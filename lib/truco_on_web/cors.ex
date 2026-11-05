defmodule TrucoOnWeb.CORS do
  @moduledoc """
  Libera chamadas do frontend servido em outra origem (ex.: Expo Web em
  `localhost:8081` falando com o peer em `localhost:4001`).
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-headers", "authorization, content-type")
      |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")

    if conn.method == "OPTIONS", do: conn |> send_resp(204, "") |> halt(), else: conn
  end
end
