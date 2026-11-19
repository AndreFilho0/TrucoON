defmodule TrucoOnWeb.Router do
  use TrucoOnWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", TrucoOnWeb do
    pipe_through :api

    post "/session", ApiController, :session
    get "/info", ApiController, :info
    get "/debug", ApiController, :debug
    post "/rooms", ApiController, :create_room
    get "/rooms/:code", ApiController, :show_room

    # painel: demonstração (só com PAINEL_CONTROLE=1)
    post "/painel/faults", PainelController, :faults
    post "/painel/race", PainelController, :race_setup
    post "/painel/race/seat", PainelController, :race_seat
  end

  scope "/", TrucoOnWeb do
    get "/painel", PainelController, :index
  end

  # Frontend (Expo Web exportado em priv/static): qualquer outra rota GET
  # devolve o index.html, para links como /m/K7QX-29FA funcionarem.
  scope "/", TrucoOnWeb do
    get "/*path", SpaController, :index
  end
end
