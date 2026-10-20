defmodule TrucoOn.Multicast.ProtocolsTest do
  @moduledoc """
  Testa o canal confiável simulando uma rede em memória que **perde,
  duplica e reordena** mensagens.
  """
  use ExUnit.Case, async: true

  alias TrucoOn.Multicast.Reliable

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
end
