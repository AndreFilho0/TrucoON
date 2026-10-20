defmodule TrucoOn.Control.SocketServer do
  @moduledoc """
  Servidor TCP genérico do transporte `:socket` (Parte 1a).

  Faz o papel dos laços `serverSock.accept()` do MPComm: aceita conexões,
  lê **uma** mensagem (prefixo de 4 bytes com o tamanho, então nunca trunca
  como o `recv(2048)` original), chama `module.handle(inst, pedido)` e
  devolve a resposta. Cada conexão é atendida num processo próprio, então
  um cliente lento não trava os outros.
  """

  use GenServer
  require Logger

  alias TrucoOn.Control.Client

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name))
  end

  @doc "Porta efetivamente aberta (útil quando pedimos a porta 0)."
  def port(server), do: GenServer.call(server, :port)

  @impl true
  def init(opts) do
    port = Keyword.fetch!(opts, :port)
    mod = Keyword.fetch!(opts, :module)
    inst = Keyword.get(opts, :inst)

    case :gen_tcp.listen(port, [:binary, packet: 4, active: false, reuseaddr: true]) do
      {:ok, listen} ->
        {:ok, actual} = :inet.port(listen)
        acceptor = spawn_link(fn -> accept_loop(listen, mod, inst) end)
        Logger.info("[socket] #{inspect(mod)} ouvindo TCP na porta #{actual}")
        {:ok, %{listen: listen, port: actual, acceptor: acceptor}}

      {:error, reason} ->
        {:stop, {:listen_failed, port, reason}}
    end
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  @impl true
  def terminate(_reason, state), do: :gen_tcp.close(state.listen)

  defp accept_loop(listen, mod, inst) do
    case :gen_tcp.accept(listen) do
      {:ok, sock} ->
        pid = spawn(fn -> receive(do: (:go -> serve(sock, mod, inst))) end)
        :ok = :gen_tcp.controlling_process(sock, pid)
        send(pid, :go)
        accept_loop(listen, mod, inst)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.warning("[socket] accept falhou: #{inspect(reason)}")
        accept_loop(listen, mod, inst)
    end
  end

  defp serve(sock, mod, inst) do
    with {:ok, bin} <- :gen_tcp.recv(sock, 0, 10_000) do
      reply =
        case Client.decode(bin) do
          {:error, _} = err ->
            err

          req ->
            try do
              mod.handle(inst, req)
            catch
              kind, reason -> {:error, {:server, kind, reason}}
            end
        end

      :gen_tcp.send(sock, :erlang.term_to_binary(reply))
    end

    :gen_tcp.close(sock)
  end
end
