import { Platform } from "react-native";

// Servidor (peer) padrão:
// 1. ?s=<url> no link de convite;
// 2. EXPO_PUBLIC_SERVER (ex.: http://192.168.0.10:4001);
// 3. quando o app é servido pelo próprio peer, a mesma origem;
// 4. senão, a porta 4001 do mesmo host (dev com Expo na 8081).
export function defaultServer(): string {
  if (Platform.OS === "web" && typeof window !== "undefined") {
    const s = new URLSearchParams(window.location.search).get("s");
    if (s) return s;
    if (process.env.EXPO_PUBLIC_SERVER) return process.env.EXPO_PUBLIC_SERVER;
    const { protocol, hostname, port } = window.location;
    if (port && port !== "8081" && port !== "19006") return `${protocol}//${hostname}:${port}`;
    return `${protocol}//${hostname}:4001`;
  }
  return process.env.EXPO_PUBLIC_SERVER ?? "http://localhost:4001";
}
