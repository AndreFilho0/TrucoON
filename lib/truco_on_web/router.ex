defmodule TrucoOnWeb.Router do
  use TrucoOnWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Rotas da aplicação (REST e frontend) chegam na Parte 2.
  scope "/api", TrucoOnWeb do
    pipe_through :api
  end
end
