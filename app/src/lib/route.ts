import { Platform } from "react-native";

// Rotas mínimas do web: "/" (início) e "/m/<código>" (mesa).
export function codeFromUrl(): string | null {
  if (Platform.OS !== "web" || typeof window === "undefined") return null;
  const m = window.location.pathname.match(/^\/m\/([A-Za-z0-9-]+)/);
  return m ? m[1].toUpperCase() : null;
}

export function goTo(path: string) {
  if (Platform.OS !== "web" || typeof window === "undefined") return;
  const search = window.location.search;
  window.history.pushState({}, "", path + search);
}

export function inviteLink(display: string, server: string): string {
  const origin =
    Platform.OS === "web" && typeof window !== "undefined" ? window.location.origin : server;
  const url = new URL(`/m/${display}`, origin);
  if (origin !== server) url.searchParams.set("s", server);
  return url.toString();
}

export function formatCode(code: string): string {
  const c = code.replace(/[^A-Z0-9]/gi, "").toUpperCase();
  return c.length === 8 ? `${c.slice(0, 4)}-${c.slice(4)}` : c;
}
