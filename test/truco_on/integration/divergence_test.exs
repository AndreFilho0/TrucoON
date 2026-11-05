defmodule TrucoOn.Integration.DivergenceTest do
  @moduledoc """
  Parte 2: sem ordem total, a mesma disputa de cadeiras deixa as réplicas
  diferentes. (Com perda e atraso a divergência é praticamente certa em
  8 mesas com 4 jogadores disputando ao mesmo tempo.)
  """
  use TrucoOn.GroupCase, async: false

  alias TrucoOn.Control.Scenario

  @moduletag timeout: 120_000

  for mode <- [:none, :fifo] do
    test "#{mode}: disputa de cadeiras deixa réplicas divergentes" do
      start_group(3, ordering: unquote(mode), loss: 0.0, delay_min: 0, delay_max: 40)
      report = Scenario.seat_race(rooms: 8, quiet: true, settle_ms: 1_500)
      refute report.consistent
      assert report.divergent_rooms != []
    end
  end
end
