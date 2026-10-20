defmodule TrucoOn.Multicast.Ordering do
  @moduledoc """
  Contrato das políticas de ordenação do multicast.

  Uma política é uma estrutura de dados pura que fica **acima** do canal
  (confiável FIFO, ou UDP cru no modo `:none`):

    * `multicast/3` — a aplicação quer enviar `payload` ao grupo. Devolve as
      mensagens que precisam sair: `{destino | :all, mensagem}`.
    * `on_receive/3` — chegou `mensagem` de `src` pelo canal. Devolve novas
      mensagens para enviar (ex.: ACKs do Lamport) e as **entregas** à
      aplicação, já na ordem da política.

  Separar política (pura) de transporte (GenServer com socket) permite
  testar os algoritmos sem rede e trocar a política só pela configuração.
  """

  @type msg_id :: {non_neg_integer, non_neg_integer}
  @type send_spec :: {:all | non_neg_integer, tuple}
  @type delivery :: %{id: msg_id, origin: non_neg_integer, payload: term, order: term}

  @callback init(my_id :: non_neg_integer, ids :: [non_neg_integer]) :: term
  @callback multicast(state :: term, msg_id, payload :: term) :: {term, [send_spec]}
  @callback on_receive(state :: term, src :: non_neg_integer, msg :: tuple) ::
              {term, [send_spec], [delivery]}
  @callback pending(state :: term) :: non_neg_integer

  @doc "Módulo da política para cada modo configurável."
  def module(:none), do: TrucoOn.Multicast.Ordering.Basic
  def module(:fifo), do: TrucoOn.Multicast.Ordering.Basic

  @doc "Se o modo usa o canal confiável FIFO por baixo."
  def reliable?(:none), do: false
  def reliable?(_), do: true
end

defmodule TrucoOn.Multicast.Ordering.Basic do
  @moduledoc """
  Sem coordenação: entrega cada mensagem assim que o canal entrega.

    * Em `:none` o canal é UDP cru ⇒ pode perder e reordenar (o MPComm
      original).
    * Em `:fifo` o canal é confiável e FIFO ⇒ sem perdas e na ordem de cada
      remetente, mas mensagens de remetentes **diferentes** ainda chegam em
      ordens diferentes em cada peer (não há ordem total).
  """

  @behaviour TrucoOn.Multicast.Ordering

  @impl true
  def init(my_id, ids), do: %{my_id: my_id, ids: ids}

  @impl true
  def multicast(st, id, payload), do: {st, [{:all, {:app, id, payload}}]}

  @impl true
  def on_receive(st, _src, {:app, {origin, _} = id, payload}),
    do: {st, [], [%{id: id, origin: origin, payload: payload, order: nil}]}

  def on_receive(st, _src, _other), do: {st, [], []}

  @impl true
  def pending(_st), do: 0
end
