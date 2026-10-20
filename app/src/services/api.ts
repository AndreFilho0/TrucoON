import type { PeerInfo, Player } from "../types";

async function request<T>(server: string, path: string, init: RequestInit = {}, token?: string): Promise<T> {
  const res = await fetch(`${server}/api${path}`, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(init.headers ?? {}),
    },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error ?? `HTTP ${res.status}`);
  return body as T;
}

export const api = {
  session: (server: string, name: string) =>
    request<{ player: Player; token: string }>(server, "/session", { method: "POST", body: JSON.stringify({ name }) }),
  info: (server: string) => request<PeerInfo>(server, "/info"),
  debug: (server: string) => request<any>(server, "/debug"),
  createRoom: (server: string, token: string, mode: "1v1" | "2v2") =>
    request<{ code: string; display: string }>(server, "/rooms", { method: "POST", body: JSON.stringify({ mode }) }, token),
  room: (server: string, code: string) => request<any>(server, `/rooms/${code}`),
};
