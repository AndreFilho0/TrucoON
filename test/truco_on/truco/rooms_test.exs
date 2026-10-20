defmodule TrucoOn.Truco.RoomsTest do
  use ExUnit.Case, async: true

  alias TrucoOn.Truco.Rooms

  @ana %{id: "ana", name: "Ana"}
  @bia %{id: "bia", name: "Bia"}
  @caio %{id: "caio", name: "Caio"}
  @duda %{id: "duda", name: "Duda"}

  defp run(rooms \\ %{}, cmds) do
    Enum.reduce(cmds, rooms, fn cmd, rooms ->
      {rooms, _code, _result, _events} = Rooms.apply(rooms, cmd)
      rooms
    end)
  end

  defp lobby do
    run([
      {:create, "ABCD2345", @ana, "2v2", 10},
      {:join, "ABCD2345", @bia},
      {:join, "ABCD2345", @caio},
      {:join, "ABCD2345", @duda}
    ])
  end

  test "a ordem dos comandos decide quem fica com a cadeira (por isso a ordem total importa)" do
    a_first = run(lobby(), [{:seat, "ABCD2345", "bia", 0}, {:seat, "ABCD2345", "caio", 0}])
    c_first = run(lobby(), [{:seat, "ABCD2345", "caio", 0}, {:seat, "ABCD2345", "bia", 0}])

    assert a_first["ABCD2345"].seats == %{0 => "bia"}
    assert c_first["ABCD2345"].seats == %{0 => "caio"}
    refute a_first == c_first
  end

  test "mesma sequência ⇒ mesmo estado (réplica determinística)" do
    cmds = [{:seat, "ABCD2345", "bia", 1}, {:seat, "ABCD2345", "ana", 0}]
    assert run(lobby(), cmds) == run(lobby(), cmds)
  end

  test "fluxo completo: criar, entrar, sentar, começar e jogar" do
    rooms =
      run(lobby(), [
        {:seat, "ABCD2345", "ana", 0},
        {:seat, "ABCD2345", "bia", 1},
        {:seat, "ABCD2345", "caio", 2},
        {:seat, "ABCD2345", "duda", 3}
      ])

    assert {_, _, {:error, :not_host}, _} = Rooms.apply(rooms, {:start, "ABCD2345", "bia"})
    {rooms, _, {:ok, :started}, events} = Rooms.apply(rooms, {:start, "ABCD2345", "ana"})
    assert Enum.any?(events, &(&1.type == "game_started"))

    room = rooms["ABCD2345"]
    assert room.status == :playing
    card = hd(room.game.round.hands["ana"])
    {_rooms, _, {:ok, :ok}, _} = Rooms.apply(rooms, {:act, "ABCD2345", "ana", {:play_card, card}})

    view = Rooms.view(room, "bia")
    assert view.me == %{id: "bia", seat: 1, team: "b"}
    assert Jason.encode!(view)
  end

  test "erros não alteram o estado" do
    rooms = lobby()

    assert {^rooms, _, {:error, :room_full}, []} =
             Rooms.apply(rooms, {:join, "ABCD2345", %{id: "eva", name: "Eva"}})

    assert {^rooms, _, {:error, :seats_not_filled}, []} =
             Rooms.apply(rooms, {:start, "ABCD2345", "ana"})

    assert {^rooms, _, {:error, :code_taken}, []} =
             Rooms.apply(rooms, {:create, "ABCD2345", @ana, "1v1", 1})
  end

  test "anfitrião que sai passa o posto; último a sair fecha a mesa" do
    rooms = run([{:create, "QQQQ2222", @ana, "1v1", 1}, {:join, "QQQQ2222", @bia}])
    rooms = run(rooms, [{:leave, "QQQQ2222", "ana"}])
    assert rooms["QQQQ2222"].host_id == "bia"
    rooms = run(rooms, [{:leave, "QQQQ2222", "bia"}])
    refute Map.has_key?(rooms, "QQQQ2222")
  end
end
