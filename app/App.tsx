import "./global.css";
import React, { useEffect, useState } from "react";
import { Platform, Text, View, useColorScheme } from "react-native";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import { StatusBar } from "expo-status-bar";
import { HomeScreen } from "./src/screens/HomeScreen";
import { LobbyScreen } from "./src/screens/LobbyScreen";
import { GameScreen } from "./src/screens/GameScreen";
import { Button } from "./src/components/Button";
import { useThemeStore } from "./src/store/theme.store";
import { useSession } from "./src/store/session.store";
import { useRoom } from "./src/store/room.store";
import { lightThemeVars, darkThemeVars } from "./src/theme";
import { codeFromUrl, goTo } from "./src/lib/route";
import { reasonText } from "./src/lib/messages";

export default function App() {
  const systemColorScheme = useColorScheme();
  const { isDark, setIsDark } = useThemeStore();
  const { player, token, server } = useSession();
  const { view, error, join, leave } = useRoom();
  const [code, setCode] = useState<string | null>(codeFromUrl());
  const [entered, setEntered] = useState(false);

  useEffect(() => {
    setIsDark(systemColorScheme === "dark");
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // voltar/avançar do navegador
  useEffect(() => {
    if (Platform.OS !== "web") return;
    const onPop = () => {
      setCode(codeFromUrl());
      setEntered(false);
      leave();
    };
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  // conecta no canal da mesa quando há código + identidade
  useEffect(() => {
    if (code && entered && token) join(server, token, code);
  }, [code, entered, token, server]);

  // quem já tem sessão e abriu um link entra direto
  useEffect(() => {
    if (code && player && token) setEntered(true);
  }, []);

  const enter = (c: string) => {
    goTo(`/m/${c}`);
    setCode(c);
    setEntered(true);
  };

  const exit = () => {
    leave();
    goTo("/");
    setCode(null);
    setEntered(false);
  };

  let screen: React.ReactNode;
  if (!code || !entered || !token) {
    screen = <HomeScreen initialCode={code} onEnter={enter} />;
  } else if (error) {
    screen = (
      <View className="flex-1 bg-felt items-center justify-center p-8 gap-4">
        <Text className="text-white text-lg text-center">{reasonText(error)}</Text>
        <Button title="Voltar ao início" variant="gold" onPress={exit} />
      </View>
    );
  } else if (!view) {
    screen = (
      <View className="flex-1 bg-felt items-center justify-center">
        <Text className="text-white/70">Entrando na mesa…</Text>
      </View>
    );
  } else if (view.status === "lobby") {
    screen = <LobbyScreen view={view} onExit={exit} />;
  } else {
    screen = <GameScreen view={view} onExit={exit} />;
  }

  return (
    <SafeAreaProvider>
      <View className={`flex-1 bg-felt-dark ${isDark ? "dark" : ""}`} style={isDark ? darkThemeVars : lightThemeVars}>
        <StatusBar style="light" />
        {/* mobile-first: no desktop a mesa fica numa coluna de celular */}
        <SafeAreaView style={{ flex: 1, width: "100%", maxWidth: 480, alignSelf: "center" }}>{screen}</SafeAreaView>
      </View>
    </SafeAreaProvider>
  );
}
