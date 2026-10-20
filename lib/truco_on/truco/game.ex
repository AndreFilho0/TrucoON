defmodule TrucoOn.Truco.Game do
  @moduledoc """
  Partida de truco mineiro como **máquina de estados pura e determinística**.

  Portado do `Melivra.Truco.GameServer`, com uma diferença central: aqui não
  há processo, timer, PubSub nem relógio. Tudo que muda o estado entra por
  `apply/3`, e o resultado depende só de `(estado, jogador, ação)`.

  Isso é o que permite **replicação por máquina de estados**: se todas as
  réplicas aplicarem os mesmos comandos na mesma ordem, terminam no mesmo
  estado. Se a ordem mudar, o estado pode divergir — é exatamente o problema
  que os protocolos de ordenação (Partes 3 e 4) resolvem.

  `apply/3` devolve `{:ok, novo_estado, eventos}` ou `{:error, motivo}`.
  Os eventos são mapas com `:type` (ex.: `"card_played"`) para a interface
  animar o que aconteceu.
  """

  alias TrucoOn.Truco.{Deck, Evaluator, Rules}

  @type player :: %{id: String.t(), name: String.t(), team: String.t(), seat: integer}
  @type action ::
          {:play_card, String.t()}
          | :truco
          | :accept
          | :reject
          | :accept_mao_de_11
          | :reject_mao_de_11
          | :forfeit

  ## ---------------------------------------------------------------------------
  ## Criação
  ## ---------------------------------------------------------------------------

  @doc """
  Cria uma partida com `players` (já com `:team` e `:seat`) e dá as cartas da
  primeira mão. `seed` define todos os embaralhamentos da partida.
  """
  def new(players, mode, seed) when mode in ["1v1", "2v2"] and is_integer(seed) do
    expected = if mode == "1v1", do: 2, else: 4

    if length(players) != expected do
      raise ArgumentError, "modo #{mode} requer #{expected} jogadores"
    end

    players =
      players
      |> Enum.sort_by(& &1.seat)
      |> Enum.map(&Map.take(&1, [:id, :name, :team, :seat]))

    state = %{
      mode: mode,
      players: players,
      players_by_id: Map.new(players, &{&1.id, &1}),
      seat_order: Enum.map(players, & &1.id),
      scores: %{"a" => 0, "b" => 0},
      status: :playing,
      winner_team: nil,
      finish_reason: nil,
      round: nil,
      round_number: 0,
      starting_seat: 0,
      seed: seed,
      last_trick: nil,
      last_round: nil
    }

    ev = emit([], "game_started", %{mode: mode, players: Enum.map(players, &public_player/1)})
    {state, ev} = start_round(state, 1, ev)
    {state, Enum.reverse(ev)}
  end

  ## ---------------------------------------------------------------------------
  ## Aplicação de ações
  ## ---------------------------------------------------------------------------

  @doc "Aplica a ação de `player_id`. Função pura."
  @spec apply(map, String.t(), action) :: {:ok, map, [map]} | {:error, atom}
  def apply(%{status: :finished}, _player_id, _action), do: {:error, :game_finished}

  def apply(state, player_id, action) do
    if Map.has_key?(state.players_by_id, player_id) do
      result =
        case action do
          {:play_card, card} when is_binary(card) -> do_play_card(state, player_id, card, [])
          :truco -> do_call_truco(state, player_id, [])
          :accept -> do_accept_truco(state, player_id, [])
          :reject -> do_reject_truco(state, player_id, [])
          :accept_mao_de_11 -> do_accept_mao_de_11(state, player_id, [])
          :reject_mao_de_11 -> do_reject_mao_de_11(state, player_id, [])
          :forfeit -> do_forfeit(state, player_id, [])
          _ -> {:error, :unknown_action}
        end

      case result do
        {:ok, state, ev} -> {:ok, state, Enum.reverse(ev)}
        {:error, _} = err -> err
      end
    else
      {:error, :not_in_game}
    end
  end

  ## ---------------------------------------------------------------------------
  ## Jogar carta
  ## ---------------------------------------------------------------------------

  defp do_play_card(%{round: nil}, _, _, _), do: {:error, :no_active_round}

  defp do_play_card(state, player_id, card, ev) do
    round = state.round

    with :ok <- check_no_pending_decisions(round),
         :ok <- check_round_open_for_play(round),
         :ok <- check_turn(round, player_id),
         :ok <- check_card_in_hand(round, player_id, card) do
      player = Map.fetch!(state.players_by_id, player_id)
      play = %{player_id: player_id, team: player.team, card: card}
      new_plays = round.plays_in_trick ++ [play]
      new_hands = Map.update!(round.hands, player_id, &List.delete(&1, card))
      trick_closing? = length(new_plays) == length(state.players)

      next_turn =
        if trick_closing?, do: nil, else: next_in_seat_order(state.seat_order, player_id)

      ev =
        emit(ev, "card_played", %{
          player_id: player_id,
          card: card,
          trick_number: length(round.trick_results) + 1
        })

      round = %{round | plays_in_trick: new_plays, hands: new_hands}

      if trick_closing? do
        finish_trick(state, round, ev)
      else
        {:ok, %{state | round: %{round | current_turn: next_turn}}, ev}
      end
    end
  end

  defp check_round_open_for_play(%{status: s}) when s in [:playing, :mao_de_ferro], do: :ok
  defp check_round_open_for_play(%{status: :mao_de_11}), do: {:error, :mao_de_11_pending}
  defp check_round_open_for_play(_), do: {:error, :round_not_open_for_play}

  defp check_no_pending_decisions(%{bet: %{pending_team: nil}}), do: :ok
  defp check_no_pending_decisions(_), do: {:error, :truco_pending}

  defp check_turn(%{current_turn: pid}, pid), do: :ok
  defp check_turn(_, _), do: {:error, :not_your_turn}

  defp check_card_in_hand(%{hands: hands}, player_id, card) do
    if card in Map.get(hands, player_id, []), do: :ok, else: {:error, :card_not_in_hand}
  end

  ## ---------------------------------------------------------------------------
  ## Fim de vaza e de mão
  ## ---------------------------------------------------------------------------

  defp finish_trick(state, round, ev) do
    trick_number = length(round.trick_results) + 1

    {trick_atom, winner_team, winner_pid} =
      case Evaluator.evaluate_trick(round.plays_in_trick) do
        {:winner, pid, "a"} -> {:team_a, "a", pid}
        {:winner, pid, "b"} -> {:team_b, "b", pid}
        :draw -> {:draw, nil, nil}
      end

    plays = Enum.map(round.plays_in_trick, &Map.take(&1, [:player_id, :card]))

    last_trick = %{
      number: trick_number,
      winner_team: winner_team,
      winner_player_id: winner_pid,
      plays: plays
    }

    ev = emit(ev, "trick_finished", last_trick)
    state = %{state | last_trick: last_trick}
    trick_results = round.trick_results ++ [trick_atom]

    case Evaluator.evaluate_round(trick_results) do
      :undecided ->
        next_starter = winner_pid || hd(round.plays_in_trick).player_id

        round = %{
          round
          | plays_in_trick: [],
            trick_results: trick_results,
            current_turn: next_starter
        }

        {:ok, %{state | round: round}, ev}

      round_result ->
        round = %{round | plays_in_trick: [], trick_results: trick_results}
        finish_round(state, round, round_result, ev)
    end
  end

  defp finish_round(state, round, round_result, ev) do
    {team, tentos} =
      case round_result do
        :team_a -> {"a", round.bet.value}
        :team_b -> {"b", round.bet.value}
        :draw -> {nil, 0}
      end

    award(state, round, team, tentos, "played", ev)
  end

  defp award(state, round, team, tentos, reason, ev) do
    scores =
      if team, do: Map.update!(state.scores, team, &(&1 + tentos)), else: state.scores

    last_round = %{
      number: round.number,
      winner_team: team,
      tentos: tentos,
      bet_value: round.bet.value,
      reason: reason
    }

    ev = emit(ev, "round_finished", Map.merge(last_round, %{scores: scores}))
    state = %{state | scores: scores, round: nil, last_round: last_round}

    case Rules.game_winner(scores["a"], scores["b"]) do
      {:winner, w} ->
        ev = emit(ev, "game_over", %{winner_team: w, scores: scores, reason: "completed"})
        {:ok, %{state | status: :finished, winner_team: w, finish_reason: "completed"}, ev}

      :none ->
        state = %{state | starting_seat: state.starting_seat + 1}
        {state, ev} = start_round(state, round.number + 1, ev)
        {:ok, state, ev}
    end
  end

  ## ---------------------------------------------------------------------------
  ## Início de mão (distribuição)
  ## ---------------------------------------------------------------------------

  defp start_round(state, n, ev) do
    n_players = length(state.players)

    hand_lists =
      Deck.new_deck()
      |> Deck.shuffle(state.seed * 1000 + n)
      |> Deck.deal(n_players)

    hands = state.seat_order |> Enum.zip(hand_lists) |> Map.new()
    starting_pid = Enum.at(state.seat_order, rem(state.starting_seat, n_players))
    category = Rules.round_category(state.scores["a"], state.scores["b"])
    {round_status, bet_value} = round_status_for(category)

    round = %{
      number: n,
      hands: hands,
      plays_in_trick: [],
      trick_results: [],
      bet: %{value: bet_value, pending_team: nil, last_caller_team: nil},
      category: category,
      status: round_status,
      current_turn: starting_pid
    }

    ev =
      emit(ev, "round_started", %{
        number: n,
        category: serialize_category(category),
        current_bet: bet_value,
        current_turn: starting_pid
      })

    {%{state | round: round, round_number: n}, ev}
  end

  defp round_status_for(:normal), do: {:playing, 1}
  defp round_status_for({:mao_de_11, _team}), do: {:mao_de_11, 3}
  defp round_status_for(:mao_de_ferro), do: {:mao_de_ferro, 3}

  ## ---------------------------------------------------------------------------
  ## Truco (pedir, aumentar, aceitar, fugir)
  ## ---------------------------------------------------------------------------

  defp do_call_truco(%{round: nil}, _, _), do: {:error, :no_active_round}

  defp do_call_truco(%{round: %{category: c}}, _, _) when c != :normal,
    do: {:error, :truco_disabled_in_special_round}

  defp do_call_truco(state, player_id, ev) do
    round = state.round
    player = Map.fetch!(state.players_by_id, player_id)

    cond do
      round.status not in [:playing, :truco_pending] ->
        {:error, :round_not_open_for_play}

      is_nil(round.bet.pending_team) ->
        with :ok <- Rules.can_call_truco?(round.bet, player.team) do
          bet = Rules.call_truco(round.bet, player.team)

          ev =
            emit(ev, "truco_called", %{
              player_id: player_id,
              team: player.team,
              current_bet: bet.value
            })

          {:ok, %{state | round: %{round | bet: bet, status: :truco_pending}}, ev}
        end

      round.bet.pending_team == player.team ->
        case Rules.next_bet(round.bet.value) do
          {:ok, value} ->
            bet = %{
              value: value,
              pending_team: Rules.opposing_team(player.team),
              last_caller_team: player.team
            }

            ev =
              emit(ev, "truco_raised", %{
                player_id: player_id,
                team: player.team,
                current_bet: value
              })

            {:ok, %{state | round: %{round | bet: bet, status: :truco_pending}}, ev}

          :error ->
            {:error, :max_bet_reached}
        end

      true ->
        {:error, :not_pending_team}
    end
  end

  defp do_accept_truco(%{round: nil}, _, _), do: {:error, :no_active_round}

  defp do_accept_truco(state, player_id, ev) do
    round = state.round
    player = Map.fetch!(state.players_by_id, player_id)

    with {:ok, bet} <- Rules.accept_truco(round.bet, player.team) do
      ev =
        emit(ev, "truco_accepted", %{
          player_id: player_id,
          team: player.team,
          current_bet: bet.value
        })

      {:ok, %{state | round: %{round | bet: bet, status: :playing}}, ev}
    end
  end

  defp do_reject_truco(%{round: nil}, _, _), do: {:error, :no_active_round}

  defp do_reject_truco(state, player_id, ev) do
    round = state.round
    player = Map.fetch!(state.players_by_id, player_id)

    with {:ok, %{tentos: tentos, awarded_to: team}} <- Rules.reject_truco(round.bet, player.team) do
      ev =
        emit(ev, "truco_rejected", %{
          player_id: player_id,
          team: player.team,
          tentos: tentos,
          awarded_to: team
        })

      award(state, round, team, tentos, "fled", ev)
    end
  end

  ## ---------------------------------------------------------------------------
  ## Mão de 11
  ## ---------------------------------------------------------------------------

  defp do_accept_mao_de_11(
         %{round: %{status: :mao_de_11, category: {:mao_de_11, team}} = round} = state,
         player_id,
         ev
       ) do
    if Map.fetch!(state.players_by_id, player_id).team != team do
      {:error, :not_mao_de_11_team}
    else
      ev = emit(ev, "mao_de_11_accepted", %{player_id: player_id, team: team})
      {:ok, %{state | round: %{round | status: :playing}}, ev}
    end
  end

  defp do_accept_mao_de_11(_, _, _), do: {:error, :not_mao_de_11}

  defp do_reject_mao_de_11(
         %{round: %{status: :mao_de_11, category: {:mao_de_11, team}} = round} = state,
         player_id,
         ev
       ) do
    if Map.fetch!(state.players_by_id, player_id).team != team do
      {:error, :not_mao_de_11_team}
    else
      opponent = Rules.opposing_team(team)

      ev =
        emit(ev, "mao_de_11_rejected", %{player_id: player_id, team: team, awarded_to: opponent})

      award(state, round, opponent, 1, "fled", ev)
    end
  end

  defp do_reject_mao_de_11(_, _, _), do: {:error, :not_mao_de_11}

  ## ---------------------------------------------------------------------------
  ## Desistência (o jogador sai no meio da partida)
  ## ---------------------------------------------------------------------------

  defp do_forfeit(state, player_id, ev) do
    player = Map.fetch!(state.players_by_id, player_id)
    winner = Rules.opposing_team(player.team)
    scores = Map.put(state.scores, winner, 12)

    ev = emit(ev, "game_over", %{winner_team: winner, scores: scores, reason: "forfeit"})

    state = %{
      state
      | status: :finished,
        scores: scores,
        round: nil,
        winner_team: winner,
        finish_reason: "forfeit"
    }

    {:ok, state, ev}
  end

  ## ---------------------------------------------------------------------------
  ## Visão por jogador (nunca expõe a mão dos outros)
  ## ---------------------------------------------------------------------------

  @doc """
  Estado sanitizado para `player_id`: inclui a própria mão e, só na mão de 11
  do 2v2, a mão do parceiro (regra do truco mineiro). Nunca a dos adversários.
  """
  def view(state, player_id) do
    base = %{
      mode: state.mode,
      status: state.status,
      scores: state.scores,
      winner_team: state.winner_team,
      finish_reason: state.finish_reason,
      players: Enum.map(state.players, &public_player/1),
      last_trick: state.last_trick,
      last_round: state.last_round,
      round: nil
    }

    case state.round do
      nil ->
        base

      round ->
        me = Map.get(state.players_by_id, player_id)

        Map.put(base, :round, %{
          number: round.number,
          status: round.status,
          category: serialize_category(round.category),
          current_bet: round.bet.value,
          bet_pending_team: round.bet.pending_team,
          last_caller_team: round.bet.last_caller_team,
          current_turn: round.current_turn,
          my_cards: Map.get(round.hands, player_id, []),
          partner_cards: partner_cards(state, round, me),
          cards_left: Map.new(round.hands, fn {pid, cards} -> {pid, length(cards)} end),
          plays_in_trick: Enum.map(round.plays_in_trick, &Map.take(&1, [:player_id, :card])),
          trick_results: Enum.map(round.trick_results, &serialize_trick_result/1)
        })
    end
  end

  defp partner_cards(
         %{mode: "2v2"} = state,
         %{status: :mao_de_11, category: {:mao_de_11, t}} = round,
         %{team: t} = me
       ) do
    partner = Enum.find(state.players, &(&1.team == me.team and &1.id != me.id))
    Map.get(round.hands, partner.id, [])
  end

  defp partner_cards(_, _, _), do: nil

  ## ---------------------------------------------------------------------------
  ## Auxiliares
  ## ---------------------------------------------------------------------------

  defp emit(ev, type, payload), do: [Map.put(payload, :type, type) | ev]

  defp public_player(p), do: Map.take(p, [:id, :name, :team, :seat])

  defp next_in_seat_order(seat_order, player_id) do
    idx = Enum.find_index(seat_order, &(&1 == player_id))
    Enum.at(seat_order, rem(idx + 1, length(seat_order)))
  end

  defp serialize_trick_result(:team_a), do: "a"
  defp serialize_trick_result(:team_b), do: "b"
  defp serialize_trick_result(:draw), do: "draw"

  defp serialize_category(:normal), do: "normal"
  defp serialize_category(:mao_de_ferro), do: "mao_de_ferro"
  defp serialize_category({:mao_de_11, team}), do: "mao_de_11_#{team}"
end
