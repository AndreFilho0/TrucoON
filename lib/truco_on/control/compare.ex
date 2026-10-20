defmodule TrucoOn.Control.Compare do
  @moduledoc """
  Comparação das sequências entregues pelos peers (funções puras).

  O `comparisonServer.py` original contava as "rodadas fora de ordem"
  comparando só as posições `0..N_MSGS-2` e só os peers `0..N-2` (o laço
  `range(1, N-1)` deixa o último peer de fora). Além de corrigir isso,
  medimos também perdas, duplicatas e violações de FIFO de cada peer.
  """

  @doc """
  Compara os logs do experimento. `logs` é `%{peer_id => [{origem, k}]}`.
  `origins` são os ids que enviaram, cada um `n` mensagens.
  """
  def bench(logs, origins, n) do
    expected = MapSet.new(for o <- origins, k <- 1..n//1, do: {o, k})

    per_peer =
      Map.new(logs, fn {peer, log} ->
        set = MapSet.new(log)

        {peer,
         %{
           delivered: length(log),
           missing: MapSet.size(MapSet.difference(expected, set)),
           duplicates: length(log) - MapSet.size(set),
           fifo_violations: fifo_violations(log)
         }}
      end)

    Map.merge(%{per_peer: per_peer, expected_per_peer: MapSet.size(expected)}, sequences(logs))
  end

  @doc """
  Compara sequências genéricas entre peers: posições em que algum peer
  difere (`unordered_rounds`, a métrica do MPComm), primeira divergência e
  se são idênticas.
  """
  def sequences(logs) do
    seqs = Map.values(logs)
    max_len = seqs |> Enum.map(&length/1) |> Enum.max(fn -> 0 end)
    padded = Enum.map(seqs, fn s -> s ++ List.duplicate(nil, max_len - length(s)) end)

    differing =
      padded
      |> Enum.zip()
      |> Enum.with_index()
      |> Enum.reject(fn {column, _j} ->
        column |> Tuple.to_list() |> Enum.uniq() |> length() == 1
      end)
      |> Enum.map(&elem(&1, 1))

    %{
      positions: max_len,
      unordered_rounds: length(differing),
      first_divergence: List.first(differing),
      identical: differing == []
    }
  end

  @doc "Quantas vezes uma mensagem de uma origem chegou depois de uma posterior dela."
  def fifo_violations(log) do
    {count, _last} =
      Enum.reduce(log, {0, %{}}, fn {origin, k}, {count, last} ->
        prev = Map.get(last, origin, 0)
        if k < prev, do: {count + 1, last}, else: {count, Map.put(last, origin, k)}
      end)

    count
  end

  @doc "Compara os resumos das réplicas (`Replica.digest/1`) de cada peer."
  def replicas(digests) do
    codes = digests |> Map.values() |> Enum.flat_map(&Map.keys(&1.rooms)) |> Enum.uniq()

    divergent =
      Enum.filter(codes, fn code ->
        digests |> Map.values() |> Enum.map(&Map.get(&1.rooms, code)) |> Enum.uniq() |> length() >
          1
      end)

    %{
      rooms: length(codes),
      divergent_rooms: divergent,
      same_command_order:
        digests |> Map.values() |> Enum.map(& &1.chain) |> Enum.uniq() |> length() == 1,
      applied: Map.new(digests, fn {id, d} -> {id, d.applied} end),
      consistent:
        divergent == [] and
          digests |> Map.values() |> Enum.map(& &1.state_hash) |> Enum.uniq() |> length() <= 1
    }
  end
end
