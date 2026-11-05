defmodule TrucoOn.Control.Scenario do
  @moduledoc """
  Cenários de truco para mostrar (e medir) o efeito da ordenação.

      S.seat_race(rooms: 10)              # disputa de cadeiras no lobby
      S.games(rooms: 3, duration_ms: 20_000)  # partidas inteiras com bots

  Os jogadores de cada mesa são distribuídos entre peers diferentes (como
  amigos em regiões diferentes) e agem ao mesmo tempo. No fim, o Verifier
  compara as réplicas. Com `ORDERING=none` ou `fifo` as réplicas tendem a
  divergir; com `total` ou `sequencer` devem ficar idênticas.
  """

  alias TrucoOn.Control.{Client, Verifier}
  alias TrucoOn.Truco.Code

  @doc """
  **Disputa de cadeiras**: cada mesa 2v2 tem 4 jogadores em peers
  diferentes; todos pedem as cadeiras na mesma ordem e ao mesmo tempo.
  Quem ganha cada cadeira depende da ordem em que os pedidos são aplicados.
  """
  def seat_race(opts \\ []) do
    rooms = Keyword.get(opts, :rooms, 10)
    members = Verifier.peers()

    tables = for r <- 1..rooms, do: setup_room(r, members)

    tables
    |> Task.async_stream(
      fn t ->
        t.players
        |> Task.async_stream(fn {p, m} -> grab_seat(m, t.code, p.id, 4) end, timeout: 60_000)
        |> Stream.run()
      end,
      timeout: 120_000
    )
    |> Stream.run()

    Process.sleep(Keyword.get(opts, :settle_ms, 2_000))
    Verifier.replicas(opts)
  end

  @doc """
  **Partidas com bots**: cria `rooms` mesas 2v2, senta todos, começa e
  deixa bots jogando por `duration_ms` em cada peer.
  """
  def games(opts \\ []) do
    rooms = Keyword.get(opts, :rooms, 3)
    duration = Keyword.get(opts, :duration_ms, 20_000)
    members = Verifier.peers()

    tables = for r <- 1..rooms, do: setup_room(r, members)

    for t <- tables do
      for {{p, m}, seat} <- Enum.with_index(t.players) do
        submit(m, {:seat, t.code, p.id, seat})
      end

      {host, host_member} = hd(t.players)
      submit(host_member, {:start, t.code, host.id})

      t.players
      |> Enum.group_by(fn {_p, m} -> m.id end)
      |> Enum.each(fn {_id, list} ->
        {_, m} = hd(list)
        ids = Enum.map(list, fn {p, _} -> p.id end)

        Client.request(
          Client.peer(m),
          {:start_bots, t.code, ids,
           [duration_ms: duration] ++ Keyword.take(opts, [:chaos, :think_ms])}
        )
      end)
    end

    Process.sleep(duration + Keyword.get(opts, :settle_ms, 3_000))
    Verifier.replicas(opts)
  end

  ## Auxiliares ----------------------------------------------------------------

  defp setup_room(r, members) do
    n = length(members)
    code = Code.generate()

    players =
      for i <- 0..3 do
        p = %{id: "bot-#{code}-#{i}", name: "Bot #{i + 1}"}
        {p, Enum.at(members, rem(r + i, n))}
      end

    [{host, host_member} | others] = players
    {:ok, _} = submit(host_member, {:create, code, host, "2v2", :rand.uniform(1_000_000)})

    others
    |> Task.async_stream(fn {p, m} -> submit(m, {:join, code, p}) end, timeout: 60_000)
    |> Stream.run()

    %{code: code, players: players}
  end

  # tenta as cadeiras 0, 1, 2, 3 em ordem até conseguir uma
  defp grab_seat(member, code, player_id, capacity) do
    Enum.reduce_while(0..(capacity - 1), nil, fn seat, _ ->
      case submit(member, {:seat, code, player_id, seat}) do
        {:ok, _} -> {:halt, seat}
        _ -> {:cont, nil}
      end
    end)
  end

  defp submit(member, cmd),
    do: Client.request(Client.peer(member), {:submit, cmd}, timeout: 30_000)
end
