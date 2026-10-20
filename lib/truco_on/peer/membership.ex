defmodule TrucoOn.Peer.Membership do
  @moduledoc """
  Entrada do peer no grupo, via **serviço de nomes/descoberta** (GroupManager).

  1. Registra o peer (IP, portas, nome do nó) e recebe seu **id**.
  2. Consulta a lista até haver `GROUP_SIZE` membros.
  3. Entrega o grupo (*view*) ao Multicast.

  No MPComm esta espera era um laço ativo (`while handShakeCount < N: pass`),
  que gasta 100% de uma CPU. Aqui é um timer: o processo dorme entre as
  consultas. Se o GroupManager não responde, tenta de novo (o peer pode
  subir antes do servidor). Ao terminar, o peer se desregistra.
  """

  use GenServer
  require Logger

  alias TrucoOn.Control.{Client, SocketServer}
  alias TrucoOn.Peer
  alias TrucoOn.Peer.Multicast

  @retry_ms 1_000
  @poll_ms 300

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Peer.via(opts[:inst], :membership))

  @doc "Dados do próprio peer e do grupo."
  def info(inst), do: GenServer.call(Peer.via(inst, :membership), :info)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    send(self(), :register)
    {:ok, %{opts: opts, me: nil, view: nil}}
  end

  @impl true
  def handle_call(:info, _from, state), do: {:reply, %{me: state.me, view: state.view}, state}

  @impl true
  def handle_info(:register, %{opts: opts} = state) do
    inst = opts[:inst]

    ctrl_port = SocketServer.port(Peer.via(inst, :ctrl))

    info = %{
      host: opts[:host],
      udp_port: Multicast.port(inst),
      ctrl_port: ctrl_port,
      http_port: opts[:http_port],
      node: Atom.to_string(node()),
      inst: inst,
      region: opts[:region]
    }

    case Client.request(opts[:gm], {:register, info}, transport: opts[:transport]) do
      {:ok, me} ->
        Logger.info("[membership] registrado como peer #{me.id}")
        send(self(), :poll)
        {:noreply, %{state | me: me}}

      other ->
        Logger.warning(
          "[membership] GroupManager indisponível (#{inspect(other)}); tentando de novo"
        )

        Process.send_after(self(), :register, @retry_ms)
        {:noreply, state}
    end
  end

  def handle_info(:poll, %{opts: opts, me: me} = state) do
    group_size = opts[:group_size]

    case Client.request(opts[:gm], :list, transport: opts[:transport]) do
      {:ok, members} when length(members) >= group_size ->
        view = Enum.take(members, opts[:group_size])

        if Enum.any?(view, &(&1.id == me.id)) do
          :ok = Multicast.set_view(opts[:inst], me.id, view)
          {:noreply, %{state | view: view}}
        else
          Logger.warning("[membership] grupo já tem #{opts[:group_size]} peers; aguardando vaga")
          Process.send_after(self(), :poll, @retry_ms)
          {:noreply, state}
        end

      {:ok, _members} ->
        Process.send_after(self(), :poll, @poll_ms)
        {:noreply, state}

      other ->
        Logger.warning("[membership] falha ao listar peers: #{inspect(other)}")
        Process.send_after(self(), :poll, @retry_ms)
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, %{me: %{id: id}, opts: opts}) do
    Client.request(opts[:gm], {:unregister, id}, transport: opts[:transport], timeout: 1_000)
  end

  def terminate(_reason, _state), do: :ok
end
