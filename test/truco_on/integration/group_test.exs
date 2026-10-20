defmodule TrucoOn.Integration.GroupTest do
  @moduledoc """
  Peers reais trocando datagramas UDP, com perda e atraso artificiais.
  Cada teste reproduz um ponto do trabalho.
  """
  use TrucoOn.GroupCase, async: false

  alias TrucoOn.Control.{Scenario, Verifier}
  alias TrucoOn.Peer.Replica

  @moduletag timeout: 120_000
  @faults [loss: 0.15, delay_min: 0, delay_max: 40]

  describe "Parte 1a — controle por socket TCP e por RPC" do
    for transport <- [:socket, :rpc] do
      test "grupo forma e experimento roda com CONTROL=#{transport}" do
        start_group(3, ordering: :fifo, transport: unquote(transport))
        report = Verifier.bench(5, quiet: true)
        assert report.logs_received == 3
        assert Enum.all?(report.per_peer, fn {_id, p} -> p.missing == 0 end)
      end
    end
  end

  describe "Parte 1b — perda e FIFO sobre UDP" do
    test "sem tratamento (:none) há perda; com canal confiável (:fifo) não há perda nem violação de FIFO" do
      start_group(3, [ordering: :fifo] ++ @faults)
      report = Verifier.bench(30, quiet: true)

      for {_id, p} <- report.per_peer do
        assert p.missing == 0
        assert p.duplicates == 0
        assert p.fifo_violations == 0
      end

      assert report.cost.retransmissions > 0
    end

    test "modo :none perde mensagens com 15% de perda" do
      start_group(3, [ordering: :none] ++ @faults)
      report = Verifier.bench(30, quiet: true)
      assert Enum.any?(report.per_peer, fn {_id, p} -> p.missing > 0 end)
    end
  end

  describe "Partes 3 e 4 — ordem total" do
    for mode <- [:total, :sequencer] do
      test "#{mode}: todos entregam a mesma sequência, mesmo com perda e atraso" do
        start_group(4, [ordering: unquote(mode)] ++ @faults)
        report = Verifier.bench(15, quiet: true)
        assert report.identical
        assert report.unordered_rounds == 0
        assert Enum.all?(report.per_peer, fn {_id, p} -> p.missing == 0 end)
      end
    end

    # N = 4: Lamport = 4 + 16 = 20 mensagens por multicast;
    # sequenciador = 4 + 1 (ou só 4 quando quem envia é o próprio sequenciador)
    test "custo do Lamport: N + N² mensagens por multicast" do
      start_group(4, ordering: :total)
      assert Verifier.bench(10, quiet: true).cost.protocol_per_multicast == 20.0
    end

    test "custo do sequenciador: até N + 1 mensagens por multicast" do
      start_group(4, ordering: :sequencer)
      cost = Verifier.bench(10, quiet: true).cost.protocol_per_multicast
      assert cost > 4.0 and cost <= 5.0
    end
  end

  describe "Parte 2 + 3 — réplicas do truco" do
    test "disputa de cadeiras com ordem total: réplicas idênticas" do
      start_group(3, [ordering: :total] ++ @faults)
      report = Scenario.seat_race(rooms: 4, quiet: true, settle_ms: 1_500)
      assert report.consistent
      assert report.same_command_order
    end

    test "partidas com bots no sequenciador: réplicas idênticas" do
      [p1 | _] = start_group(3, [ordering: :sequencer] ++ @faults)
      report = Scenario.games(rooms: 2, duration_ms: 4_000, settle_ms: 2_000, quiet: true)
      assert report.consistent
      assert report.rooms == 2

      # as partidas andaram de fato (não é só "consistente porque vazio")
      [code | _] = Replica.digest(p1).rooms |> Map.keys()
      assert %{game: %{round: _}} = Replica.view(p1, code, "x")
      assert Replica.digest(p1).applied > 20
    end
  end
end
