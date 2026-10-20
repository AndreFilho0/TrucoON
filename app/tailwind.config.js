/** @type {import('tailwindcss').Config} */
// Base do melivra_mobile (cores por variáveis CSS, modo escuro por classe)
// + cores da mesa de truco.
module.exports = {
  presets: [require("nativewind/preset")],
  darkMode: "class",
  content: ["./App.{js,jsx,ts,tsx}", "./src/**/*.{js,jsx,ts,tsx}"],
  theme: {
    extend: {
      colors: {
        primary: "rgb(var(--color-primary) / <alpha-value>)",
        secondary: "#FF6584",
        background: "rgb(var(--color-background) / <alpha-value>)",
        surface: "rgb(var(--color-surface) / <alpha-value>)",
        border: "rgb(var(--color-border) / <alpha-value>)",
        text: {
          primary: "rgb(var(--color-text-primary) / <alpha-value>)",
          secondary: "rgb(var(--color-text-secondary) / <alpha-value>)",
        },
        felt: { DEFAULT: "#0B3D2E", light: "#145A43", dark: "#062A1F" },
        gold: "#F2C14E",
        teamA: "#3B82F6",
        teamB: "#EF4444",
      },
    },
  },
  plugins: [],
};
