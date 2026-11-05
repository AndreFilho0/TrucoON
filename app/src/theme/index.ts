// Tema herdado do melivra_mobile (variáveis CSS do NativeWind).
import { vars } from "nativewind";

export const lightThemeVars = vars({
  "--color-primary": "59 130 246",
  "--color-background": "243 244 246",
  "--color-surface": "255 255 255",
  "--color-text-primary": "31 41 55",
  "--color-text-secondary": "107 114 128",
  "--color-border": "229 231 235",
});

export const darkThemeVars = vars({
  "--color-primary": "96 165 250",
  "--color-background": "17 24 39",
  "--color-surface": "31 41 55",
  "--color-text-primary": "249 250 251",
  "--color-text-secondary": "156 163 175",
  "--color-border": "55 65 81",
});

export const TEAM_COLOR: Record<string, string> = { a: "#3B82F6", b: "#EF4444" };
