defmodule TrucoOnWeb.SpaController do
  use TrucoOnWeb, :controller

  def index(conn, _params) do
    path = Application.app_dir(:truco_on, "priv/static/index.html")

    if File.exists?(path) do
      conn |> put_resp_content_type("text/html") |> send_file(200, path)
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "TrucoON peer no ar. Frontend não exportado (rode scripts/build_web.sh).")
    end
  end
end
