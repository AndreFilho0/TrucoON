defmodule TrucoOn.Control.Verifier do
  @moduledoc """
  Coordenador dos experimentos e **verificador de consistência** (o
  `comparisonServer.py` do MPComm, ampliado).

  Use no IEx do nó de controle:

      V.bench(50)          # cada peer envia 50 mensagens; compara as ordens
      V.replicas()         # compara o estado das réplicas de truco
      V.stats()            # mensagens enviadas por tipo, em cada peer
      V.faults(0.1, 0, 80) # 10% de perda e 0–80 ms de atraso em todos
      V.interactive()      # laço igual ao original ("Enter the number of messages...")

  Cenários de truco ficam em `TrucoOn.Control.Scenario`.
  """

  use GenServer
  require Logger

  alias TrucoOn.Control.{Client, Compare, GroupManager}

  @bench_timeout 180_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  ## Pedidos remotos (socket ou RPC) -------------------------------------------

  def handle(_inst, {:bench_log, run_id, peer_id, log}) do
    GenServer.cast(__MODULE__, {:bench_log, run_id, peer_id, log})
    :ok
  end

  def handle(_inst, :ping), do: :pong
  def handle(_inst, other), do: {:error, {:unknown_request, other}}

  ## API de uso (IEx) ----------------------------------------------------------

  @doc "Peers registrados no GroupManager."
  def peers do
    {:ok, members} = GroupManager.list()
    members
  end

  @doc """
  Roda o experimento do MPComm: cada peer multicasta `n` mensagens e
  devolve a ordem em que as recebeu. Imprime e devolve o relatório.
  """
  def bench(n, opts \\ []) do
    case GenServer.call(__MODULE__, {:bench, n, opts}, @bench_timeout + 5_000) do
      {:error, _} = err ->
        err

      report ->
        unless opts[:quiet], do: print_bench(report)
        report
    end
  end

  @doc "Laço interativo igual ao do `comparisonServer.py`."
  def interactive do
    case IO.gets("Número de mensagens que cada peer envia (0 para sair) => ") do
      :eof ->
        :ok

      line ->
        case Integer.parse(String.trim(line)) do
          {0, _} -> :ok
          {n, _} when n > 0 -> bench(n) && interactive()
          _ -> interactive()
        end
    end
  end

  @doc "Compara o estado das réplicas de truco de todos os peers."
  def replicas(opts \\ []) do
    digests = collect(:replica_digest)
    logs = collect(:replica_log) |> Map.new(fn {id, log} -> {id, Enum.map(log, & &1.uid)} end)

    report =
      digests
      |> Compare.replicas()
      |> Map.put(:command_order, Compare.sequences(logs))

    unless opts[:quiet], do: print_replicas(report)
    report
  end

  @doc "Estatísticas de envio do multicast em cada peer."
  def stats do
    collect(:stats)
  end

  @doc """
  Mensagens de protocolo por multicast, somando todos os peers (sem contar
  ACKs/retransmissões do canal confiável, que aparecem separados).
  """
  def message_cost(stats \\ nil) do
    stats = stats || stats()
    total = fn key -> stats |> Map.values() |> Enum.map(&Map.get(&1, key, 0)) |> Enum.sum() end
    multicasts = max(total.("multicasts"), 1)

    protocol =
      stats
      |> Map.values()
      |> Enum.flat_map(&Map.to_list/1)
      |> Enum.filter(fn {k, _} -> String.starts_with?(k, "sent.msg.") end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()

    %{
      multicasts: total.("multicasts"),
      protocol_messages: protocol,
      protocol_per_multicast: Float.round(protocol / multicasts, 2),
      udp_packets: total.("sent.udp"),
      udp_per_multicast: Float.round(total.("sent.udp") / multicasts, 2),
      acks: total.("sent.acks"),
      retransmissions: total.("sent.retransmissions"),
      dropped_by_fault: total.("sent.dropped_by_fault")
    }
  end

  @doc """
  **Parte 1a**: mede o tempo de ida e volta de `n` pedidos `:ping` a cada
  peer pelos dois transportes (socket TCP e RPC). O RPC só funciona se os
  peers rodam com distribuição Erlang (`CONTROL=rpc` no `scripts/up.sh`).
  """
  def transport_benchmark(n \\ 300) do
    members = peers()

    result =
      Map.new([:socket, :rpc], fn transport ->
        samples =
          for m <- members, _ <- 1..n do
            t0 = System.monotonic_time(:microsecond)
            reply = Client.request(Client.peer(m), :ping, transport: transport, timeout: 2_000)
            {System.monotonic_time(:microsecond) - t0, reply == :pong}
          end

        ok = for {us, true} <- samples, do: us
        sorted = Enum.sort(ok)

        stats =
          if ok == [] do
            %{ok: 0, failed: length(samples)}
          else
            %{
              ok: length(ok),
              failed: length(samples) - length(ok),
              avg_us: div(Enum.sum(ok), length(ok)),
              p50_us: Enum.at(sorted, div(length(sorted), 2)),
              p99_us: Enum.at(sorted, min(length(sorted) - 1, trunc(length(sorted) * 0.99)))
            }
          end

        {transport, stats}
      end)

    IO.puts("\n── Socket TCP × RPC (#{n} pings por peer) ──")

    for {t, s} <- result do
      IO.puts("  #{pad(t, 6)}: #{inspect(s)}")
    end

    result
  end

  @doc "Configura perda e atraso artificiais em todos os peers."
  def faults(loss, delay_min \\ 0, delay_max \\ 0) do
    collect({:set_faults, %{loss: loss, delay_min: delay_min, delay_max: delay_max}})
  end

  @doc "Envia `req` a todos os peers em paralelo; devolve `%{peer_id => resposta}`."
  def collect(req, members \\ nil) do
    (members || peers())
    |> Task.async_stream(fn m -> {m.id, Client.request(Client.peer(m), req)} end,
      timeout: 30_000,
      max_concurrency: 32
    )
    |> Map.new(fn {:ok, pair} -> pair end)
  end

  ## GenServer -----------------------------------------------------------------

  @impl true
  def init(:ok), do: {:ok, %{run: nil, next_run: 1}}

  @impl true
  def handle_call({:bench, _n, _opts}, _from, %{run: run} = state) when run != nil,
    do: {:reply, {:error, :bench_running}, state}

  def handle_call({:bench, n, _opts}, from, state) do
    case peers() do
      [] -> {:reply, {:error, :no_peers}, state}
      members -> start_bench(members, n, from, state)
    end
  end

  defp start_bench(members, n, from, state) do
    run_id = state.next_run
    Logger.info("[verifier] run #{run_id}: #{length(members)} peers × #{n} mensagens")

    started =
      members
      |> Task.async_stream(
        fn m -> {m.id, Client.request(Client.peer(m), {:start_bench, run_id, n})} end,
        timeout: 15_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    failed = Enum.reject(started, fn {_id, r} -> r == :ok end)

    if failed != [] do
      {:reply, {:error, {:start_failed, failed}}, %{state | next_run: run_id + 1}}
    else
      timer = Process.send_after(self(), {:bench_timeout, run_id}, @bench_timeout)

      run = %{
        id: run_id,
        n: n,
        ids: Enum.map(members, & &1.id),
        logs: %{},
        from: from,
        timer: timer,
        t0: System.monotonic_time(:millisecond)
      }

      {:noreply, %{state | run: run, next_run: run_id + 1}}
    end
  end

  @impl true
  def handle_cast({:bench_log, run_id, peer_id, log}, %{run: %{id: run_id} = run} = state) do
    run = %{run | logs: Map.put(run.logs, peer_id, log)}

    if map_size(run.logs) == length(run.ids) do
      Process.cancel_timer(run.timer)
      {:noreply, finish_bench(%{state | run: run})}
    else
      {:noreply, %{state | run: run}}
    end
  end

  def handle_cast({:bench_log, _run_id, _peer, _log}, state), do: {:noreply, state}

  @impl true
  def handle_info({:bench_timeout, run_id}, %{run: %{id: run_id}} = state) do
    Logger.warning("[verifier] run #{run_id}: timeout; comparando logs parciais")
    {:noreply, finish_bench(state)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp finish_bench(%{run: run} = state) do
    elapsed = System.monotonic_time(:millisecond) - run.t0
    stats = collect(:stats)

    report =
      run.logs
      |> Compare.bench(run.ids, run.n)
      |> Map.merge(%{
        run_id: run.id,
        n: run.n,
        peers: run.ids,
        mode: TrucoOn.Config.ordering(),
        elapsed_ms: elapsed,
        logs_received: map_size(run.logs),
        cost: message_cost(stats)
      })

    GenServer.reply(run.from, report)
    %{state | run: nil}
  end

  ## Impressão -----------------------------------------------------------------

  defp print_bench(%{per_peer: per_peer} = r) do
    IO.puts("""

    ── Experimento #{r.run_id} ── #{length(r.peers)} peers × #{r.n} mensagens (#{r.elapsed_ms} ms)
    Esperado por peer: #{r.expected_per_peer} mensagens. Logs recebidos: #{r.logs_received}/#{length(r.peers)}
    """)

    IO.puts("  peer  entregues  perdidas  duplicadas  violações FIFO")

    for {id, p} <- Enum.sort(per_peer) do
      IO.puts(
        "  #{pad(id, 4)}  #{pad(p.delivered, 9)}  #{pad(p.missing, 8)}  #{pad(p.duplicates, 10)}  #{pad(p.fifo_violations, 14)}"
      )
    end

    c = r.cost

    IO.puts("""

    Rodadas fora de ordem (métrica do MPComm): #{r.unordered_rounds} de #{r.positions}
    Todos entregaram a mesma sequência? #{yes(r.identical)}
    Custo: #{c.protocol_per_multicast} msgs de protocolo/multicast, #{c.udp_per_multicast} datagramas UDP/multicast
           (acks #{c.acks}, retransmissões #{c.retransmissions}, descartados pela injeção de falhas #{c.dropped_by_fault})
    """)
  end

  defp print_replicas(r) do
    IO.puts("""

    ── Réplicas ──
    Mesas: #{r.rooms}   Mesas divergentes: #{length(r.divergent_rooms)} #{inspect(r.divergent_rooms)}
    Comandos aplicados por peer: #{inspect(r.applied)}
    Mesma ordem de comandos em todos? #{yes(r.same_command_order)} (posições diferentes: #{r.command_order.unordered_rounds})
    Réplicas consistentes? #{yes(r.consistent)}
    """)
  end

  defp yes(true), do: "SIM"
  defp yes(false), do: "NÃO"

  defp pad(v, n), do: v |> to_string() |> String.pad_leading(n)
end
