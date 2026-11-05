import React, { useEffect, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";
import { useSession } from "../store/session.store";

// Mostra a qual peer (região) o jogador está ligado e permite trocar.
// Todos os peers têm réplica de todas as mesas, então qualquer um serve.
export function ServerPicker({ dark = false }: { dark?: boolean }) {
  const { server, info, setServer, loadInfo } = useSession();
  const [open, setOpen] = useState(false);
  const [custom, setCustom] = useState(server);

  useEffect(() => {
    loadInfo();
  }, [server]);

  const label = info
    ? `Servidor ${info.peer_id} · ${info.region} · ${info.ordering}`
    : "Servidor offline";
  const text = dark ? "text-white/80" : "text-text-secondary";

  return (
    <View className="items-center">
      <Pressable onPress={() => setOpen(!open)} className="flex-row items-center gap-2 py-1">
        <View className={`w-2 h-2 rounded-full ${info?.group_ready ? "bg-emerald-400" : "bg-red-400"}`} />
        <Text className={`text-xs ${text}`}>{label} ▾</Text>
      </Pressable>
      {open && (
        <View className="bg-surface rounded-2xl p-3 mt-2 w-full gap-2 border border-border">
          {(info?.peers ?? []).map((p) => (
            <Pressable
              key={p.id}
              onPress={() => {
                setServer(p.url);
                setOpen(false);
              }}
              className={`rounded-xl px-3 py-2 ${p.url === server ? "bg-primary" : "bg-background"}`}
            >
              <Text className={p.url === server ? "text-white" : "text-text-primary"}>
                Peer {p.id} · {p.region} · {p.url}
              </Text>
            </Pressable>
          ))}
          <View className="flex-row gap-2">
            <TextInput
              value={custom}
              onChangeText={setCustom}
              autoCapitalize="none"
              className="flex-1 bg-background rounded-xl px-3 py-2 text-text-primary"
            />
            <Pressable onPress={() => setServer(custom)} className="bg-primary rounded-xl px-3 justify-center">
              <Text className="text-white font-bold">Usar</Text>
            </Pressable>
          </View>
        </View>
      )}
    </View>
  );
}
