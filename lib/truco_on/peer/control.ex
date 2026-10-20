defmodule TrucoOn.Peer.Control do
  @moduledoc """
  Pedidos de controle que um peer atende (do Verifier ou de scripts),
  por socket TCP ou por RPC — mesma função `handle/2` nos dois casos.
  """

  alias TrucoOn.Peer.{Experiment, Membership, Multicast}

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

  def handle(inst, :stats), do: Multicast.stats(inst)
  def handle(inst, :reset_stats), do: Multicast.reset_stats(inst)
  def handle(inst, {:set_faults, faults}), do: Multicast.set_faults(inst, faults)

  def handle(_inst, :ping), do: :pong
  def handle(_inst, other), do: {:error, {:unknown_request, other}}
end
