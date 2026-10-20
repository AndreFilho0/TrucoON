defmodule TrucoOn.Peer.Control do
  @moduledoc """
  Pedidos de controle que um peer atende (do Verifier ou de scripts),
  por socket TCP ou por RPC — mesma função `handle/2` nos dois casos.
  """

  alias TrucoOn.Peer.{Bot, Experiment, Membership, Multicast, Replica}

  def handle(inst, {:start_bench, run_id, n_msgs}) do
    %{my_id: my_id, ids: ids, ready: ready} = Multicast.info(inst)

    if ready do
      Multicast.reset_stats(inst)
      Experiment.start(inst, run_id, n_msgs, my_id, ids)
    else
      {:error, :group_not_ready}
    end
  end

  def handle(inst, :info) do
    %{me: me, view: view} = Membership.info(inst)
    %{me: me, view: view, multicast: Multicast.info(inst)}
  end

  def handle(inst, :replica_digest), do: Replica.digest(inst)
  def handle(inst, :replica_log), do: Replica.log(inst)
  def handle(inst, :stats), do: Multicast.stats(inst)
  def handle(inst, :reset_stats), do: Multicast.reset_stats(inst)
  def handle(inst, {:set_faults, faults}), do: Multicast.set_faults(inst, faults)
  def handle(inst, {:submit, cmd}), do: Replica.submit(inst, cmd)
  def handle(inst, {:view, code, player_id}), do: Replica.view(inst, code, player_id)

  def handle(inst, {:start_bots, code, player_ids, opts}) do
    Enum.each(player_ids, &Bot.start(inst, code, &1, opts))
    :ok
  end

  def handle(_inst, :ping), do: :pong
  def handle(_inst, other), do: {:error, {:unknown_request, other}}
end
