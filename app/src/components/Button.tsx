import React from "react";
import { Pressable, Text, ActivityIndicator } from "react-native";

type Props = {
  title: string;
  onPress?: () => void;
  variant?: "primary" | "gold" | "ghost" | "danger" | "success";
  disabled?: boolean;
  loading?: boolean;
  className?: string;
};

const VARIANTS = {
  primary: "bg-primary",
  gold: "bg-gold",
  ghost: "bg-transparent border border-white/40",
  danger: "bg-teamB",
  success: "bg-emerald-500",
};

export function Button({ title, onPress, variant = "primary", disabled, loading, className = "" }: Props) {
  const text = variant === "gold" ? "text-felt-dark" : "text-white";
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled || loading}
      className={`rounded-2xl px-5 py-3.5 items-center justify-center active:opacity-80 ${VARIANTS[variant]} ${
        disabled ? "opacity-40" : ""
      } ${className}`}
    >
      {loading ? (
        <ActivityIndicator color="white" />
      ) : (
        <Text className={`font-bold text-base tracking-wide ${text}`}>{title}</Text>
      )}
    </Pressable>
  );
}
