defmodule TrucoOn.Truco.GameTest do
  use ExUnit.Case, async: true

  alias TrucoOn.Truco.{Deck, Game}

  defp players_1v1 do
    [
      %{id: "ana", name: "Ana", team: "a", seat: 0},
      %{id: "bia", name: "Bia", team: "b", seat: 1}
    ]
  end

  defp players_2v2 do
    for {id, seat} <- Enum.with_index(~w(p0 p1 p2 p3)),
        do: %{id: id, name: id, team: if(rem(seat, 2) == 0, do: "a", else: "b"), seat: seat}
  end

  describe "embaralhamento determinístico" do
    test "mesma semente ⇒ mesmo baralho; sementes diferentes ⇒ baralhos diferentes" do
      assert Deck.shuffle(Deck.new_deck(), 42) == Deck.shuffle(Deck.new_deck(), 42)
      refute Deck.shuffle(Deck.new_deck(), 42) == Deck.shuffle(Deck.new_deck(), 43)
    end

    test "não usa o estado aleatório do processo" do
      a = Deck.shuffle(Deck.new_deck(), 7)
      _ = :rand.uniform()
      assert Deck.shuffle(Deck.new_deck(), 7) == a
    end
  end

  describe "new/3" do
    test "dá 3 cartas para cada um e começa pelo assento 0" do
      {game, events} = Game.new(players_2v2(), "2v2", 1)
      assert Enum.all?(game.round.hands, fn {_p, cards} -> length(cards) == 3 end)
      assert game.round.current_turn == "p0"
      assert Enum.map(events, & &1.type) == ["game_started", "round_started"]
    end

    test "réplicas que criam com a mesma semente são idênticas" do
      assert Game.new(players_1v1(), "1v1", 99) == Game.new(players_1v1(), "1v1", 99)
    end
  end

  describe "apply/3" do
    test "só joga quem está na vez e com carta da mão" do
      {g, _} = Game.new(players_1v1(), "1v1", 5)
      [card | _] = g.round.hands["ana"]
      bia_card = hd(g.round.hands["bia"])

      assert {:error, :not_your_turn} = Game.apply(g, "bia", {:play_card, bia_card})
      assert {:error, :card_not_in_hand} = Game.apply(g, "ana", {:play_card, bia_card})
      assert {:ok, g2, [%{type: "card_played"}]} = Game.apply(g, "ana", {:play_card, card})
      assert g2.round.current_turn == "bia"
    end

    test "truco: pede, fica pendente, adversário foge e quem pediu leva 1" do
      {g, _} = Game.new(players_1v1(), "1v1", 5)
      {:ok, g, _} = Game.apply(g, "ana", :truco)
      assert g.round.bet.value == 3

      assert {:error, :truco_pending} =
               Game.apply(g, "ana", {:play_card, hd(g.round.hands["ana"])})

      {:ok, g, events} = Game.apply(g, "bia", :reject)
      assert g.scores == %{"a" => 1, "b" => 0}
      assert Enum.any?(events, &(&1.type == "round_finished"))
      assert g.round.number == 2
    end

    test "mão completa até alguém fazer 2 vazas" do
      {g, _} = Game.new(players_1v1(), "1v1", 11)
      g = play_until_round_ends(g, 1)
      assert (g.scores["a"] + g.scores["b"]) in [0, 1]
      assert g.round.number == 2
    end

    test "partida termina ao chegar em 12 tentos" do
      {g, _} = Game.new(players_1v1(), "1v1", 3)

      g =
        Enum.reduce_while(1..200, g, fn _, g ->
          if g.status == :finished, do: {:halt, g}, else: {:cont, flee(g)}
        end)

      assert g.status == :finished
      assert g.winner_team in ["a", "b"]
      assert {:error, :game_finished} = Game.apply(g, "ana", :truco)
    end

    test "desistência dá a vitória ao outro time" do
      {g, _} = Game.new(players_2v2(), "2v2", 3)
      {:ok, g, _} = Game.apply(g, "p1", :forfeit)
      assert g.winner_team == "a"
      assert g.finish_reason == "forfeit"
    end
  end

  describe "view/2" do
    test "mostra a própria mão e nunca a dos outros" do
      {g, _} = Game.new(players_2v2(), "2v2", 8)
      v = Game.view(g, "p0")
      assert v.round.my_cards == g.round.hands["p0"]
      refute Map.has_key?(v.round, :hands)
      assert v.round.partner_cards == nil
      assert v.round.cards_left == %{"p0" => 3, "p1" => 3, "p2" => 3, "p3" => 3}
      assert Jason.encode!(v)
    end
  end

  # alguém pede truco e o outro foge ⇒ 1 tento por mão, até alguém fazer 12
  # (na mão de 11 não pode pedir truco: o time com 11 decide; na mão de
  # ferro joga-se a mão inteira)
  defp flee(%{round: %{status: :mao_de_11, category: {:mao_de_11, team}}} = g) do
    p = Enum.find(g.players, &(&1.team == team))
    {:ok, g, _} = Game.apply(g, p.id, :reject_mao_de_11)
    g
  end

  defp flee(%{round: %{category: :mao_de_ferro, number: n}} = g), do: play_until_round_ends(g, n)

  defp flee(g) do
    turn = g.round.current_turn
    other = Enum.find(g.seat_order, &(&1 != turn))
    {:ok, g, _} = Game.apply(g, turn, :truco)
    {:ok, g, _} = Game.apply(g, other, :reject)
    g
  end

  defp play_until_round_ends(g, n) do
    if g.status == :finished or g.round.number != n do
      g
    else
      turn = g.round.current_turn
      {:ok, g, _} = Game.apply(g, turn, {:play_card, hd(g.round.hands[turn])})
      play_until_round_ends(g, n)
    end
  end
end
