defmodule TrucoOn.Application do
  @moduledoc """
  Sobe os processos de acordo com o papel do nó (`ROLE`):

    * `control` — GroupManager + Verifier (o "servidor" do MPComm), com as
      portas TCP abertas e também acessíveis por RPC.
    * `peer` — um peer do grupo (multicast UDP + réplica) e o servidor
      web/WebSocket para os jogadores.
    * `none` — só a infraestrutura (usado nos testes, que sobem peers à mão).
  """

  use Application
  require Logger

  alias TrucoOn.Config

  @impl true
  def start(_type, _args) do
    base = [
      TrucoOnWeb.Telemetry,
      {Phoenix.PubSub, name: TrucoOn.PubSub},
      {Registry, keys: :unique, name: TrucoOn.Peer.Registry}
    ]

    # Carrega todos os módulos já no boot. O transporte socket desserializa
    # com `binary_to_term(bin, [:safe])`, que recusa átomos inexistentes; em
    # dev os módulos são carregados sob demanda, e um pedido como
    # `{:start_bench, ...}` seria rejeitado se `TrucoOn.Peer.Control` ainda
    # não tivesse sido carregado (é ele que "cria" o átomo :start_bench).
    for mod <- Application.spec(:truco_on, :modules) || [], do: Code.ensure_loaded(mod)

    role = Config.role()

    Logger.info(
      "TrucoON: papel=#{role} controle=#{Config.control_transport()} ordenação=#{Config.ordering()}"
    )

    children = base ++ role_children(role)
    Supervisor.start_link(children, strategy: :one_for_one, name: TrucoOn.Supervisor)
  end

  defp role_children(:control) do
    # As portas TCP ficam sempre abertas (mesmo com CONTROL=rpc) para que
    # `V.transport_benchmark/1` possa comparar os dois transportes.
    sockets = [
      Supervisor.child_spec(
        {TrucoOn.Control.SocketServer,
         port: Config.get(:gm_port), module: TrucoOn.Control.GroupManager, name: :gm_socket},
        id: :gm_socket
      ),
      Supervisor.child_spec(
        {TrucoOn.Control.SocketServer,
         port: Config.get(:verifier_port),
         module: TrucoOn.Control.Verifier,
         name: :verifier_socket},
        id: :verifier_socket
      )
    ]

    [TrucoOn.Control.GroupManager, TrucoOn.Control.Verifier] ++ sockets
  end

  defp role_children(:peer), do: [{TrucoOn.Peer, Config.peer_opts()}, TrucoOnWeb.Endpoint]
  defp role_children(:none), do: [TrucoOnWeb.Endpoint]

  @impl true
  def config_change(changed, _new, removed) do
    TrucoOnWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
