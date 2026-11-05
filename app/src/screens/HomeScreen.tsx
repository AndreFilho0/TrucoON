import React, { useState } from "react";
import { KeyboardAvoidingView, Platform, ScrollView, Text, TextInput, View } from "react-native";
import { Button } from "../components/Button";
import { ServerPicker } from "../components/ServerPicker";
import { api } from "../services/api";
import { useSession } from "../store/session.store";
import { formatCode } from "../lib/route";
import { reasonText } from "../lib/messages";

type Props = { initialCode: string | null; onEnter: (code: string) => void };

export function HomeScreen({ initialCode, onEnter }: Props) {
  const { player, token, server, login, logout } = useSession();
  const [name, setName] = useState(player?.name ?? "");
  const [code, setCode] = useState(initialCode ? formatCode(initialCode) : "");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const ensureLogin = async () => {
    if (player && token && player.name === name.trim()) return useSession.getState().token!;
    await login(name);
    return useSession.getState().token!;
  };

  const create = async (mode: "1v1" | "2v2") => {
    setBusy(mode);
    setError(null);
    try {
      const t = await ensureLogin();
      const room = await api.createRoom(server, t, mode);
      onEnter(room.code);
    } catch (e: any) {
      setError(reasonText(e.message));
    } finally {
      setBusy(null);
    }
  };

  const join = async () => {
    setBusy("join");
    setError(null);
    try {
      await ensureLogin();
      onEnter(code.replace(/[^A-Za-z0-9]/g, "").toUpperCase());
    } catch (e: any) {
      setError(reasonText(e.message));
    } finally {
      setBusy(null);
    }
  };

  const hasName = name.trim().length > 0;
  const invited = !!initialCode;

  return (
    <KeyboardAvoidingView className="flex-1 bg-felt" behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView contentContainerStyle={{ flexGrow: 1, justifyContent: "center", padding: 24 }}>
        <View className="items-center mb-8">
          <Text className="text-6xl mb-2">🃏</Text>
          <Text className="text-4xl font-extrabold text-gold tracking-tight">TrucoON</Text>
          <Text className="text-white/70 text-center mt-2">
            {invited ? "Você foi chamado para uma mesa!" : "Puxe uma mesa e chame seus amigos."}
          </Text>
        </View>

        <View className="bg-felt-light rounded-3xl p-5 gap-4">
          <View>
            <Text className="text-white/80 mb-2 font-semibold">Seu apelido</Text>
            <TextInput
              value={name}
              onChangeText={setName}
              placeholder="Como te chamam na mesa?"
              placeholderTextColor="#ffffff66"
              maxLength={20}
              className="bg-felt-dark text-white rounded-2xl px-4 py-3.5 text-base"
            />
          </View>

          {invited ? (
            <Button title={`Entrar na mesa ${formatCode(initialCode!)}`} variant="gold" disabled={!hasName} loading={busy === "join"} onPress={join} />
          ) : (
            <>
              <View className="flex-row gap-3">
                <Button title="Mesa 1 x 1" className="flex-1" variant="gold" disabled={!hasName} loading={busy === "1v1"} onPress={() => create("1v1")} />
                <Button title="Mesa 2 x 2" className="flex-1" variant="gold" disabled={!hasName} loading={busy === "2v2"} onPress={() => create("2v2")} />
              </View>

              <View className="flex-row items-center gap-3 my-1">
                <View className="flex-1 h-px bg-white/20" />
                <Text className="text-white/50 text-xs">OU ENTRE COM O CÓDIGO</Text>
                <View className="flex-1 h-px bg-white/20" />
              </View>

              <View className="flex-row gap-3">
                <TextInput
                  value={code}
                  onChangeText={(t) => setCode(formatCode(t))}
                  placeholder="K7QX-29FA"
                  placeholderTextColor="#ffffff55"
                  autoCapitalize="characters"
                  maxLength={9}
                  className="flex-1 bg-felt-dark text-white rounded-2xl px-4 py-3.5 text-base tracking-widest"
                />
                <Button title="Entrar" disabled={!hasName || code.length < 9} loading={busy === "join"} onPress={join} />
              </View>
            </>
          )}

          {error && <Text className="text-red-300 text-center">{error}</Text>}
        </View>

        <View className="mt-6">
          <ServerPicker dark />
          {player && (
            <Text onPress={logout} className="text-white/40 text-xs text-center mt-3">
              jogando como {player.name} · trocar
            </Text>
          )}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
