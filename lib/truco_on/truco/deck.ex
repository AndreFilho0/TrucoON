defmodule TrucoOn.Truco.Deck do
  @moduledoc """
  Operações puras sobre o baralho de truco mineiro (27 cartas, manilhas fixas).

  Cartas são representadas como strings `"<valor>_<naipe>"` (ex: `"3_paus"`).

  ## Composição (27 cartas)

  - Comuns (23): `Q J K A 2 3` × `ouros espadas copas paus`, **exceto** `A_espadas`
    (que é manilha fixa — espadilha)
  - Manilhas fixas (4), do mais fraco ao mais forte:
    `7_ouros` < `A_espadas` (espadilha) < `7_copas` < `4_paus` (zap)

  Não há vira: as manilhas são sempre as mesmas.

  ## Força absoluta

  Cartas comuns (1..6): `Q < J < K < A < 2 < 3`
  Manilhas (7..10): `7_ouros < A_espadas < 7_copas < 4_paus`
  """

  @common_values ~w(Q J K A 2 3)
  @suits ~w(ouros espadas copas paus)

  # Manilhas fixas, do mais fraco ao mais forte.
  @manilhas ~w(7_ouros A_espadas 7_copas 4_paus)

  @value_strength %{
    "Q" => 1,
    "J" => 2,
    "K" => 3,
    "A" => 4,
    "2" => 5,
    "3" => 6
  }

  # Forças 7..10 alocadas na ordem de @manilhas.
  @manilha_strength @manilhas
                    |> Enum.with_index(7)
                    |> Map.new()

  @doc "Lista de valores das cartas comuns, do mais fraco ao mais forte."
  def common_values, do: @common_values

  @doc "Lista de naipes do baralho."
  def suits, do: @suits

  @doc "Lista das 4 manilhas fixas, do mais fraco ao mais forte."
  def manilhas, do: @manilhas

  @doc "Baralho completo (27 cartas) em ordem canônica."
  def new_deck do
    common =
      for v <- @common_values,
          s <- @suits,
          not (v == "A" and s == "espadas"),
          do: card(v, s)

    common ++ @manilhas
  end

  @doc """
  Embaralha o baralho de forma **determinística** a partir de `seed`.

  No TrucoON cada peer guarda uma réplica da mesa e aplica os mesmos
  comandos. Para todas as réplicas distribuírem as mesmas cartas, o
  embaralhamento não pode depender de estado local (como o `:rand` do
  processo): usamos um estado de PRNG explícito (`:rand.seed_s/2`) derivado
  só da semente, que viaja dentro do comando replicado.
  """
  def shuffle(deck, seed) when is_integer(seed) do
    state = :rand.seed_s(:exsss, {seed, seed + 1, seed + 2})

    {keyed, _state} =
      Enum.map_reduce(deck, state, fn card, st ->
        {r, st} = :rand.uniform_s(st)
        {{r, card}, st}
      end)

    keyed |> Enum.sort() |> Enum.map(&elem(&1, 1))
  end

  @doc """
  Distribui as cartas de uma rodada a partir de um baralho já embaralhado.

  Retorna `hands` — uma lista com `n_players` listas de 3 cartas cada,
  distribuídas em ordem (jogador 0 recebe os índices 0..2, jogador 1 os 3..5, etc.).

  Truco mineiro não tem vira.
  """
  def deal(shuffled_deck, n_players) when is_list(shuffled_deck) and n_players in [2, 4] do
    needed = 3 * n_players

    if length(shuffled_deck) < needed do
      raise ArgumentError, "baralho com #{length(shuffled_deck)} cartas — precisa de #{needed}"
    end

    shuffled_deck |> Enum.take(needed) |> Enum.chunk_every(3)
  end

  @doc """
  Força absoluta de uma carta.

  - Manilhas: 7..10 (`7_ouros`=7, `A_espadas`=8, `7_copas`=9, `4_paus`=10)
  - Comuns: 1..6 (`Q`=1, `J`=2, `K`=3, `A`=4, `2`=5, `3`=6)
  """
  def card_strength(card) when is_binary(card) do
    case Map.fetch(@manilha_strength, card) do
      {:ok, strength} ->
        strength

      :error ->
        {value, _suit} = parse(card)
        Map.fetch!(@value_strength, value)
    end
  end

  @doc "Decompõe uma carta em `{valor, naipe}`. Levanta `ArgumentError` se inválida."
  def parse(card) when is_binary(card) do
    case String.split(card, "_", parts: 2) do
      [v, s] -> validate_parsed(card, v, s)
      _ -> raise ArgumentError, "carta inválida: #{inspect(card)}"
    end
  end

  defp validate_parsed(card, value, suit) do
    cond do
      card in @manilhas ->
        {value, suit}

      value in @common_values and suit in @suits and not (value == "A" and suit == "espadas") ->
        {value, suit}

      true ->
        raise ArgumentError, "carta inválida: #{inspect(card)}"
    end
  end

  defp card(value, suit), do: "#{value}_#{suit}"
end
