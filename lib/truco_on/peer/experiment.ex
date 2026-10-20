defmodule TrucoOn.Peer.Experiment do
  @moduledoc """
  O experimento original do MPComm, mantido para medir os protocolos.

  Ao receber o sinal de início do Verifier, o peer envia `n` mensagens
  numeradas `{origem, k}` ao grupo, com intervalo aleatório de 10–100 ms
  (como no original), seguidas de uma mensagem de fim. Registra cada
  mensagem **na ordem em que foi entregue**, grava o log em
  `tmp/logs/` e envia o log ao Verifier, que compara as ordens.

  Fim do experimento: quando chegaram as mensagens de fim de todos os
  peers, ou — no modo `:none`, em que mensagens de fim podem se perder —
  depois de 3 s sem receber nada.
  """

  use GenServer
  require Logger

  alias TrucoOn.Control.Client
  alias TrucoOn.Peer
  alias TrucoOn.Peer.Multicast

  @idle_ms 3_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Peer.via(opts[:inst], :experiment))

  @doc "Sinal de início (vem do Verifier)."
  def start(inst, run_id, n_msgs, my_id, group_ids),
    do: GenServer.call(Peer.via(inst, :experiment), {:start, run_id, n_msgs, my_id, group_ids})

  def deliver(inst, delivery),
    do: GenServer.cast(Peer.via(inst, :experiment), {:deliver, delivery})

  @impl true
  def init(opts), do: {:ok, %{opts: opts, run: nil}}

  @impl true
  def handle_call({:start, run_id, n, my_id, ids}, _from, state) do
    inst = state.opts[:inst]
    Logger.info("[experimento] run #{run_id}: enviando #{n} mensagens")

    # o envio roda num processo à parte, para continuar recebendo
    spawn_link(fn ->
      for k <- 1..n//1 do
        Process.sleep(Enum.random(10..100))
        Multicast.multicast(inst, {:bench, run_id, my_id, k})
      end

      Multicast.multicast(inst, {:bench_stop, run_id, my_id})
      GenServer.cast(Peer.via(inst, :experiment), {:sent_all, run_id})
    end)

    run = %{
      id: run_id,
      my_id: my_id,
      ids: ids,
      log: [],
      stops: MapSet.new(),
      sent_all: false,
      last_rx: now(),
      done: false
    }

    {:reply, :ok, %{state | run: run}}
  end

  @impl true
  def handle_cast({:deliver, %{payload: payload}}, %{run: %{id: run_id} = run} = state) do
    run =
      case payload do
        {:bench, ^run_id, origin, k} ->
          %{run | log: [{origin, k} | run.log], last_rx: now()}

        {:bench_stop, ^run_id, origin} ->
          %{run | stops: MapSet.put(run.stops, origin), last_rx: now()}

        _ ->
          run
      end

    {:noreply, maybe_finish(%{state | run: run})}
  end

  def handle_cast({:deliver, _}, state), do: {:noreply, state}

  def handle_cast({:sent_all, run_id}, %{run: %{id: run_id} = run} = state) do
    Process.send_after(self(), {:idle_check, run_id}, @idle_ms)
    {:noreply, maybe_finish(%{state | run: %{run | sent_all: true}})}
  end

  def handle_cast({:sent_all, _}, state), do: {:noreply, state}

  @impl true
  def handle_info({:idle_check, run_id}, %{run: %{id: run_id, done: false} = run} = state) do
    if now() - run.last_rx >= @idle_ms do
      Logger.warning("[experimento] run #{run_id}: sem mensagens há #{@idle_ms} ms; encerrando")
      {:noreply, finish(state)}
    else
      Process.send_after(self(), {:idle_check, run_id}, @idle_ms)
      {:noreply, state}
    end
  end

  def handle_info({:idle_check, _}, state), do: {:noreply, state}

  defp maybe_finish(%{run: run} = state) do
    if not run.done and run.sent_all and MapSet.size(run.stops) == length(run.ids),
      do: finish(state),
      else: state
  end

  defp finish(%{run: run, opts: opts} = state) do
    log = Enum.reverse(run.log)
    write_log_file(run, log)

    req = {:bench_log, run.id, run.my_id, log}

    Task.start(fn ->
      Client.request(opts[:verifier], req, transport: opts[:transport])
    end)

    Logger.info("[experimento] run #{run.id}: #{length(log)} mensagens entregues; log enviado")
    %{state | run: %{run | done: true}}
  end

  defp write_log_file(run, log) do
    dir = Path.join(File.cwd!(), "tmp/logs")
    File.mkdir_p!(dir)

    File.write!(
      Path.join(dir, "peer#{run.my_id}-run#{run.id}.log"),
      inspect(log, limit: :infinity)
    )
  rescue
    _ -> :ok
  end

  defp now, do: System.monotonic_time(:millisecond)
end
