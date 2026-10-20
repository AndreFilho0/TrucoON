defmodule TrucoOn.Multicast.Reliable do
  @moduledoc """
  Canais **confiáveis e FIFO** sobre UDP (Parte 1b). Estrutura de dados pura.

  O UDP pode perder, duplicar e reordenar datagramas. Para cada par
  (remetente → destinatário) mantemos um canal com:

  **Lado do remetente** (`out`)
    * número de sequência próprio do canal (`next`), começando em 1;
    * mensagens ainda não confirmadas (`unacked`), guardadas até chegar o ACK.
      Se o ACK não chega em `rto` ms, a mensagem é **retransmitida**.

  **Lado do destinatário** (`in`)
    * próximo número esperado (`expected`);
    * fila de espera (*hold-back queue*, `buffer`) para mensagens que
      chegaram adiantadas.

  Ao receber a mensagem `seq`:
    * `seq < expected` ou já está no buffer → **duplicada**, descarta
      (mas confirma de novo, porque o ACK anterior pode ter se perdido);
    * senão guarda no buffer e entrega em ordem tudo que estiver contíguo a
      partir de `expected` ⇒ **ordem FIFO por remetente**;
    * responde com **ACK cumulativo** `expected - 1` ("recebi tudo até aqui").

  Perda é detectada pelo remetente (falta de ACK → retransmite) e lacunas no
  destinatário ficam paradas no buffer até a retransmissão preencher.
  """

  defstruct out: %{}, in: %{}

  @type peer :: term
  @type t :: %__MODULE__{}

  def new, do: %__MODULE__{}

  @doc "Registra o envio de `inner` para `dest`. Devolve `{r, seq}`."
  def send(%__MODULE__{} = r, dest, inner, now) do
    ch = Map.get(r.out, dest, %{next: 1, unacked: %{}})
    seq = ch.next
    ch = %{ch | next: seq + 1, unacked: Map.put(ch.unacked, seq, {inner, now})}
    {%{r | out: Map.put(r.out, dest, ch)}, seq}
  end

  @doc """
  Processa um dado `seq` vindo de `src`. Devolve
  `{r, entregues_em_ordem, ack_cumulativo, status}`, com status
  `:in_order | :held_back | :duplicate`.
  """
  def on_data(%__MODULE__{} = r, src, seq, inner) do
    ch = Map.get(r.in, src, %{expected: 1, buffer: %{}})

    if seq < ch.expected or Map.has_key?(ch.buffer, seq) do
      {r, [], ch.expected - 1, :duplicate}
    else
      status = if seq == ch.expected, do: :in_order, else: :held_back
      {expected, buffer, delivered} = drain(ch.expected, Map.put(ch.buffer, seq, inner), [])
      ch = %{expected: expected, buffer: buffer}
      {%{r | in: Map.put(r.in, src, ch)}, delivered, expected - 1, status}
    end
  end

  defp drain(expected, buffer, acc) do
    case Map.pop(buffer, expected) do
      {nil, buffer} -> {expected, buffer, Enum.reverse(acc)}
      {inner, buffer} -> drain(expected + 1, buffer, [inner | acc])
    end
  end

  @doc "ACK cumulativo de `dest`: descarta tudo com `seq <= cum`."
  def on_ack(%__MODULE__{} = r, dest, cum) do
    case Map.fetch(r.out, dest) do
      {:ok, ch} ->
        unacked = Map.reject(ch.unacked, fn {seq, _} -> seq <= cum end)
        %{r | out: Map.put(r.out, dest, %{ch | unacked: unacked})}

      :error ->
        r
    end
  end

  @doc """
  Mensagens cujo ACK está atrasado (`now - enviado >= rto`). Devolve
  `{r, [{dest, seq, inner}]}` já marcando o novo horário de envio.
  """
  def due(%__MODULE__{} = r, now, rto) do
    Enum.reduce(r.out, {r, []}, fn {dest, ch}, {r, acc} ->
      late = for {seq, {inner, sent}} <- ch.unacked, now - sent >= rto, do: {seq, inner}

      if late == [] do
        {r, acc}
      else
        unacked =
          Enum.reduce(late, ch.unacked, fn {seq, inner}, u -> Map.put(u, seq, {inner, now}) end)

        r = %{r | out: Map.put(r.out, dest, %{ch | unacked: unacked})}
        {r, acc ++ Enum.map(Enum.sort(late), fn {seq, inner} -> {dest, seq, inner} end)}
      end
    end)
  end

  @doc "Quantas mensagens ainda esperam ACK (em todos os canais)."
  def pending(%__MODULE__{out: out}),
    do: Enum.reduce(out, 0, fn {_d, ch}, n -> n + map_size(ch.unacked) end)

  @doc "Quantas mensagens estão paradas na fila de espera (em todos os canais)."
  def held_back(%__MODULE__{in: inn}),
    do: Enum.reduce(inn, 0, fn {_s, ch}, n -> n + map_size(ch.buffer) end)
end
