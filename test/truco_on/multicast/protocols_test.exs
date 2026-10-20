defmodule TrucoOn.Multicast.ProtocolsTest do
  @moduledoc """
  Testa as estruturas puras dos protocolos simulando uma rede em memória
  que **perde, duplica e reordena** mensagens.
  """
  use ExUnit.Case, async: true

  alias TrucoOn.Multicast.Reliable
  alias TrucoOn.Multicast.Ordering.{Basic, Lamport}

  describe "Reliable (Parte 1b)" do
    test "entrega tudo, sem duplicatas e em ordem FIFO, mesmo com perda e reordenação" do
      :rand.seed(:exsss, {1, 2, 3})
      {sender, packets} = send_n(Reliable.new(), :b, 1..200)
      {_sender, receiver, delivered} = lossy_exchange(sender, Reliable.new(), packets, loss: 0.3)
      assert delivered == Enum.to_list(1..200)
      assert Reliable.held_back(receiver) == 0
    end

    test "mensagem adiantada fica na fila de espera até a lacuna ser preenchida" do
      r = Reliable.new()
      {r, [], 0, :held_back} = Reliable.on_data(r, :a, 2, :m2)
      {r, [], 0, :held_back} = Reliable.on_data(r, :a, 3, :m3)
      assert Reliable.held_back(r) == 2
      {r, [:m1, :m2, :m3], 3, :in_order} = Reliable.on_data(r, :a, 1, :m1)
      {_r, [], 3, :duplicate} = Reliable.on_data(r, :a, 2, :m2)
    end

    test "retransmite só o que passou do RTO e ainda não foi confirmado" do
      {r, 1} = Reliable.send(Reliable.new(), :b, :x, 0)
      {r, 2} = Reliable.send(r, :b, :y, 0)
      r = Reliable.on_ack(r, :b, 1)
      assert {_r, [{:b, 2, :y}]} = Reliable.due(r, 200, 150)
      assert {_r, []} = Reliable.due(r, 100, 150)
    end
  end

  describe "ordem total" do
    for mod <- [Lamport] do
      test "#{inspect(mod)}: todos os processos entregam a mesma sequência" do
        :rand.seed(:exsss, {7, 8, 9})

        for _round <- 1..20 do
          sequences = simulate(unquote(mod), [1, 2, 3, 4], 8)
          assert sequences |> Map.values() |> Enum.uniq() |> length() == 1
          assert length(sequences[1]) == 4 * 8
        end
      end
    end

    test "sem coordenação (Basic) as sequências costumam divergir" do
      :rand.seed(:exsss, {4, 5, 6})

      divergent =
        Enum.count(1..20, fn _ ->
          simulate(Basic, [1, 2, 3, 4], 8) |> Map.values() |> Enum.uniq() |> length() > 1
        end)

      assert divergent > 0
    end

    test "custo em mensagens: Lamport N + N²" do
      assert count_messages(Lamport, [1, 2, 3, 4]) == 4 + 16
    end
  end

  ## Simulação -------------------------------------------------------------------

  defp send_n(r, dest, range) do
    Enum.reduce(range, {r, []}, fn i, {r, acc} ->
      {r, seq} = Reliable.send(r, dest, i, 0)
      {r, acc ++ [{seq, i}]}
    end)
  end

  # Troca entre um remetente e um destinatário com perda nos dois sentidos,
  # até tudo ser confirmado.
  defp lossy_exchange(sender, receiver, initial, opts, now \\ 0, delivered \\ []) do
    loss = opts[:loss]
    arrivals = initial |> Enum.reject(fn _ -> :rand.uniform() < loss end) |> Enum.shuffle()

    {receiver, delivered, acks} =
      Enum.reduce(arrivals, {receiver, delivered, []}, fn {seq, inner}, {rcv, del, acks} ->
        {rcv, out, cum, _} = Reliable.on_data(rcv, :a, seq, inner)
        {rcv, del ++ out, [cum | acks]}
      end)

    sender =
      acks
      |> Enum.reject(fn _ -> :rand.uniform() < loss end)
      |> Enum.reduce(sender, &Reliable.on_ack(&2, :b, &1))

    if Reliable.pending(sender) == 0 do
      {sender, receiver, delivered}
    else
      now = now + 200
      {sender, late} = Reliable.due(sender, now, 150)

      lossy_exchange(
        sender,
        receiver,
        Enum.map(late, fn {_d, s, i} -> {s, i} end),
        opts,
        now,
        delivered
      )
    end
  end

  # Rede em memória com canais FIFO (como os da camada Reliable) mas com
  # entrega **intercalada aleatoriamente** entre canais diferentes.
  defp simulate(mod, ids, per_process) do
    states = Map.new(ids, &{&1, mod.init(&1, ids)})

    # todos os processos querem enviar per_process mensagens
    todo = for i <- ids, k <- 1..per_process, do: {i, k}
    channels = %{}
    loop(mod, ids, states, channels, Enum.shuffle(todo), Map.new(ids, &{&1, []}))
  end

  defp loop(mod, ids, states, channels, todo, delivered) do
    busy = channels |> Enum.filter(fn {_k, q} -> q != [] end) |> Enum.map(&elem(&1, 0))

    cond do
      todo == [] and busy == [] ->
        Map.new(delivered, fn {id, list} -> {id, Enum.reverse(list)} end)

      todo != [] and (busy == [] or :rand.uniform() < 0.3) ->
        [{i, k} | rest] = todo
        {st, sends} = mod.multicast(states[i], {i, k}, {i, k})
        channels = enqueue(channels, i, ids, sends)
        loop(mod, ids, Map.put(states, i, st), channels, rest, delivered)

      true ->
        {from, to} = key = Enum.random(busy)
        [msg | q] = channels[key]
        {st, sends, deliveries} = mod.on_receive(states[to], from, msg)
        channels = channels |> Map.put(key, q) |> enqueue(to, ids, sends)

        delivered =
          Map.update!(
            delivered,
            to,
            &(Enum.reverse(Enum.map(deliveries, fn d -> d.payload end)) ++ &1)
          )

        loop(mod, ids, Map.put(states, to, st), channels, todo, delivered)
    end
  end

  defp enqueue(channels, from, ids, sends) do
    Enum.reduce(sends, channels, fn {target, msg}, ch ->
      dests = if target == :all, do: ids, else: [target]
      Enum.reduce(dests, ch, fn d, ch -> Map.update(ch, {from, d}, [msg], &(&1 ++ [msg])) end)
    end)
  end

  # Mensagens geradas por UM multicast de um processo que não é o sequenciador.
  defp count_messages(mod, ids) do
    states = Map.new(ids, &{&1, mod.init(&1, ids)})
    {st, sends} = mod.multicast(states[2], {2, 1}, :x)
    states = Map.put(states, 2, st)
    drain(mod, ids, states, Enum.map(expand(sends, 2, ids), & &1), 0)
  end

  defp drain(_mod, _ids, _states, [], count), do: count

  defp drain(mod, ids, states, [{from, to, msg} | rest], count) do
    {st, sends, _} = mod.on_receive(states[to], from, msg)
    drain(mod, ids, Map.put(states, to, st), rest ++ expand(sends, to, ids), count + 1)
  end

  defp expand(sends, from, ids) do
    Enum.flat_map(sends, fn {target, msg} ->
      dests = if target == :all, do: ids, else: [target]
      Enum.map(dests, &{from, &1, msg})
    end)
  end
end
