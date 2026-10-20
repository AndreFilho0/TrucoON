defmodule TrucoOn.Control.GroupManager do
  @moduledoc """
  Serviço de **registro e descoberta** de peers (o `GroupMngr.py` do MPComm).

  Cada peer se registra informando como encontrá-lo (IP, porta UDP do
  multicast, porta TCP de controle, nome do nó Erlang, porta HTTP) e recebe
  um **identificador** inteiro. Os peers consultam a lista para formar o
  grupo de multicast.

  Melhorias em relação ao original:

    * `unregister` implementado (no original era `# to do`);
    * registro **idempotente**: um peer que reinicia com o mesmo endereço
      recebe o mesmo id, em vez de aparecer duplicado;
    * a lista volta com os ids, ordenada, e não só os IPs;
    * pedido desconhecido recebe resposta de erro (no original o cliente
      ficava esperando).
  """

  use GenServer
  require Logger

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Ponto de entrada comum aos transportes socket e RPC."
  def handle(_inst, {:register, info}), do: GenServer.call(__MODULE__, {:register, info})
  def handle(_inst, {:unregister, id}), do: GenServer.call(__MODULE__, {:unregister, id})
  def handle(_inst, :list), do: GenServer.call(__MODULE__, :list)
  def handle(_inst, :reset), do: GenServer.call(__MODULE__, :reset)
  def handle(_inst, :ping), do: :pong
  def handle(_inst, other), do: {:error, {:unknown_request, other}}

  @doc "Lista local (usada pelo Verifier, que roda no mesmo nó)."
  def list, do: GenServer.call(__MODULE__, :list)

  @impl true
  def init(:ok), do: {:ok, %{next_id: 1, members: %{}}}

  @impl true
  def handle_call({:register, info}, _from, state) do
    key = {info.host, info.udp_port}

    case Enum.find(state.members, fn {_id, m} -> {m.host, m.udp_port} == key end) do
      {id, _old} ->
        member = Map.put(info, :id, id)
        Logger.info("[gm] peer #{id} re-registrado #{inspect(key)}")
        {:reply, {:ok, member}, put_in(state.members[id], member)}

      nil ->
        id = state.next_id
        member = Map.put(info, :id, id)
        Logger.info("[gm] peer #{id} registrado #{inspect(key)} região=#{info[:region]}")

        {:reply, {:ok, member},
         %{state | next_id: id + 1, members: Map.put(state.members, id, member)}}
    end
  end

  def handle_call({:unregister, id}, _from, state) do
    Logger.info("[gm] peer #{id} saiu")
    {:reply, :ok, %{state | members: Map.delete(state.members, id)}}
  end

  def handle_call(:list, _from, state) do
    {:reply, {:ok, state.members |> Map.values() |> Enum.sort_by(& &1.id)}, state}
  end

  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{next_id: 1, members: %{}}}
end
