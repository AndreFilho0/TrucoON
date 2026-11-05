import { create } from "zustand";
import { Socket, Channel } from "phoenix";
import type { RoomView, TrucoEvent } from "../types";

// Conexão WebSocket com o peer e o canal da mesa atual.
// Toda ação vira um comando replicado no servidor: a resposta só chega
// quando a réplica do peer aplicou o comando na ordem do protocolo.
type RoomStore = {
  socket: Socket | null;
  socketKey: string | null;
  channel: Channel | null;
  code: string | null;
  view: RoomView | null;
  feed: TrucoEvent[];
  error: string | null;
  connected: boolean;
  join: (server: string, token: string, code: string) => void;
  leave: () => void;
  push: (event: string, payload?: object) => Promise<void>;
};

export const useRoom = create<RoomStore>((set, get) => ({
  socket: null,
  socketKey: null,
  channel: null,
  code: null,
  view: null,
  feed: [],
  error: null,
  connected: false,

  join: (server, token, code) => {
    get().channel?.leave();
    let { socket, socketKey } = get();
    const key = `${server}|${token}`;

    if (!socket || socketKey !== key) {
      socket?.disconnect();
      socket = new Socket(server.replace(/^http/, "ws") + "/socket", { params: { token } });
      socket.onOpen(() => set({ connected: true }));
      socket.onClose(() => set({ connected: false }));
      socket.connect();
      socketKey = key;
    }

    const channel = socket.channel(`room:${code}`, {});
    channel.on("state", ({ view, events }: { view: RoomView; events: TrucoEvent[] }) => {
      set((s) => ({ view, feed: [...events, ...s.feed].slice(0, 30), error: null }));
    });
    channel.on("closed", () => set({ view: null, error: "Mesa encerrada" }));

    channel
      .join(15000)
      .receive("ok", () => set({ error: null }))
      .receive("error", (r: { reason?: string }) => {
        set({ error: r?.reason ?? "erro ao entrar" });
        channel.leave();
      })
      .receive("timeout", () => set({ error: "servidor não respondeu" }));

    set({ socket, socketKey, channel, code, view: null, feed: [], error: null });
  },

  leave: () => {
    get().channel?.leave();
    set({ channel: null, code: null, view: null, feed: [] });
  },

  push: (event, payload = {}) =>
    new Promise((resolve, reject) => {
      const ch = get().channel;
      if (!ch) return reject(new Error("sem mesa"));
      ch.push(event, payload, 15000)
        .receive("ok", () => resolve())
        .receive("error", (r: { reason?: string }) => reject(new Error(r?.reason ?? "erro")))
        .receive("timeout", () => reject(new Error("timeout")));
    }),
}));
