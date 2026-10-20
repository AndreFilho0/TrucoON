defmodule TrucoOn.GroupCase do
  @moduledoc """
  Sobe um grupo completo **na mesma VM**: GroupManager, Verifier e `n`
  peers, cada um com seu socket UDP real em `127.0.0.1` (porta aleatória).
  """

  use ExUnit.CaseTemplate

  import ExUnit.Callbacks

  alias TrucoOn.Control.Client.Target
  alias TrucoOn.Control.{GroupManager, SocketServer, Verifier}
  alias TrucoOn.Peer.Multicast

  using do
    quote do
      import TrucoOn.GroupCase
    end
  end

  def start_group(n, opts \\ []) do
    transport = Keyword.get(opts, :transport, :rpc)
    Application.put_env(:truco_on, :control_transport, transport)
    Application.put_env(:truco_on, :ordering, Keyword.fetch!(opts, :ordering))

    start_supervised!(GroupManager)
    start_supervised!(Verifier)

    {gm_port, ver_port} =
      if transport == :socket do
        start_supervised!(
          Supervisor.child_spec({SocketServer, port: 0, module: GroupManager, name: :t_gm},
            id: :t_gm
          )
        )

        start_supervised!(
          Supervisor.child_spec({SocketServer, port: 0, module: Verifier, name: :t_ver},
            id: :t_ver
          )
        )

        {SocketServer.port(:t_gm), SocketServer.port(:t_ver)}
      else
        {nil, nil}
      end

    gm = %Target{node: node(), host: "127.0.0.1", port: gm_port, module: GroupManager}
    ver = %Target{node: node(), host: "127.0.0.1", port: ver_port, module: Verifier}

    insts =
      for i <- 1..n do
        inst = :"p#{i}"

        peer_opts = [
          inst: inst,
          host: "127.0.0.1",
          udp_port: 0,
          ctrl_port: 0,
          http_port: 0,
          region: "r#{i}",
          ordering: Keyword.fetch!(opts, :ordering),
          group_size: n,
          transport: transport,
          gm: gm,
          verifier: ver,
          loss: Keyword.get(opts, :loss, 0.0),
          delay_min: Keyword.get(opts, :delay_min, 0),
          delay_max: Keyword.get(opts, :delay_max, 0)
        ]

        start_supervised!(Supervisor.child_spec({TrucoOn.Peer, peer_opts}, id: inst))
        inst
      end

    wait_until(fn -> Enum.all?(insts, &Multicast.info(&1).ready) end)
    insts
  end

  def wait_until(fun, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait(fun, deadline)
  end

  defp do_wait(fun, deadline) do
    cond do
      fun.() -> :ok
      System.monotonic_time(:millisecond) > deadline -> flunk("condição não atingida a tempo")
      true -> Process.sleep(50) && do_wait(fun, deadline)
    end
  end
end
