defmodule TrucoOnWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :truco_on

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_truco_on_key",
    signing_salt: "GjcSLxnw",
    same_site: "Lax"
  ]

  # WebSocket dos jogadores (Phoenix Channels)
  socket "/socket", TrucoOnWeb.UserSocket, websocket: true, longpoll: false

  # Painel ao vivo do multicast (/painel): WebSocket só de leitura, a
  # página com seus arquivos e o cliente JS de Channels do próprio Phoenix.
  socket "/painel/socket", TrucoOnWeb.PainelSocket, websocket: true, longpoll: false
  plug Plug.Static, at: "/painel/assets", from: {:truco_on, "priv/painel"}, gzip: false

  plug Plug.Static,
    at: "/painel/vendor",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.min.js)

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :truco_on,
    gzip: false,
    only: TrucoOnWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug TrucoOnWeb.CORS
  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug TrucoOnWeb.Router
end
