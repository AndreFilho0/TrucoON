defmodule TrucoOn.Truco.RulesTest do
  use ExUnit.Case, async: true

  alias TrucoOn.Truco.Rules

  describe "next_bet/1 e reject_value/1" do
    test "sequência truco → seis → nove → doze" do
      assert Rules.next_bet(1) == {:ok, 3}
      assert Rules.next_bet(3) == {:ok, 6}
      assert Rules.next_bet(6) == {:ok, 9}
      assert Rules.next_bet(9) == {:ok, 12}
      assert Rules.next_bet(12) == :error
    end

    test "fugir concede o valor pré-pedido" do
      assert Rules.reject_value(3) == 1
      assert Rules.reject_value(6) == 3
      assert Rules.reject_value(9) == 6
      assert Rules.reject_value(12) == 9
    end
  end

  describe "opposing_team/1" do
    test "inverte os times" do
      assert Rules.opposing_team("a") == "b"
      assert Rules.opposing_team("b") == "a"
    end
  end

  describe "can_call_truco?/2" do
    test "permitido em estado inicial" do
      assert Rules.can_call_truco?(Rules.initial_bet_state(), "a") == :ok
      assert Rules.can_call_truco?(Rules.initial_bet_state(), "b") == :ok
    end

    test "rejeita se já está no doze" do
      bet = %{value: 12, pending_team: nil, last_caller_team: "a"}
      assert Rules.can_call_truco?(bet, "b") == {:error, :max_bet_reached}
    end

    test "rejeita se há aposta pendente" do
      bet = %{value: 3, pending_team: "b", last_caller_team: "a"}
      assert Rules.can_call_truco?(bet, "a") == {:error, :bet_already_pending}
    end

    test "rejeita se mesmo time pediu o último aumento" do
      bet = %{value: 3, pending_team: nil, last_caller_team: "a"}
      assert Rules.can_call_truco?(bet, "a") == {:error, :same_team_cannot_raise}
      assert Rules.can_call_truco?(bet, "b") == :ok
    end
  end

  describe "call_truco/2" do
    test "1 → 3, marca o adversário como pendente" do
      assert Rules.call_truco(Rules.initial_bet_state(), "a") == %{
               value: 3,
               pending_team: "b",
               last_caller_team: "a"
             }
    end

    test "3 → 6 quando o adversário aumenta após aceitar (cenário simulado)" do
      bet = %{value: 3, pending_team: nil, last_caller_team: "a"}
      assert Rules.call_truco(bet, "b") == %{value: 6, pending_team: "a", last_caller_team: "b"}
    end
  end

  describe "accept_truco/2" do
    test "limpa o pendente e mantém o valor" do
      bet = %{value: 3, pending_team: "b", last_caller_team: "a"}

      assert Rules.accept_truco(bet, "b") ==
               {:ok, %{value: 3, pending_team: nil, last_caller_team: "a"}}
    end

    test "rejeita se não há pendente" do
      bet = Rules.initial_bet_state()
      assert Rules.accept_truco(bet, "a") == {:error, :no_bet_pending}
    end

    test "rejeita se o time não é o pendente" do
      bet = %{value: 3, pending_team: "b", last_caller_team: "a"}
      assert Rules.accept_truco(bet, "a") == {:error, :not_pending_team}
    end
  end

  describe "reject_truco/2" do
    test "concede tentos ao adversário com base no valor pedido" do
      bet = %{value: 6, pending_team: "a", last_caller_team: "b"}
      assert Rules.reject_truco(bet, "a") == {:ok, %{tentos: 3, awarded_to: "b"}}
    end

    test "fugir do truco (3) concede 1" do
      bet = %{value: 3, pending_team: "b", last_caller_team: "a"}
      assert Rules.reject_truco(bet, "b") == {:ok, %{tentos: 1, awarded_to: "a"}}
    end

    test "rejeita se não há pendente" do
      assert Rules.reject_truco(Rules.initial_bet_state(), "a") == {:error, :no_bet_pending}
    end

    test "rejeita se o time não é o pendente" do
      bet = %{value: 3, pending_team: "b", last_caller_team: "a"}
      assert Rules.reject_truco(bet, "a") == {:error, :not_pending_team}
    end
  end

  describe "round_category/2" do
    test "normal quando ambos abaixo de 11" do
      assert Rules.round_category(0, 0) == :normal
      assert Rules.round_category(10, 9) == :normal
    end

    test "mão de 11 quando apenas um está com 11" do
      assert Rules.round_category(11, 5) == {:mao_de_11, "a"}
      assert Rules.round_category(7, 11) == {:mao_de_11, "b"}
    end

    test "mão de ferro quando ambos estão com 11" do
      assert Rules.round_category(11, 11) == :mao_de_ferro
    end
  end

  describe "game_winner/2" do
    test "ninguém venceu" do
      assert Rules.game_winner(0, 0) == :none
      assert Rules.game_winner(11, 11) == :none
    end

    test "time A com 12 ou mais" do
      assert Rules.game_winner(12, 5) == {:winner, "a"}
      assert Rules.game_winner(15, 9) == {:winner, "a"}
    end

    test "time B com 12 ou mais" do
      assert Rules.game_winner(7, 12) == {:winner, "b"}
    end
  end
end
