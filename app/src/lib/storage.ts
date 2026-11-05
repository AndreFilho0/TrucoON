// localStorage com fallback (aba anônima, preview, nativo): nunca quebra o app.
const memory: Record<string, string> = {};

export const storage = {
  get(key: string): string | null {
    try {
      if (typeof localStorage !== "undefined") return localStorage.getItem(key);
    } catch {}
    return memory[key] ?? null;
  },
  set(key: string, value: string) {
    try {
      if (typeof localStorage !== "undefined") return localStorage.setItem(key, value);
    } catch {}
    memory[key] = value;
  },
  remove(key: string) {
    try {
      if (typeof localStorage !== "undefined") return localStorage.removeItem(key);
    } catch {}
    delete memory[key];
  },
};
