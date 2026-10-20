#!/usr/bin/env bash
# Roda o mesmo experimento em cada modo de ordenação e imprime um resumo.
#   scripts/measure.sh [N_PEERS] [MSGS]      (perda/atraso via LOSS, DELAY_MAX)
set -uo pipefail
cd "$(dirname "$0")/.."
N="${1:-4}"; MSGS="${2:-30}"
for mode in none fifo total sequencer; do
  ORDERING=$mode scripts/up.sh "$N" >/dev/null
  sleep 12
  echo "=== ORDERING=$mode ==="
  scripts/run.sh "r = V.bench($MSGS, quiet: true)
    race = S.seat_race(rooms: 8, quiet: true)
    %{
      perdidas: r.per_peer |> Map.values() |> Enum.map(& &1.missing) |> Enum.sum(),
      violacoes_fifo: r.per_peer |> Map.values() |> Enum.map(& &1.fifo_violations) |> Enum.sum(),
      rodadas_fora_de_ordem: \"#{r.unordered_rounds}/#{r.positions}\",
      mesma_sequencia: r.identical,
      msgs_protocolo_por_multicast: r.cost.protocol_per_multicast,
      datagramas_por_multicast: r.cost.udp_per_multicast,
      retransmissoes: r.cost.retransmissions,
      tempo_ms: r.elapsed_ms,
      mesas_divergentes_disputa_cadeiras: \"#{length(race.divergent_rooms)}/#{race.rooms}\"
    }" 2>&1 | sed -n '/resultado/,$p'
  scripts/down.sh >/dev/null
  sleep 2
done
