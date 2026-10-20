import React, { useEffect, useState } from "react";
import { Text, View } from "react-native";
import { api } from "../services/api";
import { useSession } from "../store/session.store";

// Painel de verificação: consulta TODOS os peers e mostra, lado a lado, o
// hash do estado desta mesa em cada réplica. Hashes iguais = réplicas
// consistentes; diferentes = divergiram (ordem diferente de comandos).
export function ReplicaPanel({ code }: { code: string }) {
  const info = useSession((s) => s.info);
  const [rows, setRows] = useState<any[]>([]);

  useEffect(() => {
    let alive = true;
    const tick = async () => {
      const peers = info?.peers ?? [];
      const results = await Promise.all(
        peers.map(async (p) => {
          try {
            const d = await api.debug(p.url);
            return { id: p.id, region: p.region, applied: d.replica.applied, hash: d.rooms[code] ?? "—", mode: d.multicast.mode };
          } catch {
            return { id: p.id, region: p.region, applied: "?", hash: "offline", mode: "?" };
          }
        })
      );
      if (alive) setRows(results);
    };
    tick();
    const t = setInterval(tick, 1500);
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, [info, code]);

  const hashes = new Set(rows.map((r) => r.hash));
  const ok = rows.length > 0 && hashes.size === 1;

  return (
    <View className="bg-black/40 rounded-2xl p-3 gap-1">
      <Text className={`font-bold ${ok ? "text-emerald-300" : "text-red-300"}`}>
        {ok ? "✓ Réplicas consistentes" : "✗ Réplicas divergentes"} · {rows[0]?.mode ?? ""}
      </Text>
      {rows.map((r) => (
        <Text key={r.id} className="text-white/80 text-xs" style={{ fontFamily: "monospace" }}>
          peer {r.id} ({r.region}) · {String(r.applied).padStart(4)} cmds · {String(r.hash).slice(0, 12)}
        </Text>
      ))}
    </View>
  );
}
