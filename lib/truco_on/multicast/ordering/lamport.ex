defmodule TrucoOn.Multicast.Ordering.Lamport do
  @moduledoc """
  **Multicast totalmente ordenado com relógios de Lamport** (Parte 3,
  Tanenbaum & van Steen, cap. 5 — "totally ordered multicasting").

  Hipótese: canais confiáveis e FIFO (garantidos pela camada
  `TrucoOn.Multicast.Reliable`, Parte 1b).

  ## Relógio de Lamport

  Cada processo tem um contador `clock`:
    * antes de enviar: `clock += 1` e a mensagem leva `clock`;
    * ao receber uma mensagem com carimbo `t`: `clock = max(clock, t) + 1`.

  ## Protocolo

  1. Para enviar `m`, o processo carimba `m` com `(clock, id)` e manda para
     **todos** (inclusive ele mesmo).
  2. Ao receber `m`, cada processo coloca `m` numa fila ordenada pelo
     carimbo `(ts, id_origem)` — o id desempata carimbos iguais, o que gera
     uma ordem **total** — e manda um **ACK** carimbado para todos.
  3. Um processo entrega a mensagem da **cabeça** da fila quando ela tiver
     sido confirmada por **todos** os processos.

  Por que funciona: quando a cabeça `m` tem ACK de todos, qualquer mensagem
  com carimbo menor já chegou. Se um processo `p` mandou `m'` antes de
  confirmar `m`, o canal FIFO entrega `m'` antes do ACK de `p`; se mandou
  depois, o carimbo de `m'` é maior que o do ACK, que é maior que o de `m`.

  Custo: para cada multicast, `N` mensagens de dados + `N × N` ACKs.
  """

  @behaviour TrucoOn.Multicast.Ordering

  defstruct [:my_id, :ids, clock: 0, queue: nil, msgs: %{}, acks: %{}]

  @impl true
  def init(my_id, ids), do: %__MODULE__{my_id: my_id, ids: ids, queue: :gb_sets.new()}

  @impl true
  def multicast(%__MODULE__{} = st, id, payload) do
    clock = st.clock + 1
    {%{st | clock: clock}, [{:all, {:tm, clock, st.my_id, id, payload}}]}
  end

  @impl true
  def on_receive(%__MODULE__{} = st, _src, {:tm, ts, origin, id, payload}) do
    key = {ts, origin}
    # evento de recebimento
    clock = max(st.clock, ts) + 1
    # evento de envio do ACK
    clock = clock + 1

    st = %{
      st
      | clock: clock,
        queue: :gb_sets.add(key, st.queue),
        msgs: Map.put(st.msgs, key, {id, payload})
    }

    {st, deliveries} = try_deliver(st, [])
    {st, [{:all, {:ta, clock, st.my_id, key}}], deliveries}
  end

  def on_receive(%__MODULE__{} = st, _src, {:ta, ts, acker, key}) do
    # O ACK pode chegar antes da própria mensagem (vêm por canais
    # diferentes); por isso guardamos ACKs de chaves ainda desconhecidas.
    acks = Map.update(st.acks, key, MapSet.new([acker]), &MapSet.put(&1, acker))
    st = %{st | clock: max(st.clock, ts) + 1, acks: acks}
    {st, deliveries} = try_deliver(st, [])
    {st, [], deliveries}
  end

  def on_receive(st, _src, _other), do: {st, [], []}

  defp try_deliver(st, acc) do
    if :gb_sets.is_empty(st.queue) do
      {st, Enum.reverse(acc)}
    else
      {ts, origin} = head = :gb_sets.smallest(st.queue)
      acked = Map.get(st.acks, head, MapSet.new())

      if MapSet.size(acked) == length(st.ids) do
        {id, payload} = Map.fetch!(st.msgs, head)

        st = %{
          st
          | queue: :gb_sets.delete(head, st.queue),
            msgs: Map.delete(st.msgs, head),
            acks: Map.delete(st.acks, head)
        }

        delivery = %{id: id, origin: origin, payload: payload, order: {:lamport, ts, origin}}
        try_deliver(st, [delivery | acc])
      else
        {st, Enum.reverse(acc)}
      end
    end
  end

  @impl true
  def pending(%__MODULE__{queue: q}), do: :gb_sets.size(q)
end
