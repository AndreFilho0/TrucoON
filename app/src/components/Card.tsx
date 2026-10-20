import React from "react";
import { Pressable, Text, View } from "react-native";
import { parseCard } from "../lib/cards";

type Props = {
  card?: string | null;
  size?: "sm" | "md" | "lg";
  onPress?: () => void;
  disabled?: boolean;
  highlight?: boolean;
};

const SIZES = {
  sm: { w: 38, h: 54, value: 13, suit: 18 },
  md: { w: 56, h: 80, value: 16, suit: 28 },
  lg: { w: 76, h: 108, value: 20, suit: 38 },
};

export function Card({ card, size = "md", onPress, disabled, highlight }: Props) {
  const s = SIZES[size];

  if (!card) {
    // verso da carta
    return (
      <View
        style={{ width: s.w, height: s.h }}
        className="rounded-lg border-2 border-white bg-teamB items-center justify-center"
      >
        <View style={{ width: s.w - 10, height: s.h - 10 }} className="rounded-md border border-white/50" />
      </View>
    );
  }

  const c = parseCard(card);
  const color = c.red ? "#DC2626" : "#111827";

  return (
    <Pressable
      onPress={onPress}
      disabled={!onPress || disabled}
      style={{ width: s.w, height: s.h }}
      className={`rounded-lg bg-white px-1 py-0.5 justify-between shadow ${
        highlight ? "border-2 border-gold -translate-y-2" : "border border-gray-300"
      } ${disabled ? "opacity-60" : ""}`}
    >
      <Text style={{ color, fontSize: s.value, fontWeight: "800" }}>{c.value}</Text>
      <Text style={{ color, fontSize: s.suit, textAlign: "center", marginTop: -6 }}>{c.symbol}</Text>
      <Text
        numberOfLines={1}
        style={{ fontSize: Math.max(8, s.value - 8), textAlign: "center", color: "#B45309", fontWeight: "700" }}
      >
        {c.manilha ?? " "}
      </Text>
    </Pressable>
  );
}
