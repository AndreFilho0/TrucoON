defmodule TrucoOn.Integration.GroupTest do
  @moduledoc """
  Peers reais trocando datagramas UDP, com perda e atraso artificiais.
  Cada teste reproduz um ponto do trabalho.
  """
  use TrucoOn.GroupCase, async: false

  alias TrucoOn.Control.{Scenario, Verifier}

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

  describe "Parte 3 — ordem total" do
    test "total: todos entregam a mesma sequência, mesmo com perda e atraso" do
      start_group(4, [ordering: :total] ++ @faults)
      report = Verifier.bench(15, quiet: true)
      assert report.identical
      assert report.unordered_rounds == 0
      assert Enum.all?(report.per_peer, fn {_id, p} -> p.missing == 0 end)
    end

    # N = 4: Lamport = 4 + 16 = 20 mensagens por multicast
    test "custo do Lamport: N + N² mensagens por multicast" do
      start_group(4, ordering: :total)
      assert Verifier.bench(10, quiet: true).cost.protocol_per_multicast == 20.0
    end
  end

  describe "Parte 2 + 3 — réplicas do truco" do
    test "disputa de cadeiras com ordem total: réplicas idênticas" do
      start_group(3, [ordering: :total] ++ @faults)
      report = Scenario.seat_race(rooms: 4, quiet: true, settle_ms: 1_500)
      assert report.consistent
      assert report.same_command_order
    end
  end
end
