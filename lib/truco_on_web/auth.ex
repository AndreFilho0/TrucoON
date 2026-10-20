defmodule TrucoOnWeb.Auth do
  @moduledoc """
  Identidade de **convidado**: quem abre o link escolhe um apelido e recebe
  um token assinado (`Phoenix.Token`, HMAC com o `secret_key_base`).

  Todos os peers usam o mesmo `secret_key_base`, então um token emitido
  por um peer vale em qualquer outro — o jogador pode trocar de servidor
  (região) sem criar conta.
  """

  @salt "player"
  @max_age 60 * 60 * 24 * 30

  def new_player(name) do
    name = name |> to_string() |> String.trim() |> String.slice(0, 20)

    if name == "" do
      {:error, :invalid_name}
    else
      id = :crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false)
      player = %{id: id, name: name}
      {:ok, player, Phoenix.Token.sign(TrucoOnWeb.Endpoint, @salt, player)}
    end
  end

  def verify(token) when is_binary(token) do
    Phoenix.Token.verify(TrucoOnWeb.Endpoint, @salt, token, max_age: @max_age)
  end

  def verify(_), do: {:error, :missing}

  @doc "Lê o token do cabeçalho `Authorization: Bearer ...`."
  def from_conn(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> verify(token)
      _ -> {:error, :missing}
    end
  end
end
