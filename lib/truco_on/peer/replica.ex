defmodule TrucoOn.Peer.Replica do
  @moduledoc """
  **Réplica** da base de mesas neste peer (Parte 2).

  Toda alteração segue o mesmo caminho, inclusive as feitas por jogadores
  ligados a este peer:

      jogador ──WebSocket──► submit(cmd)
                                │ multicast {:cmd, uid, cmd}
                                ▼
                 (rede + protocolo de ordenação)
                                │ entrega (na ordem da política)
                                ▼
      deliver ──► Rooms.apply ──► novo estado ──► ETS + PubSub local
                                └─► responde a quem fez submit (se foi aqui)

  Ou seja: o peer **não aplica** o comando do próprio jogador na hora; ele
  espera a entrega pelo multicast, como todas as outras réplicas. Assim, se
  a política garante ordem total, todas aplicam exatamente a mesma
  sequência e terminam no mesmo estado.

  ## Estado com e sem processo (ETS)

  O GenServer é o **único escritor** do estado. Cada mesa também é
  publicada numa tabela **ETS** (`:protected`, `read_concurrency`), de onde
  os canais WebSocket leem a visão sem passar pela fila de mensagens do
  processo: muitos leitores em paralelo, um escritor. A ETS é local ao nó —
  não é replicada; quem replica é o protocolo de multicast.

  ## Verificação

  `digest/1` resume a réplica: número de comandos aplicados, um hash
  encadeado da sequência de comandos (muda se a **ordem** mudar) e um hash
  do estado de cada mesa. O Verifier compara esses resumos entre os peers.
  """

  use GenServer
  require Logger

  alias TrucoOn.Peer
  alias TrucoOn.Peer.Multicast
  alias TrucoOn.Truco.Rooms

  @submit_timeout 15_000
  @max_log 20_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Peer.via(opts[:inst], :replica))

  ## API -----------------------------------------------------------------------

  @doc """
  Envia `cmd` ao grupo e espera a **própria réplica** aplicá-lo. Devolve o
  resultado da aplicação (`{:ok, valor}` ou `{:error, motivo}`).
  """
  def submit(inst, cmd, timeout \\ @submit_timeout) do
    GenServer.call(Peer.via(inst, :replica), {:submit, cmd}, timeout)
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  def deliver(inst, delivery), do: GenServer.cast(Peer.via(inst, :replica), {:deliver, delivery})

  @doc "Lê uma mesa direto da ETS (sem passar pelo processo)."
  def get_room(inst, code) do
    case :ets.lookup(table(inst), code) do
      [{^code, room}] -> room
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  def view(inst, code, player_id) do
    case get_room(inst, code) do
      nil -> nil
      room -> Rooms.view(room, player_id)
    end
  end

  def preview(inst, code) do
    case get_room(inst, code) do
      nil -> nil
      room -> Rooms.preview(room)
    end
  end

  def digest(inst), do: GenServer.call(Peer.via(inst, :replica), :digest)
  def log(inst), do: GenServer.call(Peer.via(inst, :replica), :log)

  @doc "Tópico do PubSub local onde saem as atualizações da mesa `code`."
  def topic(inst, code), do: "replica:#{inst}:room:#{code}"

  ## Init ----------------------------------------------------------------------

  @impl true
  def init(opts) do
    inst = Keyword.fetch!(opts, :inst)
    tab = :ets.new(table(inst), [:named_table, :protected, :set, read_concurrency: true])

    {:ok,
     %{
       inst: inst,
       tab: tab,
       rooms: %{},
       applied: 0,
       chain: <<0::256>>,
       log: [],
       waiters: %{}
     }}
  end

  defp table(inst), do: :"truco_rooms_#{inst}"

  ## Callbacks -----------------------------------------------------------------

  @impl true
  def handle_call({:submit, cmd}, from, state) do
    uid = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    {:ok, _} = Multicast.multicast(state.inst, {:cmd, uid, cmd})
    {:noreply, %{state | waiters: Map.put(state.waiters, uid, {from, now()})}}
  end

  def handle_call(:digest, _from, state) do
    rooms =
      Map.new(state.rooms, fn {code, room} -> {code, hash(room)} end)

    digest = %{
      applied: state.applied,
      chain: Base.encode16(state.chain, case: :lower),
      state_hash: hash(state.rooms) |> binary_part(0, 16),
      rooms: rooms
    }

    {:reply, digest, state}
  end

  def handle_call(:log, _from, state), do: {:reply, Enum.reverse(state.log), state}

  @impl true
  def handle_cast({:deliver, %{payload: {:cmd, uid, cmd}} = d}, state) do
    {rooms, code, result, events} = Rooms.apply(state.rooms, cmd)

    # ETS: publica a nova versão (ou remove a mesa fechada)
    case Map.fetch(rooms, code) do
      {:ok, room} -> :ets.insert(state.tab, {code, room})
      :error -> if code, do: :ets.delete(state.tab, code)
    end

    # local_broadcast: avisa só os jogadores ligados a ESTE peer. O PubSub do
    # Phoenix é distribuído por padrão; com os nós Erlang conectados (modo
    # RPC), um broadcast comum chegaria aos canais dos outros peers e cada
    # jogador receberia a mesma atualização N vezes — além de mascarar a
    # replicação, que deve acontecer só pelo nosso multicast.
    if code && match?({:ok, _}, result) do
      Phoenix.PubSub.local_broadcast(
        TrucoOn.PubSub,
        topic(state.inst, code),
        {:room_updated, code, events}
      )
    end

    {waiter, waiters} = Map.pop(state.waiters, uid)
    if waiter, do: GenServer.reply(elem(waiter, 0), result)

    entry = %{
      uid: uid,
      origin: d.origin,
      cmd: elem(cmd, 0),
      code: code,
      ok: match?({:ok, _}, result)
    }

    state = %{
      state
      | rooms: rooms,
        applied: state.applied + 1,
        chain: :crypto.hash(:sha256, state.chain <> uid),
        log: Enum.take([entry | state.log], @max_log),
        waiters: expire(waiters)
    }

    {:noreply, state}
  end

  defp expire(waiters) do
    limit = now() - @submit_timeout
    Map.reject(waiters, fn {_uid, {_from, t}} -> t < limit end)
  end

  defp hash(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp now, do: System.monotonic_time(:millisecond)
end
