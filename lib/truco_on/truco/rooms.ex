defmodule TrucoOn.Truco.Rooms do
  @moduledoc """
  A **base de dados replicada** do TrucoON: o conjunto de mesas (salas),
  cada uma com lobby e partida.

  Cada peer guarda uma cópia deste mapa (`code => sala`). As alterações
  chegam como **comandos** entregues pelo multicast, e `apply/2` é puro e
  determinístico: mesmo estado + mesmo comando ⇒ mesmo resultado em qualquer
  réplica. Erros também são determinísticos (todas as réplicas rejeitam o
  mesmo comando pelo mesmo motivo).

  ## Comandos

      {:create, code, player, mode, seed}   cria a mesa; player = %{id, name}
      {:join,   code, player}               entra no lobby
      {:seat,   code, player_id, seat}      senta numa cadeira (0..1 ou 0..3)
      {:leave,  code, player_id}            sai do lobby (ou desiste da partida)
      {:start,  code, player_id}            anfitrião começa a partida
      {:act,    code, player_id, action}    ação de jogo (ver `TrucoOn.Truco.Game`)
      {:rematch, code, player_id}           anfitrião começa nova partida

  ## Por que a ordem importa (exemplo do lobby)

  Dois jogadores pedem a cadeira 0 ao mesmo tempo. A réplica que aplicar o
  pedido de A primeiro dá a cadeira para A e rejeita B; a que aplicar B
  primeiro faz o contrário. Sem ordem total, as réplicas **divergem**.
  """

  alias TrucoOn.Truco.Game

  @max_events 40

  @type rooms :: %{String.t() => map}
  @type result :: {:ok, term} | {:error, atom}

  @doc """
  Aplica `cmd` em `rooms`. Devolve `{rooms, code, result, events}`.
  Em caso de erro, `rooms` volta inalterado.
  """
  @spec apply(rooms, tuple) :: {rooms, String.t() | nil, result, [map]}
  def apply(rooms, cmd) do
    code = command_code(cmd)

    case run(Map.get(rooms, code), cmd) do
      {:ok, :deleted, value, _events} ->
        {Map.delete(rooms, code), code, {:ok, value}, []}

      {:ok, room, value, events} ->
        {room, events} = stamp_events(room, events)
        {Map.put(rooms, code, room), code, {:ok, value}, events}

      {:error, _reason} = err ->
        {rooms, code, err, []}
    end
  end

  def command_code(cmd) when is_tuple(cmd) and tuple_size(cmd) >= 2, do: elem(cmd, 1)
  def command_code(_), do: nil

  ## ---------------------------------------------------------------------------
  ## Comandos
  ## ---------------------------------------------------------------------------

  defp run(nil, {:create, code, player, mode, seed}) when mode in ["1v1", "2v2"] do
    room = %{
      code: code,
      mode: mode,
      host_id: player.id,
      seed: seed,
      status: :lobby,
      members: [player],
      seats: %{},
      game: nil,
      games_played: 0,
      version: 0,
      events: []
    }

    {:ok, room, code, [%{type: "room_created", player_id: player.id, mode: mode}]}
  end

  defp run(_room, {:create, _, _, _, _}), do: {:error, :code_taken}
  defp run(nil, _cmd), do: {:error, :room_not_found}

  defp run(room, {:join, _code, player}) do
    cond do
      member?(room, player.id) ->
        members = Enum.map(room.members, &if(&1.id == player.id, do: player, else: &1))
        {:ok, %{room | members: members}, :already_member, []}

      room.status != :lobby ->
        {:error, :game_in_progress}

      length(room.members) >= capacity(room) ->
        {:error, :room_full}

      true ->
        room = %{room | members: room.members ++ [player]}
        {:ok, room, :joined, [%{type: "player_joined", player_id: player.id, name: player.name}]}
    end
  end

  defp run(room, {:seat, _code, player_id, seat}) do
    cond do
      room.status != :lobby ->
        {:error, :game_in_progress}

      not member?(room, player_id) ->
        {:error, :not_in_room}

      not is_integer(seat) or seat < 0 or seat >= capacity(room) ->
        {:error, :invalid_seat}

      Map.get(room.seats, seat) == player_id ->
        {:ok, room, seat, []}

      Map.has_key?(room.seats, seat) ->
        {:error, :seat_taken}

      true ->
        seats =
          room.seats
          |> Enum.reject(fn {_s, pid} -> pid == player_id end)
          |> Map.new()
          |> Map.put(seat, player_id)

        event = %{type: "seat_taken", player_id: player_id, seat: seat, team: team_of(seat)}
        {:ok, %{room | seats: seats}, seat, [event]}
    end
  end

  defp run(room, {:leave, _code, player_id}) do
    cond do
      not member?(room, player_id) ->
        {:error, :not_in_room}

      room.status == :playing ->
        # sair no meio da partida = desistir (o outro time vence)
        {:ok, game, events} = Game.apply(room.game, player_id, :forfeit)
        {:ok, %{room | game: game, status: :finished}, :forfeited, events}

      true ->
        members = Enum.reject(room.members, &(&1.id == player_id))
        seats = room.seats |> Enum.reject(fn {_s, pid} -> pid == player_id end) |> Map.new()

        case members do
          [] ->
            {:ok, :deleted, :room_closed, []}

          [next | _] ->
            host = if room.host_id == player_id, do: next.id, else: room.host_id
            room = %{room | members: members, seats: seats, host_id: host}
            {:ok, room, :left, [%{type: "player_left", player_id: player_id, host_id: host}]}
        end
    end
  end

  defp run(room, {:start, _code, player_id}) do
    cond do
      room.host_id != player_id -> {:error, :not_host}
      room.status == :playing -> {:error, :game_in_progress}
      map_size(room.seats) < capacity(room) -> {:error, :seats_not_filled}
      true -> start_game(room)
    end
  end

  defp run(room, {:rematch, _code, player_id}) do
    cond do
      room.host_id != player_id -> {:error, :not_host}
      room.status != :finished -> {:error, :game_not_finished}
      true -> start_game(room)
    end
  end

  defp run(room, {:act, _code, player_id, action}) do
    cond do
      room.status != :playing ->
        {:error, :game_not_running}

      true ->
        with {:ok, game, events} <- Game.apply(room.game, player_id, action) do
          status = if game.status == :finished, do: :finished, else: :playing
          {:ok, %{room | game: game, status: status}, :ok, events}
        end
    end
  end

  defp run(_room, _cmd), do: {:error, :unknown_command}

  defp start_game(room) do
    players =
      Enum.map(room.seats, fn {seat, pid} ->
        member = Enum.find(room.members, &(&1.id == pid))
        %{id: pid, name: member.name, team: team_of(seat), seat: seat}
      end)

    # Semente da partida: vem do comando :create (sorteada pelo peer de
    # origem) + número de partidas, então é igual em todas as réplicas.
    {game, events} = Game.new(players, room.mode, room.seed + room.games_played)

    room = %{room | game: game, status: :playing, games_played: room.games_played + 1}
    {:ok, room, :started, events}
  end

  ## ---------------------------------------------------------------------------
  ## Visão de uma sala para um jogador
  ## ---------------------------------------------------------------------------

  @doc "Visão pública da sala (sem cartas), usada na prévia do convite."
  def preview(room) do
    %{
      code: room.code,
      mode: room.mode,
      status: room.status,
      host_id: room.host_id,
      capacity: capacity(room),
      members: Enum.map(room.members, &Map.take(&1, [:id, :name])),
      seats: seats_view(room),
      version: room.version
    }
  end

  @doc "Visão completa para `player_id` (inclui a mão dele, nunca a dos outros)."
  def view(room, player_id) do
    me =
      case Enum.find(room.seats, fn {_s, pid} -> pid == player_id end) do
        {seat, _} -> %{id: player_id, seat: seat, team: team_of(seat)}
        nil -> %{id: player_id, seat: nil, team: nil}
      end

    room
    |> preview()
    |> Map.merge(%{
      me: me,
      is_host: room.host_id == player_id,
      game: room.game && Game.view(room.game, player_id),
      events: Enum.reverse(room.events)
    })
  end

  defp seats_view(room) do
    for seat <- 0..(capacity(room) - 1) do
      pid = Map.get(room.seats, seat)
      member = pid && Enum.find(room.members, &(&1.id == pid))

      %{
        seat: seat,
        team: team_of(seat),
        player: member && Map.take(member, [:id, :name])
      }
    end
  end

  ## ---------------------------------------------------------------------------
  ## Auxiliares
  ## ---------------------------------------------------------------------------

  @doc "Cadeiras pares = time A, ímpares = time B (no 2v2 os parceiros ficam de frente)."
  def team_of(seat) when rem(seat, 2) == 0, do: "a"
  def team_of(_seat), do: "b"

  def capacity(%{mode: "1v1"}), do: 2
  def capacity(%{mode: "2v2"}), do: 4

  defp member?(room, player_id), do: Enum.any?(room.members, &(&1.id == player_id))

  # Numera os eventos com a versão da sala (um contador por sala que avança a
  # cada comando aplicado com sucesso) e guarda só os últimos @max_events.
  defp stamp_events(room, events) do
    version = room.version + 1
    events = Enum.map(events, &Map.put(&1, :version, version))
    kept = Enum.take(Enum.reverse(events) ++ room.events, @max_events)
    {%{room | version: version, events: kept}, events}
  end
end
