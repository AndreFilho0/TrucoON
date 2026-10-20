defmodule TrucoOn.Control.Client do
  @moduledoc """
  Cliente das interações **cliente-servidor** do sistema (Parte 1a).

  No MPComm original toda interação com o GroupManager e com o servidor de
  comparação era feita à mão com sockets TCP + `pickle`. Aqui o mesmo pedido
  (um termo Elixir, ex.: `{:register, info}`) pode ir por dois transportes,
  escolhidos pela variável `CONTROL`:

    * `:socket` — conexão TCP, mensagem com prefixo de tamanho de 4 bytes
      (`packet: 4`) e serialização com `:erlang.term_to_binary/1` (o
      equivalente do `pickle`). Tudo explícito: conectar, enviar, esperar a
      resposta, fechar, tratar cada erro.
    * `:rpc` — **chamada remota de procedimento** com `:erpc.call/5`: o
      chamador escreve `módulo.função(args)` e o runtime do Erlang cuida de
      conexão, serialização, envio, espera e propagação de erros.

  Do lado do servidor, os dois transportes chegam na **mesma função**
  `handle(inst, pedido)` do módulo alvo. Assim a comparação entre eles é
  justa: só muda o transporte.
  """

  alias TrucoOn.Config

  defmodule Target do
    @moduledoc "Endereço de um servidor de controle nos dois transportes."
    defstruct [:node, :host, :port, :module, inst: nil]

    @type t :: %__MODULE__{
            node: node | nil,
            host: String.t() | nil,
            port: non_neg_integer | nil,
            module: module,
            inst: term
          }
  end

  @default_timeout 10_000

  @doc """
  Envia `req` para `target` e devolve a resposta do servidor.
  Em falha de comunicação devolve `{:error, {:transport, motivo}}`.
  """
  def request(%Target{} = target, req, opts \\ []) do
    transport = Keyword.get(opts, :transport, Config.control_transport())
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case transport do
      :rpc -> rpc(target, req, timeout)
      :socket -> socket(target, req, timeout)
    end
  end

  ## RPC -----------------------------------------------------------------------

  defp rpc(%Target{node: node, module: mod, inst: inst}, req, timeout) do
    :erpc.call(node, mod, :handle, [inst, req], timeout)
  catch
    :error, {:erpc, reason} -> {:error, {:transport, reason}}
    kind, reason -> {:error, {:transport, {kind, reason}}}
  end

  ## Socket TCP ---------------------------------------------------------------

  @tcp_opts [:binary, packet: 4, active: false]

  defp socket(%Target{host: host, port: port}, req, timeout) do
    case :gen_tcp.connect(String.to_charlist(host), port, @tcp_opts, timeout) do
      {:ok, sock} ->
        try do
          with :ok <- :gen_tcp.send(sock, :erlang.term_to_binary(req)),
               {:ok, bin} <- :gen_tcp.recv(sock, 0, timeout) do
            decode(bin)
          else
            {:error, reason} -> {:error, {:transport, reason}}
          end
        after
          :gen_tcp.close(sock)
        end

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  @doc """
  Desserializa com `:safe`: recusa termos que criariam átomos novos ou
  funções. (No MPComm, `pickle.loads` em dados vindos da rede permite
  execução de código arbitrário.)
  """
  def decode(bin) do
    :erlang.binary_to_term(bin, [:safe])
  rescue
    ArgumentError -> {:error, {:transport, :bad_payload}}
  end

  ## Alvos conhecidos ----------------------------------------------------------

  def group_manager do
    %Target{
      node: Config.get(:control_node),
      host: Config.get(:control_host),
      port: Config.get(:gm_port),
      module: TrucoOn.Control.GroupManager
    }
  end

  def verifier do
    %Target{
      node: Config.get(:control_node),
      host: Config.get(:control_host),
      port: Config.get(:verifier_port),
      module: TrucoOn.Control.Verifier
    }
  end

  @doc "Alvo de controle de um peer a partir do registro no GroupManager."
  def peer(member) do
    %Target{
      # o nome do nó viaja como string: com `binary_to_term(..., [:safe])` o
      # servidor socket recusaria criar o átomo de um nó que nunca viu.
      node: member.node && String.to_atom(member.node),
      host: member.host,
      port: member.ctrl_port,
      module: TrucoOn.Peer.Control,
      inst: member.inst
    }
  end
end
