import { create } from "zustand";

type ThemeStore = {
  isDark: boolean;
  setIsDark: (isDark: boolean) => void;
  toggleTheme: () => void;
};

export const useThemeStore = create<ThemeStore>((set, get) => ({
  isDark: false,
  setIsDark: (isDark) => set({ isDark }),
  toggleTheme: () => set({ isDark: !get().isDark }),
}));
