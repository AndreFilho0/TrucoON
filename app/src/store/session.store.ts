import { create } from "zustand";
import { api } from "../services/api";
import { defaultServer } from "../config";
import { storage } from "../lib/storage";
import type { PeerInfo, Player } from "../types";

// Identidade de convidado: apelido + token assinado pelo servidor.
// O token vale em qualquer peer (mesmo segredo), então dá para trocar de
// servidor/região sem perder a identidade.
type SessionStore = {
  server: string;
  player: Player | null;
  token: string | null;
  info: PeerInfo | null;
  setServer: (url: string) => void;
  loadInfo: () => Promise<void>;
  login: (name: string) => Promise<void>;
  logout: () => void;
};

const saved = (() => {
  try {
    return JSON.parse(storage.get("trucoon.session") ?? "null");
  } catch {
    return null;
  }
})();

export const useSession = create<SessionStore>((set, get) => ({
  server: defaultServer(),
  player: saved?.player ?? null,
  token: saved?.token ?? null,
  info: null,

  setServer: (url) => {
    set({ server: url.replace(/\/$/, ""), info: null });
    get().loadInfo();
  },

  loadInfo: async () => {
    try {
      set({ info: await api.info(get().server) });
    } catch {
      set({ info: null });
    }
  },

  login: async (name) => {
    const { player, token } = await api.session(get().server, name);
    storage.set("trucoon.session", JSON.stringify({ player, token }));
    set({ player, token });
  },

  logout: () => {
    storage.remove("trucoon.session");
    set({ player: null, token: null });
  },
}));
