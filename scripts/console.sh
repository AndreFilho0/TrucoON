#!/usr/bin/env bash
# Abre um IEx conectado ao nó de controle. Atalhos:
#   V.bench(50)   V.replicas()   V.stats()   V.message_cost()   V.faults(0.1, 0, 80)
#   S.seat_race(rooms: 10)   S.games(rooms: 3, duration_ms: 20_000)
cd "$(dirname "$0")/.."
exec iex --name "console$$@${PEER_HOST:-127.0.0.1}" --cookie "${COOKIE:-trucoon}" \
  --remsh "control@${PEER_HOST:-127.0.0.1}"
