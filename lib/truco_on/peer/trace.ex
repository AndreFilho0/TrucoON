defmodule TrucoOn.Peer.Trace do
  @moduledoc """
  Rastreamento ao vivo do caminho das mensagens dentro de um peer, para o
  **painel** (`/painel`).

  O `Multicast` e a `Replica` publicam aqui o que acontece em cada camada:

      send      um datagrama saiu (para quem, se foi perdido, com que atraso)
      recv      um datagrama chegou (em ordem, adiantado ou duplicado)
      deliver   a política de ordenação entregou uma mensagem à aplicação
      apply     a réplica aplicou o comando (resultado, hash encadeado)
      queues    retrato das filas (canal FIFO e ordenação) depois da mudança

  Os eventos saem pelo PubSub **local** e só são montados quando alguém
  está assistindo (o painel assina o tópico): sem painel aberto, o custo é
  uma consulta ao Registry por evento.

  Os rótulos nunca carregam a semente do baralho nem as cartas na mão de
  ninguém: só o tipo do comando, o nome do jogador e, numa jogada, a carta
  que ele acabou de pôr na mesa (que todos vão ver de qualquer jeito).
  """

  @pubsub TrucoOn.PubSub

  def topic(inst), do: "painel:trace:#{inst}"

  @doc "Se há alguém assistindo este peer."
  def enabled?(inst), do: Registry.lookup(@pubsub, topic(inst)) != []

  @doc "Publica um evento já montado."
  def emit(inst, event) do
    Phoenix.PubSub.local_broadcast(@pubsub, topic(inst), {:trace, event})
  end

  ## Rótulos -------------------------------------------------------------------

  @doc """
  Descreve a mensagem interna (o que viaja dentro do canal confiável). O
  `kind` diz a camada: `msg` (dado da aplicação) ou `tack` (ACK do Lamport).
  `inst` serve para consultar a mesa na réplica
  local e dar nome às jogadas (truco, seis, nove...).
  """
  def inner(_inst, nil), do: %{kind: "rack"}

  def inner(inst, {:app, id, payload}),
    do: Map.merge(%{kind: "msg", id: msg_id(id)}, payload(inst, payload))

  def inner(inst, {:tm, ts, origin, id, payload}),
    do: Map.merge(%{kind: "msg", id: msg_id(id), ts: "#{ts}.#{origin}"}, payload(inst, payload))

  def inner(_inst, {:ta, ts, acker, {kts, korigin}}),
    do: %{kind: "tack", ts: ts, acker: acker, ref: "#{kts}.#{korigin}"}

  def inner(_inst, other) when is_tuple(other), do: %{kind: to_string(elem(other, 0))}
  def inner(_inst, _), do: %{kind: "?"}

  def msg_id({origin, n}), do: "#{origin}.#{n}"
  def msg_id(other), do: inspect(other)

  @doc "Rótulo curto do conteúdo (comando do jogo ou mensagem do experimento)."
  def payload(inst, {:cmd, _uid, cmd}) do
    code = command_code(cmd)
    room = code && TrucoOn.Peer.Replica.get_room(inst, code)
    %{label: command(cmd, room), code: code}
  end

  def payload(_inst, {:bench, _run, _origin, k}), do: %{label: "bench #{k}"}
  def payload(_inst, {:bench_stop, _run, _origin}), do: %{label: "bench fim"}
  def payload(_inst, _), do: %{label: "?"}

  @doc """
  Rótulo de um comando. `room` é a mesa **antes** de aplicar o comando (ou
  `nil`): é dela que sai o nome do jogador e o valor da aposta, porque o
  comando só diz `:truco` e quem decide se é truco, seis, nove ou doze é o
  estado da mão.
  """
  def command(cmd, room \\ nil)
  def command({:create, _code, p, mode, _seed}, _room), do: "#{name(p)} cria mesa #{mode}"
  def command({:join, _code, p}, _room), do: "#{name(p)} entra"
  def command({:seat, _code, pid, seat}, room), do: "#{who(room, pid)} → cadeira #{seat}"
  def command({:leave, _code, pid}, room), do: "#{who(room, pid)} sai"
  def command({:start, _code, _pid}, _room), do: "começar partida"
  def command({:rematch, _code, _pid}, _room), do: "revanche"
  def command({:act, _code, pid, action}, room), do: "#{who(room, pid)}: #{action(action, room)}"
  def command(cmd, _room) when is_tuple(cmd), do: to_string(elem(cmd, 0))
  def command(_, _room), do: "?"

  defp command_code(cmd) when is_tuple(cmd) and tuple_size(cmd) >= 2 and is_binary(elem(cmd, 1)),
    do: elem(cmd, 1)

  defp command_code(_), do: nil

  ## Jogadas -------------------------------------------------------------------

  defp action({:play_card, card}, _room) when is_binary(card), do: "joga #{card(card)}"

  # Pedir ou aumentar: o próximo valor depois da aposta atual.
  defp action(:truco, room) do
    case bet(room) do
      %{value: v} ->
        case TrucoOn.Truco.Rules.next_bet(v) do
          {:ok, next} -> "#{bet_name(next)}!"
          :error -> "aumentar (já vale 12)"
        end

      nil ->
        "truco!"
    end
  end

  defp action(:accept, room), do: "aceita" <> bet_suffix(room, " o ")
  defp action(:reject, room), do: "corre" <> bet_suffix(room, " do ")
  defp action(:accept_mao_de_11, _room), do: "aceita a mão de 11"
  defp action(:reject_mao_de_11, _room), do: "recusa a mão de 11"
  defp action(:forfeit, _room), do: "desiste"
  defp action(kind, _room) when is_atom(kind), do: to_string(kind)
  defp action(_, _room), do: "jogada"

  # "aceita o seis", "corre do nove": o valor que está sendo pedido
  defp bet_suffix(room, prep) do
    case bet(room) do
      %{value: v, pending_team: t} when not is_nil(t) and v > 1 -> prep <> bet_name(v)
      _ -> ""
    end
  end

  defp bet(%{game: %{round: %{bet: bet}}}), do: bet
  defp bet(_), do: nil

  defp bet_name(3), do: "truco"
  defp bet_name(6), do: "seis"
  defp bet_name(9), do: "nove"
  defp bet_name(12), do: "doze"
  defp bet_name(v), do: "#{v}"

  @suit %{"ouros" => "♦", "espadas" => "♠", "copas" => "♥", "paus" => "♣"}
  @manilha %{
    "4_paus" => "zap",
    "7_copas" => "copas",
    "A_espadas" => "espadilha",
    "7_ouros" => "pica-fumo"
  }

  @doc "Carta legível: `\"4_paus\"` vira `\"4♣ (zap)\"`."
  def card(card) do
    case String.split(card, "_", parts: 2) do
      [v, s] ->
        base = v <> Map.get(@suit, s, s)
        if m = @manilha[card], do: "#{base} (#{m})", else: base

      _ ->
        card
    end
  end

  ## Jogadores -----------------------------------------------------------------

  defp who(%{members: members}, pid) do
    case Enum.find(members, &(&1.id == pid)) do
      %{name: n} when is_binary(n) and n != "" -> n
      _ -> short(pid)
    end
  end

  defp who(_room, pid), do: short(pid)

  defp name(%{name: n}) when is_binary(n), do: n
  defp name(%{id: id}), do: short(id)
  defp name(_), do: "?"

  # ids de jogador são longos; sem a mesa, mostra o final
  defp short("painel-" <> rest), do: rest
  defp short(id) when is_binary(id), do: String.slice(id, -6, 6)
  defp short(id), do: inspect(id)
end
