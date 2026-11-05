// Cartas no formato "<valor>_<naipe>" (ex.: "3_paus"), igual ao backend.
export const SUITS: Record<string, { symbol: string; red: boolean }> = {
  ouros: { symbol: "♦", red: true },
  espadas: { symbol: "♠", red: false },
  copas: { symbol: "♥", red: true },
  paus: { symbol: "♣", red: false },
};

// Manilhas fixas do truco mineiro, da mais fraca à mais forte.
export const MANILHAS: Record<string, string> = {
  "7_ouros": "Pica-fumo",
  A_espadas: "Espadilha",
  "7_copas": "Sete-copas",
  "4_paus": "Zap",
};

export function parseCard(card: string) {
  const [value, suit] = card.split("_");
  return { value, suit, ...(SUITS[suit] ?? { symbol: "?", red: false }), manilha: MANILHAS[card] };
}

export const BET_NAME: Record<number, string> = { 1: "", 3: "TRUCO", 6: "SEIS", 9: "NOVE", 12: "DOZE" };
export const NEXT_BET: Record<number, number> = { 1: 3, 3: 6, 6: 9, 9: 12 };
