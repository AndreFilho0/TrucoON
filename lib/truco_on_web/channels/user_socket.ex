defmodule TrucoOnWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", TrucoOnWeb.RoomChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case TrucoOnWeb.Auth.verify(token) do
      {:ok, player} -> {:ok, assign(socket, :player, player)}
      {:error, _} -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "player:#{socket.assigns.player.id}"
end
