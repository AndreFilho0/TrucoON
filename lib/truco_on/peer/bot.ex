defmodule TrucoOn.Peer.Bot do
  @moduledoc """
  Jogador automático, usado nos cenários de teste do Verifier.

  O bot roda no peer ao qual o "jogador" estaria conectado, lê a visão da
  mesa **da réplica local** (ETS) e envia comandos por `Replica.submit/2`,
  exatamente como um jogador humano pelo WebSocket. Com vários bots em
  peers diferentes, comandos concorrentes (ex.: um pede truco enquanto o
  outro joga a carta) disputam a ordem — é o que expõe a divergência entre
  réplicas quando não há ordem total.
  """

  alias TrucoOn.Peer.Replica

  def start(inst, code, player_id, opts \\ []) do
    duration = Keyword.get(opts, :duration_ms, 20_000)
    deadline = System.monotonic_time(:millisecond) + duration
    Task.start(fn -> loop(inst, code, player_id, deadline, opts) end)
  end

  defp loop(inst, code, player_id, deadline, opts) do
    if System.monotonic_time(:millisecond) < deadline do
      {min_ms, max_ms} = Keyword.get(opts, :think_ms, {20, 120})
      Process.sleep(Enum.random(min_ms..max_ms))

      case Replica.view(inst, code, player_id) do
        %{status: :finished} ->
          :done

        %{game: %{round: round}, me: me} when is_map(round) ->
          if action = choose(round, me, player_id, opts) do
            Replica.submit(inst, {:act, code, player_id, action})
          end

          loop(inst, code, player_id, deadline, opts)

        _ ->
          loop(inst, code, player_id, deadline, opts)
      end
    end
  end

  @doc false
  def choose(round, me, player_id, opts) do
    chaos = Keyword.get(opts, :chaos, 0.05)
    my_team = me.team

    cond do
      round.status == :mao_de_11 and round.category == "mao_de_11_#{my_team}" ->
        if :rand.uniform() < 0.8, do: :accept_mao_de_11, else: :reject_mao_de_11

      round.bet_pending_team == my_team ->
        r = :rand.uniform()

        cond do
          r < 0.5 -> :accept
          r < 0.7 -> :reject
          round.current_bet < 12 -> :truco
          true -> :accept
        end

      round.current_turn == player_id and is_nil(round.bet_pending_team) and
        round.status in [:playing, :mao_de_ferro] and round.my_cards != [] ->
        if round.category == "normal" and round.last_caller_team != my_team and
             round.current_bet < 12 and :rand.uniform() < 0.15 do
          :truco
        else
          {:play_card, Enum.random(round.my_cards)}
        end

      :rand.uniform() < chaos and round.category == "normal" ->
        # ação "fora de hora", como um jogador apressado com a tela atrasada
        :truco

      true ->
        nil
    end
  end
end
