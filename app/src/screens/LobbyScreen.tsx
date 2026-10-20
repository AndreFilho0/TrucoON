import React, { useState } from "react";
import { Platform, Pressable, ScrollView, Share, Text, View } from "react-native";
import QRCode from "react-native-qrcode-svg";
import { Button } from "../components/Button";
import { ReplicaPanel } from "../components/ReplicaPanel";
import { useRoom } from "../store/room.store";
import { useSession } from "../store/session.store";
import { formatCode, inviteLink } from "../lib/route";
import { reasonText } from "../lib/messages";
import type { RoomView } from "../types";

export function LobbyScreen({ view, onExit }: { view: RoomView; onExit: () => void }) {
  const push = useRoom((s) => s.push);
  const server = useSession((s) => s.server);
  const [msg, setMsg] = useState<string | null>(null);
  const [showReplicas, setShowReplicas] = useState(false);

  const display = formatCode(view.code);
  const link = inviteLink(display, server);
  const full = view.seats.every((s) => s.player);

  const act = (event: string, payload?: object) =>
    push(event, payload).catch((e) => setMsg(reasonText(e.message)));

  const share = async () => {
    try {
      if (Platform.OS === "web" && (navigator as any).share) {
        await (navigator as any).share({ title: "TrucoON", text: "Bora um truco?", url: link });
      } else if (Platform.OS === "web") {
        await navigator.clipboard.writeText(link);
        setMsg("Link copiado!");
      } else {
        await Share.share({ message: `Bora um truco? ${link}` });
      }
    } catch {}
  };

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(link);
      setMsg("Link copiado!");
    } catch {
      setMsg(link);
    }
  };

  // mesa vista de cima: cadeira 0 embaixo, 1 à direita, 2 em cima, 3 à esquerda
  const seat = (n: number) => view.seats.find((s) => s.seat === n);
  const SeatBox = ({ n }: { n: number }) => {
    const s = seat(n);
    if (!s) return <View className="w-24" />;
    const mine = s.player?.id === view.me.id;
    return (
      <Pressable
        onPress={() => !s.player && act("seat", { seat: n })}
        className={`w-24 h-16 rounded-2xl items-center justify-center border-2 ${
          s.team === "a" ? "border-teamA" : "border-teamB"
        } ${s.player ? (mine ? "bg-gold" : "bg-white/90") : "bg-white/10"}`}
      >
        <Text numberOfLines={1} className={`font-bold ${s.player ? "text-felt-dark" : "text-white/70"}`}>
          {s.player ? s.player.name : "Sentar"}
        </Text>
        <Text className={`text-xs ${s.player ? "text-felt-dark/60" : "text-white/40"}`}>Time {s.team.toUpperCase()}</Text>
      </Pressable>
    );
  };

  return (
    <ScrollView className="flex-1 bg-felt" contentContainerStyle={{ padding: 20, gap: 18 }}>
      <View className="flex-row items-center justify-between">
        <Pressable onPress={() => act("leave").then(onExit)}>
          <Text className="text-white/70">← Sair</Text>
        </Pressable>
        <Text className="text-white/70">Mesa {view.mode === "1v1" ? "1 x 1" : "2 x 2"}</Text>
        <Pressable onPress={() => setShowReplicas(!showReplicas)}>
          <Text className="text-white/70">⚙ Réplicas</Text>
        </Pressable>
      </View>

      {showReplicas && <ReplicaPanel code={view.code} />}

      <View className="items-center bg-felt-light rounded-3xl p-5 gap-3">
        <Text className="text-white/70">Chame a galera com o código</Text>
        <Text className="text-gold text-4xl font-extrabold tracking-widest">{display}</Text>
        <View className="bg-white p-3 rounded-2xl">
          <QRCode value={link} size={170} />
        </View>
        <View className="flex-row gap-3 w-full">
          <Button title="Copiar link" variant="ghost" className="flex-1" onPress={copy} />
          <Button title="Compartilhar" variant="gold" className="flex-1" onPress={share} />
        </View>
      </View>

      <View className="bg-felt-dark rounded-3xl p-5 items-center gap-3">
        <Text className="text-white/70 mb-1">Escolha sua cadeira (parceiros ficam de frente)</Text>
        {view.mode === "2v2" && <SeatBox n={2} />}
        <View className="flex-row items-center justify-between w-full">
          {view.mode === "2v2" ? <SeatBox n={3} /> : <View className="w-24" />}
          <View className="w-16 h-16 rounded-full bg-felt-light items-center justify-center">
            <Text className="text-2xl">🃏</Text>
          </View>
          {view.mode === "2v2" ? <SeatBox n={1} /> : <View className="w-24" />}
        </View>
        {view.mode === "1v1" && <SeatBox n={1} />}
        <SeatBox n={0} />
      </View>

      <View className="gap-1">
        <Text className="text-white/70">Na mesa ({view.members.length}/{view.capacity})</Text>
        {view.members.map((m) => (
          <Text key={m.id} className="text-white">
            {m.id === view.host_id ? "👑 " : "• "}
            {m.name}
            {m.id === view.me.id ? " (você)" : ""}
          </Text>
        ))}
      </View>

      {msg && <Text className="text-gold text-center">{msg}</Text>}

      {view.is_host ? (
        <Button title={full ? "Começar partida" : "Aguardando jogadores…"} variant="gold" disabled={!full} onPress={() => act("start")} />
      ) : (
        <Text className="text-white/60 text-center">O anfitrião começa quando todos sentarem.</Text>
      )}
    </ScrollView>
  );
}
