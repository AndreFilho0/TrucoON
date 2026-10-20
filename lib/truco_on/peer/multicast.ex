defmodule TrucoOn.Peer.Multicast do
  @moduledoc """
  Comunicação **multicast** de um peer sobre **sockets UDP** (`:gen_udp`).

  É o equivalente das threads de envio/recepção do `peerCommunicatorUDP.py`,
  organizado em camadas:

      aplicação (Replica / Experiment)
            ▲ entregas            │ multicast(payload)
      política de ordenação  (Basic | Lamport | Sequencer)   — Partes 3 e 4
            ▲                     │
      canal confiável FIFO   (Reliable: seq, ACK, retransmissão) — Parte 1b
            ▲                     │      (desligado no modo :none)
      UDP + injeção de falhas (perda e atraso artificiais)
            ▲                     ▼
                  rede (datagramas UDP)

  "Multicast" aqui é, como no MPComm, o envio de um datagrama para cada
  membro do grupo (inclusive para si mesmo).

  ## Injeção de falhas

  Para reproduzir em uma máquina só o que acontece entre regiões
  distantes, cada datagrama enviado pode ser descartado com probabilidade
  `loss` e atrasado por um tempo aleatório entre `delay_min` e `delay_max`.
  Atrasos aleatórios por pacote fazem os datagramas chegarem **fora de
  ordem**, como na Internet.

  ## Formato dos datagramas (`term_to_binary`)

      {:r, src, inner}         UDP cru (modo :none)
      {:d, src, seq, inner}    dado do canal confiável
      {:a, src, cum}           ACK cumulativo do canal confiável
  """

  use GenServer
  require Logger

  alias TrucoOn.Multicast.{Ordering, Reliable}
  alias TrucoOn.Peer

  @tick_ms 25
  @rto_ms 150

  ## API -----------------------------------------------------------------------

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Peer.via(opts[:inst], :multicast))

  @doc "Envia `payload` ao grupo. Devolve `{:ok, msg_id}`."
  def multicast(inst, payload),
    do: GenServer.call(Peer.via(inst, :multicast), {:multicast, payload})

  @doc "Define o grupo (chamado pelo Membership quando o grupo está completo)."
  def set_view(inst, my_id, members),
    do: GenServer.call(Peer.via(inst, :multicast), {:set_view, my_id, members})

  def port(inst), do: GenServer.call(Peer.via(inst, :multicast), :port)
  def info(inst), do: GenServer.call(Peer.via(inst, :multicast), :info)
  def stats(inst), do: GenServer.call(Peer.via(inst, :multicast), :stats)
  def reset_stats(inst), do: GenServer.call(Peer.via(inst, :multicast), :reset_stats)

  def set_faults(inst, faults),
    do: GenServer.call(Peer.via(inst, :multicast), {:set_faults, faults})

  ## Init ----------------------------------------------------------------------

  @impl true
  def init(opts) do
    mode = Keyword.fetch!(opts, :ordering)

    sock_opts = [
      :binary,
      active: true,
      reuseaddr: true,
      recbuf: 4 * 1024 * 1024,
      sndbuf: 4 * 1024 * 1024
    ]

    case :gen_udp.open(Keyword.fetch!(opts, :udp_port), sock_opts) do
      {:ok, socket} ->
        {:ok, port} = :inet.port(socket)
        if Ordering.reliable?(mode), do: :timer.send_interval(@tick_ms, :tick)

        state = %{
          inst: opts[:inst],
          mode: mode,
          ord_mod: Ordering.module(mode),
          ord: nil,
          socket: socket,
          port: port,
          my_id: nil,
          ids: [],
          addrs: %{},
          ready: false,
          waiting: [],
          counter: 0,
          rel: Reliable.new(),
          faults: %{
            loss: opts[:loss] || 0.0,
            delay_min: opts[:delay_min] || 0,
            delay_max: opts[:delay_max] || 0
          },
          stats: %{}
        }

        Logger.info("[multicast] UDP na porta #{port}, modo #{mode}")
        {:ok, state}

      {:error, reason} ->
        {:stop, {:udp_open_failed, reason}}
    end
  end

  ## Calls ---------------------------------------------------------------------

  @impl true
  def handle_call({:multicast, payload}, _from, state) do
    counter = state.counter + 1
    id = {state.my_id, counter}
    state = %{state | counter: counter}

    if state.ready do
      {:reply, {:ok, id}, do_multicast(state, id, payload)}
    else
      # grupo ainda não formado: guarda e envia quando o view chegar
      {:reply, {:ok, :pending}, %{state | waiting: state.waiting ++ [payload]}}
    end
  end

  def handle_call({:set_view, my_id, members}, _from, state) do
    ids = members |> Enum.map(& &1.id) |> Enum.sort()

    addrs =
      Map.new(members, fn m ->
        {:ok, ip} = :inet.parse_address(String.to_charlist(m.host))
        {m.id, {ip, m.udp_port}}
      end)

    state = %{
      state
      | my_id: my_id,
        ids: ids,
        addrs: addrs,
        ready: true,
        ord: state.ord_mod.init(my_id, ids)
    }

    Logger.info("[multicast] grupo formado: eu=#{my_id} membros=#{inspect(ids)}")

    state =
      Enum.reduce(state.waiting, %{state | waiting: []}, fn payload, st ->
        counter = st.counter + 1
        do_multicast(%{st | counter: counter}, {my_id, counter}, payload)
      end)

    {:reply, :ok, state}
  end

  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call(:info, _from, state) do
    info = %{
      my_id: state.my_id,
      ids: state.ids,
      mode: state.mode,
      ready: state.ready,
      udp_port: state.port,
      faults: state.faults,
      sequencer:
        state.mode == :sequencer && state.ord &&
          TrucoOn.Multicast.Ordering.Sequencer.sequencer(state.ord),
      pending_acks: Reliable.pending(state.rel),
      held_back: Reliable.held_back(state.rel),
      ordering_queue: if(state.ord, do: state.ord_mod.pending(state.ord), else: 0)
    }

    {:reply, info, state}
  end

  def handle_call(:stats, _from, state), do: {:reply, state.stats, state}
  def handle_call(:reset_stats, _from, state), do: {:reply, :ok, %{state | stats: %{}}}

  def handle_call({:set_faults, faults}, _from, state) do
    faults = Map.merge(state.faults, Map.take(faults, [:loss, :delay_min, :delay_max]))
    Logger.info("[multicast] falhas: #{inspect(faults)}")
    {:reply, :ok, %{state | faults: faults}}
  end

  ## Recepção UDP ----------------------------------------------------------------

  @impl true
  def handle_info({:udp, _sock, _ip, _port, bin}, state) do
    state =
      case safe_decode(bin) do
        {:ok, packet} when state.ready and is_tuple(packet) and tuple_size(packet) >= 3 ->
          if Map.has_key?(state.addrs, elem(packet, 1)),
            do: on_packet(state, packet),
            else: bump(state, "recv.unknown_sender")

        # antes do grupo formado não sabemos responder; o remetente retransmite
        {:ok, _packet} ->
          bump(state, "recv.before_ready")

        :error ->
          bump(state, "recv.garbage")
      end

    {:noreply, state}
  end

  def handle_info(:tick, %{ready: true} = state) do
    {rel, late} = Reliable.due(state.rel, now(), @rto_ms)
    state = %{state | rel: rel}

    state =
      Enum.reduce(late, state, fn {dest, seq, inner}, st ->
        st
        |> bump("sent.retransmissions")
        |> transmit(dest, {:d, st.my_id, seq, inner})
      end)

    {:noreply, state}
  end

  def handle_info(:tick, state), do: {:noreply, state}

  def handle_info({:send_later, addr, bin}, state) do
    :gen_udp.send(state.socket, addr, bin)
    {:noreply, state}
  end

  ## Pacotes -------------------------------------------------------------------

  defp on_packet(state, {:r, src, inner}) do
    state |> bump("recv.raw") |> to_ordering(src, inner)
  end

  defp on_packet(state, {:d, src, seq, inner}) do
    {rel, delivered, cum, status} = Reliable.on_data(state.rel, src, seq, inner)

    state =
      %{state | rel: rel}
      |> bump("recv.data")
      |> bump("recv.#{status}")
      |> bump("sent.acks")
      |> transmit(src, {:a, state.my_id, cum})

    Enum.reduce(delivered, state, fn inner, st -> to_ordering(st, src, inner) end)
  end

  defp on_packet(state, {:a, src, cum}) do
    %{state | rel: Reliable.on_ack(state.rel, src, cum)} |> bump("recv.acks")
  end

  defp on_packet(state, _other), do: bump(state, "recv.garbage")

  defp to_ordering(state, src, inner) do
    {ord, sends, deliveries} = state.ord_mod.on_receive(state.ord, src, inner)
    state = send_all(%{state | ord: ord}, sends)

    Enum.each(deliveries, fn d -> Peer.dispatch(state.inst, d) end)
    bump(state, "delivered", length(deliveries))
  end

  ## Envio ---------------------------------------------------------------------

  defp do_multicast(state, id, payload) do
    {ord, sends} = state.ord_mod.multicast(state.ord, id, payload)
    %{state | ord: ord} |> bump("multicasts") |> send_all(sends)
  end

  defp send_all(state, sends) do
    Enum.reduce(sends, state, fn {target, inner}, st ->
      dests = if target == :all, do: st.ids, else: [target]
      Enum.reduce(dests, st, &send_inner(&2, &1, inner))
    end)
  end

  defp send_inner(state, dest, inner) do
    state = bump(state, "sent.msg.#{elem(inner, 0)}")

    if Ordering.reliable?(state.mode) do
      {rel, seq} = Reliable.send(state.rel, dest, inner, now())
      transmit(%{state | rel: rel}, dest, {:d, state.my_id, seq, inner})
    else
      transmit(state, dest, {:r, state.my_id, inner})
    end
  end

  # Envia de fato, aplicando perda e atraso artificiais.
  defp transmit(state, dest, packet) do
    addr = Map.fetch!(state.addrs, dest)
    bin = :erlang.term_to_binary(packet)
    %{loss: loss, delay_min: dmin, delay_max: dmax} = state.faults
    state = bump(state, "sent.udp")

    cond do
      loss > 0 and :rand.uniform() < loss ->
        bump(state, "sent.dropped_by_fault")

      dmax > 0 ->
        delay = dmin + :rand.uniform(max(dmax - dmin, 0) + 1) - 1
        Process.send_after(self(), {:send_later, addr, bin}, delay)
        state

      true ->
        :gen_udp.send(state.socket, addr, bin)
        state
    end
  end

  ## Auxiliares ----------------------------------------------------------------

  defp safe_decode(bin) do
    {:ok, :erlang.binary_to_term(bin, [:safe])}
  rescue
    ArgumentError -> :error
  end

  defp bump(state, key, n \\ 1), do: %{state | stats: Map.update(state.stats, key, n, &(&1 + n))}

  defp now, do: System.monotonic_time(:millisecond)
end
