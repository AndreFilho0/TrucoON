import Config

# Toda a configuração do TrucoON vem de variáveis de ambiente, para que o
# mesmo código rode como nó de controle (GroupManager + Verifier) ou como
# peer, em qualquer máquina, sem IP fixo no código (no MPComm original os
# endereços ficavam hard-coded em constMP.py).
#
# Variáveis (com o default entre parênteses):
#
#   ROLE           control | peer                           (peer)
#   CONTROL        rpc | socket — transporte cliente-servidor (rpc)
#   ORDERING       none | fifo                               (fifo)
#   GROUP_SIZE     número de peers no grupo                  (3)
#   CONTROL_NODE   nome do nó de controle, modo rpc          (control@127.0.0.1)
#   CONTROL_HOST   IP do nó de controle, modo socket         (127.0.0.1)
#   GM_PORT        porta TCP do GroupManager                 (5680)
#   VERIFIER_PORT  porta TCP do Verifier                     (5678)
#   PEER_HOST      IP que o peer anuncia aos outros          (127.0.0.1)
#   UDP_PORT       porta UDP do multicast                    (6789)
#   CTRL_PORT      porta TCP de controle do peer (socket)    (5679)
#   PORT           porta HTTP/WebSocket do peer              (4000)
#   REGION         rótulo da região (só exibição)            (local)
#   LOSS           probabilidade de perder um pacote UDP     (0.0)
#   DELAY_MIN/MAX  atraso artificial por pacote, em ms       (0/0)

env = fn key, default -> System.get_env(key, default) end
int = fn key, default -> String.to_integer(System.get_env(key, to_string(default))) end

float = fn key, default ->
  case Float.parse(System.get_env(key, to_string(default))) do
    {f, _} -> f
    :error -> default
  end
end

pick = fn key, default, allowed ->
  value = System.get_env(key, default)

  case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
    nil -> raise "#{key}=#{inspect(value)} inválido; use um de #{inspect(allowed)}"
    atom -> atom
  end
end

role =
  if config_env() == :test,
    do: :none,
    else: pick.("ROLE", "peer", [:control, :peer, :none])

http_port = int.("PORT", 4000)

config :truco_on,
  role: role,
  control_transport: pick.("CONTROL", "rpc", [:rpc, :socket]),
  ordering: pick.("ORDERING", "fifo", [:none, :fifo]),
  group_size: int.("GROUP_SIZE", 3),
  control_node: String.to_atom(env.("CONTROL_NODE", "control@127.0.0.1")),
  control_host: env.("CONTROL_HOST", "127.0.0.1"),
  gm_port: int.("GM_PORT", 5680),
  verifier_port: int.("VERIFIER_PORT", 5678),
  peer: [
    host: env.("PEER_HOST", "127.0.0.1"),
    udp_port: int.("UDP_PORT", 6789),
    ctrl_port: int.("CTRL_PORT", 5679),
    http_port: http_port,
    region: env.("REGION", "local"),
    loss: float.("LOSS", 0.0),
    delay_min: int.("DELAY_MIN", 0),
    delay_max: int.("DELAY_MAX", 0)
  ]

if System.get_env("PHX_SERVER") do
  config :truco_on, TrucoOnWeb.Endpoint, server: true
end

if config_env() == :dev do
  config :truco_on, TrucoOnWeb.Endpoint, http: [ip: {0, 0, 0, 0}, port: http_port]
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"

  config :truco_on, TrucoOnWeb.Endpoint,
    url: [host: host, port: http_port],
    http: [ip: {0, 0, 0, 0}, port: http_port],
    check_origin: false,
    secret_key_base: secret_key_base
end
