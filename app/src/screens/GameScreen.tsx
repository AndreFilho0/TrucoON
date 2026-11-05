import React, { useEffect, useMemo, useState } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { ReplicaPanel } from "../components/ReplicaPanel";
import { useRoom } from "../store/room.store";
import { BET_NAME, NEXT_BET } from "../lib/cards";
import { describeEvent, reasonText } from "../lib/messages";
import { TEAM_COLOR } from "../theme";
import type { RoomView } from "../types";

export function GameScreen({ view, onExit }: { view: RoomView; onExit: () => void }) {
  const { push, feed } = useRoom();
  const [msg, setMsg] = useState<string | null>(null);
  const [showReplicas, setShowReplicas] = useState(false);
  const game = view.game!;
  const round = game.round;
  const me = view.me;
  const myTeam = me.team ?? "a";
  const otherTeam = myTeam === "a" ? "b" : "a";

  const names = useMemo(() => Object.fromEntries(game.players.map((p) => [p.id, p.name])), [game.players]);
  const name = (id: string) => (id === me.id ? "Você" : names[id] ?? "?");

  useEffect(() => {
    if (!msg) return;
    const t = setTimeout(() => setMsg(null), 2500);
    return () => clearTimeout(t);
  }, [msg]);

  const act = (event: string, payload?: object) => push(event, payload).catch((e) => setMsg(reasonText(e.message)));

  // posições relativas: eu embaixo; o próximo a jogar à direita; parceiro em cima (2v2)
  const n = game.players.length;
  const bySeatOffset = (offset: number) => game.players.find((p) => p.seat === ((me.seat ?? 0) + offset) % n);
  const top = n === 2 ? bySeatOffset(1) : bySeatOffset(2);
  const right = n === 4 ? bySeatOffset(1) : undefined;
  const left = n === 4 ? bySeatOffset(3) : undefined;

  const myTurn = round?.current_turn === me.id;
  const pendingOnMe = round?.bet_pending_team === myTeam;
  const maoDe11Mine = round?.status === "mao_de_11" && round.category === `mao_de_11_${myTeam}`;
  const canTruco =
    round && round.category === "normal" && !round.bet_pending_team && round.last_caller_team !== myTeam &&
    round.current_bet < 12 && round.status === "playing";

  const trick = round?.plays_in_trick?.length ? round.plays_in_trick : game.last_trick?.plays ?? [];
  const showingLast = !round?.plays_in_trick?.length && !!game.last_trick;

  const Opponent = ({ p }: { p?: { id: string; name: string; team: string } }) =>
    p ? (
      <View className="items-center gap-1">
        <View className="flex-row gap-0.5">
          {Array.from({ length: round?.cards_left?.[p.id] ?? 0 }).map((_, i) => (
            <Card key={i} size="sm" />
          ))}
        </View>
        <Text
          className={`text-xs font-bold px-2 py-0.5 rounded-full ${round?.current_turn === p.id ? "bg-gold text-felt-dark" : "text-white"}`}
          style={{ borderColor: TEAM_COLOR[p.team], borderWidth: 1 }}
        >
          {p.name}
        </Text>
      </View>
    ) : (
      <View />
    );

  const lastLines = feed.map((e) => describeEvent(e, name)).filter(Boolean).slice(0, 3) as string[];

  return (
    <View className="flex-1 bg-felt">
      {/* placar */}
      <View className="flex-row items-center justify-between px-4 pt-4 pb-2">
        <Pressable onPress={() => act("leave").then(onExit)}>
          <Text className="text-white/60 text-xs">← Sair</Text>
        </Pressable>
        <View className="flex-row items-center gap-3">
          <Text className="text-white font-extrabold text-lg" style={{ color: TEAM_COLOR[myTeam] }}>
            NÓS {game.scores[myTeam]}
          </Text>
          <Text className="text-white/50">×</Text>
          <Text className="text-white font-extrabold text-lg" style={{ color: TEAM_COLOR[otherTeam] }}>
            {game.scores[otherTeam]} ELES
          </Text>
        </View>
        <Pressable onPress={() => setShowReplicas(!showReplicas)}>
          <Text className="text-white/60 text-xs">⚙</Text>
        </Pressable>
      </View>

      {showReplicas && (
        <View className="px-4">
          <ReplicaPanel code={view.code} />
        </View>
      )}

      {round && (
        <View className="flex-row justify-center items-center gap-3 pb-1">
          <Text className="text-white/70 text-xs">Mão {round.number}</Text>
          <Text className="text-gold font-bold text-xs">Valendo {round.current_bet}</Text>
          <View className="flex-row gap-1">
            {[0, 1, 2].map((i) => {
              const r = round.trick_results[i];
              const bg = r ? (r === "draw" ? "#9CA3AF" : TEAM_COLOR[r]) : "transparent";
              return <View key={i} style={{ backgroundColor: bg }} className="w-3 h-3 rounded-full border border-white/50" />;
            })}
          </View>
        </View>
      )}

      {/* mesa */}
      <View className="flex-1 mx-3 my-2 rounded-[40px] bg-felt-light border-4 border-felt-dark justify-between py-4">
        <View className="items-center">
          <Opponent p={top} />
        </View>

        <View className="flex-row items-center justify-between px-2">
          <Opponent p={left} />
          <View className="items-center gap-1">
            <View className="flex-row gap-1 flex-wrap justify-center" style={{ opacity: showingLast ? 0.55 : 1 }}>
              {trick.map((pl) => (
                <View key={pl.player_id} className="items-center">
                  <Card card={pl.card} size="md" />
                  <Text className="text-white/70 text-[10px]">{name(pl.player_id)}</Text>
                </View>
              ))}
            </View>
            {showingLast && <Text className="text-white/50 text-[10px]">última vaza</Text>}
          </View>
          <Opponent p={right} />
        </View>

        <View className="items-center gap-1">
          {lastLines.map((l, i) => (
            <Text key={i} className={i === 0 ? "text-gold font-bold" : "text-white/50 text-xs"}>
              {l}
            </Text>
          ))}
        </View>
      </View>

      {/* parceiro na mão de 11 */}
      {round?.partner_cards && (
        <View className="items-center">
          <Text className="text-white/70 text-xs mb-1">Cartas do parceiro (mão de 11)</Text>
          <View className="flex-row gap-1">
            {round.partner_cards.map((c) => (
              <Card key={c} card={c} size="sm" />
            ))}
          </View>
        </View>
      )}

      {/* minha mão e ações */}
      <View className="px-4 pb-6 pt-2 gap-3">
        <Text className={`text-center font-bold ${myTurn ? "text-gold" : "text-white/60"}`}>
          {game.status === "finished"
            ? ""
            : pendingOnMe
            ? "Pediram! Aceita, foge ou aumenta?"
            : maoDe11Mine
            ? "Mão de 11: jogar ou correr?"
            : myTurn
            ? "Sua vez"
            : round?.current_turn
            ? `Vez de ${name(round.current_turn)}`
            : ""}
        </Text>

        <View className="flex-row justify-center gap-2">
          {(round?.my_cards ?? []).map((c) => (
            <Card
              key={c}
              card={c}
              size="lg"
              highlight={myTurn && !round?.bet_pending_team}
              onPress={() => act("play_card", { card: c })}
            />
          ))}
        </View>

        {game.status === "finished" ? (
          <View className="items-center gap-3">
            <Text className="text-3xl font-extrabold text-gold">
              {game.winner_team === myTeam ? "Vitória! 🏆" : "Derrota 😅"}
            </Text>
            {view.is_host ? (
              <Button title="Revanche" variant="gold" onPress={() => act("rematch")} />
            ) : (
              <Text className="text-white/60">Aguardando o anfitrião pedir revanche…</Text>
            )}
          </View>
        ) : pendingOnMe ? (
          <View className="flex-row gap-2">
            <Button title="Aceitar" variant="success" className="flex-1" onPress={() => act("accept")} />
            <Button title="Fugir" variant="danger" className="flex-1" onPress={() => act("reject")} />
            {round!.current_bet < 12 && (
              <Button title={BET_NAME[NEXT_BET[round!.current_bet]]} variant="gold" className="flex-1" onPress={() => act("truco")} />
            )}
          </View>
        ) : maoDe11Mine ? (
          <View className="flex-row gap-2">
            <Button title="Jogar (vale 3)" variant="success" className="flex-1" onPress={() => act("accept_mao_de_11")} />
            <Button title="Correr" variant="danger" className="flex-1" onPress={() => act("reject_mao_de_11")} />
          </View>
        ) : (
          <Button
            title={round && round.current_bet > 1 ? BET_NAME[NEXT_BET[round.current_bet]] ?? "TRUCO" : "TRUCO!"}
            variant="gold"
            disabled={!canTruco}
            onPress={() => act("truco")}
          />
        )}

        {msg && <Text className="text-red-300 text-center">{msg}</Text>}
      </View>
    </View>
  );
}
