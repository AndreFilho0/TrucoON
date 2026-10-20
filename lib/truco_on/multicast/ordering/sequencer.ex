defmodule TrucoOn.Multicast.Ordering.Sequencer do
  @moduledoc """
  Coordenação **leve** por **sequenciador** (Parte 4; cap. 7, protocolos
  baseados em primário / *remote-write*).

  Um processo do grupo — o de menor id — é o **sequenciador** (o
  "primário" que define a ordem das escritas):

  1. Quem quer enviar `m` manda só para o sequenciador: `{:req, m}`
     (1 mensagem; se o próprio remetente é o sequenciador, nem isso).
  2. O sequenciador dá a `m` o próximo número global `g` e manda
     `{:ord, g, m}` para todos (N mensagens).
  3. Cada processo entrega em ordem crescente de `g`.

  Como todas as mensagens ordenadas saem de **um único remetente** por um
  canal FIFO confiável, todos recebem na mesma ordem ⇒ **ordem total** e as
  réplicas ficam consistentes (consistência sequencial: todos veem as
  escritas na mesma ordem, a ordem escolhida pelo primário).

  Custo por multicast: `N + 1` mensagens, contra `N + N²` do Lamport.

  Preço: o sequenciador é **gargalo** e **ponto único de falha**; se ele
  cair é preciso eleger outro (algoritmo de eleição, cap. 5) e recuperar o
  último `g` — não implementado aqui.
  """

  @behaviour TrucoOn.Multicast.Ordering

  defstruct [:my_id, :ids, :sequencer, next_g: 1, expected: 1, buffer: %{}]

  @impl true
  def init(my_id, ids),
    do: %__MODULE__{my_id: my_id, ids: ids, sequencer: Enum.min(ids)}

  @doc "Id do processo que é o sequenciador."
  def sequencer(%__MODULE__{sequencer: s}), do: s

  @impl true
  def multicast(%__MODULE__{} = st, id, payload) do
    if st.my_id == st.sequencer do
      order(st, id, payload)
    else
      {st, [{st.sequencer, {:req, id, payload}}]}
    end
  end

  @impl true
  def on_receive(%__MODULE__{sequencer: me, my_id: me} = st, _src, {:req, id, payload}) do
    {st, sends} = order(st, id, payload)
    {st, sends, []}
  end

  def on_receive(%__MODULE__{} = st, _src, {:ord, g, id, payload}) do
    if g < st.expected or Map.has_key?(st.buffer, g) do
      {st, [], []}
    else
      {st, deliveries} = drain(%{st | buffer: Map.put(st.buffer, g, {id, payload})}, [])
      {st, [], deliveries}
    end
  end

  def on_receive(st, _src, _other), do: {st, [], []}

  defp order(st, id, payload) do
    g = st.next_g
    {%{st | next_g: g + 1}, [{:all, {:ord, g, id, payload}}]}
  end

  defp drain(st, acc) do
    case Map.pop(st.buffer, st.expected) do
      {nil, _} ->
        {st, Enum.reverse(acc)}

      {{{origin, _} = id, payload}, buffer} ->
        delivery = %{id: id, origin: origin, payload: payload, order: {:global_seq, st.expected}}
        drain(%{st | buffer: buffer, expected: st.expected + 1}, [delivery | acc])
    end
  end

  @impl true
  def pending(%__MODULE__{buffer: b}), do: map_size(b)
end
