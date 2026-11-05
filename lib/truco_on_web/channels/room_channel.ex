defmodule TrucoOnWeb.RoomChannel do
  @moduledoc """
  Canal WebSocket de uma mesa (`room:<código>`). Servidor **com estado de
  sessão**: um processo por jogador conectado.

  * Ações do jogador viram comandos replicados (`Replica.submit/2`): o
    canal só responde quando a réplica deste peer aplicou o comando, na
    ordem definida pelo protocolo de multicast.
  * Quando a réplica aplica qualquer comando desta mesa (venha de que peer
    vier), o canal recebe `{:room_updated, ...}` pelo PubSub local, lê a
    visão do jogador na ETS e envia `state` ao navegador.
  """

  use TrucoOnWeb, :channel

  alias TrucoOn.Peer.Replica
  alias TrucoOn.Truco.Code

  @inst :main

  @impl true
  def join("room:" <> raw, _params, socket) do
    code = Code.normalize(raw)
    player = socket.assigns.player

    case Replica.get_room(@inst, code) do
      nil ->
        {:error, %{reason: "room_not_found"}}

      room ->
        result =
          if Enum.any?(room.members, &(&1.id == player.id)),
            do: {:ok, :member},
            else: Replica.submit(@inst, {:join, code, player})

        case result do
          {:ok, _} ->
            Phoenix.PubSub.subscribe(TrucoOn.PubSub, Replica.topic(@inst, code))
            send(self(), :push_state)
            {:ok, assign(socket, :code, code)}

          {:error, reason} ->
            {:error, %{reason: to_string(reason)}}
        end
    end
  end

  @impl true
  def handle_in(event, params, socket) do
    case command(event, params, socket) do
      nil ->
        {:reply, {:error, %{reason: "unknown_event"}}, socket}

      cmd ->
        case Replica.submit(@inst, cmd) do
          {:ok, _} -> {:reply, :ok, socket}
          {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
        end
    end
  end

  defp command(event, params, socket) do
    code = socket.assigns.code
    pid = socket.assigns.player.id

    case event do
      "seat" ->
        if is_integer(params["seat"]), do: {:seat, code, pid, params["seat"]}

      "start" ->
        {:start, code, pid}

      "leave" ->
        {:leave, code, pid}

      "rematch" ->
        {:rematch, code, pid}

      "play_card" ->
        if is_binary(params["card"]), do: {:act, code, pid, {:play_card, params["card"]}}

      "truco" ->
        {:act, code, pid, :truco}

      "accept" ->
        {:act, code, pid, :accept}

      "reject" ->
        {:act, code, pid, :reject}

      "accept_mao_de_11" ->
        {:act, code, pid, :accept_mao_de_11}

      "reject_mao_de_11" ->
        {:act, code, pid, :reject_mao_de_11}

      _ ->
        nil
    end
  end

  @impl true
  def handle_info(:push_state, socket) do
    push_state(socket, [])
  end

  def handle_info({:room_updated, _code, events}, socket) do
    push_state(socket, events)
  end

  defp push_state(socket, events) do
    case Replica.view(@inst, socket.assigns.code, socket.assigns.player.id) do
      nil ->
        push(socket, "closed", %{})
        {:stop, :normal, socket}

      view ->
        push(socket, "state", %{view: view, events: events})
        {:noreply, socket}
    end
  end
end
