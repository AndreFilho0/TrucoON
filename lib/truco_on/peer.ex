defmodule TrucoOn.Peer do
  @moduledoc """
  Um **peer** do grupo: supervisiona os processos que formam uma réplica.

      TrucoOn.Peer (supervisor, rest_for_one)
      ├── Replica      base replicada de mesas (aplica comandos entregues)
      ├── Experiment   experimento do MPComm (mensagens numeradas + log)
      ├── Multicast    socket UDP + canal confiável + ordenação
      ├── SocketServer controle por TCP
      └── Membership   registra no GroupManager e forma o grupo

  Os processos são nomeados por `{inst, papel}` num `Registry` local, o que
  permite rodar **vários peers na mesma VM** (usado nos testes). Em produção
  cada nó Erlang roda um único peer, a instância `:main`.
  """

  use Supervisor

  alias TrucoOn.Peer.{Experiment, Membership, Multicast, Replica}

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: via(opts[:inst], :sup))

  def via(inst, role), do: {:via, Registry, {TrucoOn.Peer.Registry, {inst, role}}}

  @impl true
  def init(opts) do
    inst = Keyword.fetch!(opts, :inst)

    # porta TCP de controle sempre aberta (o RPC também funciona quando o
    # nó tem distribuição Erlang); CONTROL só escolhe qual o peer USA.
    ctrl = [
      {TrucoOn.Control.SocketServer,
       port: opts[:ctrl_port], module: TrucoOn.Peer.Control, inst: inst, name: via(inst, :ctrl)}
    ]

    children =
      [
        {Replica, opts},
        {Experiment, opts},
        {Multicast, opts}
      ] ++ ctrl ++ [{Membership, opts}]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Encaminha uma entrega do multicast para o consumidor certo."
  def dispatch(inst, %{payload: payload} = delivery) do
    case payload do
      {:cmd, _uid, _cmd} -> Replica.deliver(inst, delivery)
      {:bench, _run, _origin, _k} -> Experiment.deliver(inst, delivery)
      {:bench_stop, _run, _origin} -> Experiment.deliver(inst, delivery)
      _ -> :ok
    end
  end
end
