defmodule TrucoOn.Config do
  @moduledoc "Leitura da configuração (definida em `config/runtime.exs`)."

  def get(key, default \\ nil), do: Application.get_env(:truco_on, key, default)

  def role, do: get(:role, :none)
  def control_transport, do: get(:control_transport, :rpc)
  def ordering, do: get(:ordering, :fifo)
  def group_size, do: get(:group_size, 3)

  @doc "Opções do peer principal deste nó (instância `:main`)."
  def peer_opts do
    peer = get(:peer, [])

    [
      inst: :main,
      host: peer[:host] || "127.0.0.1",
      udp_port: peer[:udp_port] || 6789,
      ctrl_port: peer[:ctrl_port] || 5679,
      http_port: peer[:http_port] || 4000,
      region: peer[:region] || "local",
      loss: peer[:loss] || 0.0,
      delay_min: peer[:delay_min] || 0,
      delay_max: peer[:delay_max] || 0,
      ordering: ordering(),
      group_size: group_size(),
      transport: control_transport(),
      gm: TrucoOn.Control.Client.group_manager(),
      verifier: TrucoOn.Control.Client.verifier()
    ]
  end
end
