defmodule TrucoOn.Truco.Rules do
  @moduledoc """
  Regras de aposta e categorização da rodada — funções puras.

  ## Estado de aposta

  Representado por um map:

      %{
        value: 1 | 3 | 6 | 9 | 12,
        pending_team: nil | "a" | "b",   # time que precisa decidir aceitar/aumentar/fugir
        last_caller_team: nil | "a" | "b" # último time que pediu/aumentou
      }

  ## Mão de 11 e Mão de Ferro

  Categorias especiais determinadas pelo placar do jogo (ver `round_category/2`).
  Não passam pelo fluxo normal de aposta — são decididas em uma única ação
  (aceitar/fugir) e valem 3 tentos fixos.
  """

  @doc "Estado inicial de aposta para uma nova rodada normal."
  def initial_bet_state, do: %{value: 1, pending_team: nil, last_caller_team: nil}

  @doc "Sequência de valores possíveis em uma rodada normal."
  def bet_levels, do: [1, 3, 6, 9, 12]

  @doc """
  Próximo valor de aposta após `current` (truco → seis → nove → doze).
  Retorna `:error` se não é possível subir mais.
  """
  def next_bet(1), do: {:ok, 3}
  def next_bet(3), do: {:ok, 6}
  def next_bet(6), do: {:ok, 9}
  def next_bet(9), do: {:ok, 12}
  def next_bet(12), do: :error

  @doc """
  Tentos concedidos ao adversário se o time pendente fugir do pedido `value`.

  - Fuga de truco (3) → adversário ganha 1 (valor pré-pedido)
  - Fuga de seis (6) → 3
  - Fuga de nove (9) → 6
  - Fuga de doze (12) → 9
  """
  def reject_value(3), do: 1
  def reject_value(6), do: 3
  def reject_value(9), do: 6
  def reject_value(12), do: 9

  @doc """
  Time adversário do informado.
  """
  def opposing_team("a"), do: "b"
  def opposing_team("b"), do: "a"

  @doc """
  Pode pedir truco (ou subir aposta)?

  - `bet` — estado atual de aposta (ver moduledoc)
  - `team` — `"a"` ou `"b"`, time do solicitante

  Erros possíveis: `:max_bet_reached`, `:bet_already_pending`, `:same_team_cannot_raise`.
  """
  def can_call_truco?(%{value: 12}, _team), do: {:error, :max_bet_reached}

  def can_call_truco?(%{pending_team: pending}, _team) when not is_nil(pending),
    do: {:error, :bet_already_pending}

  def can_call_truco?(%{last_caller_team: last_caller}, team)
      when last_caller == team,
      do: {:error, :same_team_cannot_raise}

  def can_call_truco?(_bet, team) when team in ["a", "b"], do: :ok

  @doc """
  Aplica um pedido de truco/aumento e devolve o novo estado de aposta.

  Pré-condição: `can_call_truco?/2` retornou `:ok`.
  """
  def call_truco(%{value: value} = bet, team) when team in ["a", "b"] do
    {:ok, new_value} = next_bet(value)
    pending = opposing_team(team)
    %{bet | value: new_value, pending_team: pending, last_caller_team: team}
  end

  @doc """
  Aceita o pedido pendente. Aposta fica fixa no novo valor; ninguém mais pendente.

  Erros: `:no_bet_pending`, `:not_pending_team`.
  """
  def accept_truco(%{pending_team: nil}, _team), do: {:error, :no_bet_pending}

  def accept_truco(%{pending_team: pending} = bet, team) when pending == team do
    {:ok, %{bet | pending_team: nil}}
  end

  def accept_truco(_bet, _team), do: {:error, :not_pending_team}

  @doc """
  Foge do pedido pendente.

  Retorna `{:ok, %{tentos: n, awarded_to: team}}` indicando quantos tentos vão
  para o time adversário (que pediu).

  Erros: `:no_bet_pending`, `:not_pending_team`.
  """
  def reject_truco(%{pending_team: nil}, _team), do: {:error, :no_bet_pending}

  def reject_truco(%{pending_team: pending, value: value}, team) when pending == team do
    awarded_to = opposing_team(team)
    {:ok, %{tentos: reject_value(value), awarded_to: awarded_to}}
  end

  def reject_truco(_bet, _team), do: {:error, :not_pending_team}

  @doc """
  Categoria de uma rodada baseada no placar atual da partida.

  - `:mao_de_ferro` — ambos os times com 11 tentos (rodada às cegas, vale 3)
  - `{:mao_de_11, team}` — apenas `team` está com 11 tentos
  - `:normal` — caso geral
  """
  def round_category(score_a, score_b) when is_integer(score_a) and is_integer(score_b) do
    cond do
      score_a == 11 and score_b == 11 -> :mao_de_ferro
      score_a == 11 -> {:mao_de_11, "a"}
      score_b == 11 -> {:mao_de_11, "b"}
      true -> :normal
    end
  end

  @doc """
  Detecta vitória da partida no placar.

  Retorna `{:winner, "a" | "b"}` se algum time alcançou 12 tentos, ou `:none`.
  """
  def game_winner(score_a, _score_b) when score_a >= 12, do: {:winner, "a"}
  def game_winner(_score_a, score_b) when score_b >= 12, do: {:winner, "b"}
  def game_winner(_, _), do: :none
end
