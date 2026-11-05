defmodule TrucoOn.Truco.Evaluator do
  @moduledoc """
  Avaliação pura de vazas e rodadas.

  ## Vaza (`evaluate_trick/1`)

  Recebe uma lista de jogadas na ordem em que foram feitas. Cada jogada é um map
  com `:player_id`, `:team` (`"a"` | `"b"`) e `:card`.

  Retorna `{:winner, player_id, team}` ou `:draw`. Em caso de cartas com força
  máxima empatadas, vence se forem do mesmo time (o jogador escolhido é o
  primeiro que jogou aquela força); senão é empate.

  Como as 4 manilhas do truco mineiro são únicas (7_ouros, A_espadas, 7_copas,
  4_paus, cada uma com força distinta), empates só acontecem entre cartas comuns
  do mesmo valor (ex: `K_ouros` vs `K_copas`).

  ## Rodada (`evaluate_round/1`)

  Recebe uma lista de resultados de vazas (`:team_a | :team_b | :draw`),
  ordenada (1ª vaza primeiro). Suporta listas de 0 a 3 vazas.

  Retorna:
  - `:team_a` ou `:team_b` — rodada decidida
  - `:draw` — três vazas empataram (mão nula)
  - `:undecided` — faltam vazas pra decidir

  Regras:
  - Time que vencer 2 vazas vence a rodada
  - 1 vitória + empates = vence
  - 1 vitória pra cada lado + empate na 3ª = vence quem ganhou a 1ª
  - Três empates = mão nula (nenhum tento)
  """

  alias TrucoOn.Truco.Deck

  @doc """
  Avalia uma vaza dada a lista de jogadas.
  """
  def evaluate_trick(plays) when is_list(plays) and plays != [] do
    plays_with_strength =
      Enum.map(plays, fn play ->
        Map.put(play, :strength, Deck.card_strength(play.card))
      end)

    max_strength = plays_with_strength |> Enum.map(& &1.strength) |> Enum.max()
    top = Enum.filter(plays_with_strength, &(&1.strength == max_strength))

    case top |> Enum.map(& &1.team) |> Enum.uniq() do
      [single_team] ->
        winner = hd(top)
        {:winner, winner.player_id, single_team}

      _ ->
        :draw
    end
  end

  @doc """
  Avalia o resultado parcial ou final de uma rodada.
  """
  def evaluate_round(trick_results)
      when is_list(trick_results) and length(trick_results) <= 3 do
    if length(trick_results) < 2 do
      :undecided
    else
      resolve(trick_results)
    end
  end

  defp resolve(trick_results) do
    freq = Enum.frequencies(trick_results)
    a = Map.get(freq, :team_a, 0)
    b = Map.get(freq, :team_b, 0)
    d = Map.get(freq, :draw, 0)
    n = length(trick_results)

    cond do
      a >= 2 -> :team_a
      b >= 2 -> :team_b
      a == 1 and b == 0 and d >= 1 -> :team_a
      a == 0 and b == 1 and d >= 1 -> :team_b
      a == 1 and b == 1 and n == 3 -> first_decided(trick_results)
      a == 1 and b == 1 -> :undecided
      d == n and n == 3 -> :draw
      true -> :undecided
    end
  end

  defp first_decided(trick_results) do
    case Enum.find(trick_results, &(&1 in [:team_a, :team_b])) do
      :team_a -> :team_a
      :team_b -> :team_b
    end
  end
end
