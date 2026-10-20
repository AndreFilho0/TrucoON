#!/usr/bin/env bash
# Sobe o nó de controle (GroupManager + Verifier) e N peers nesta máquina,
# cada um num processo/nó Erlang separado, em segundo plano.
#
#   scripts/up.sh [N]                      # 3 peers por padrão
#   ORDERING=none scripts/up.sh 4      # escolhe o protocolo
#   CONTROL=socket scripts/up.sh           # controle por socket TCP (Parte 1a)
#   LOSS=0.1 DELAY_MAX=80 scripts/up.sh    # perda/atraso em todos os peers
#   REMOTE_DELAY=150 scripts/up.sh         # o último peer vira "outra região"
#
# Logs em tmp/run/*.log. Para parar: scripts/down.sh
set -euo pipefail
cd "$(dirname "$0")/.."

N="${1:-3}"
export ORDERING="${ORDERING:-none}"
export CONTROL="${CONTROL:-rpc}"
export GROUP_SIZE="$N"
COOKIE="${COOKIE:-trucoon}"
HOST="${PEER_HOST:-127.0.0.1}"
# os peers precisam achar o nó de controle no mesmo endereço em que ele sobe
export CONTROL_NODE="${CONTROL_NODE:-control@$HOST}"
export CONTROL_HOST="${CONTROL_HOST:-$HOST}"
RUN=tmp/run
mkdir -p "$RUN"

if [ -f "$RUN/pids" ]; then
  echo "Já existe um grupo rodando (tmp/run/pids). Rode scripts/down.sh antes." >&2
  exit 1
fi

mix compile >/dev/null
rm -f "$RUN"/*.log

# Nó de controle: sempre com nome Erlang, para podermos abrir o console
# remoto (scripts/console.sh). No modo socket os peers NÃO usam
# distribuição Erlang: falam com ele só por TCP.
ROLE=control elixir --name "control@$HOST" --cookie "$COOKIE" -S mix run --no-halt \
  >"$RUN/control.log" 2>&1 &
echo $! >>"$RUN/pids"
sleep 1

for i in $(seq 1 "$N"); do
  delay_min="${DELAY_MIN:-0}"
  delay_max="${DELAY_MAX:-0}"
  region="regiao-$i"
  if [ -n "${REMOTE_DELAY:-}" ] && [ "$i" -eq "$N" ]; then
    delay_min="$REMOTE_DELAY"; delay_max="$((REMOTE_DELAY * 2))"; region="remota"
  fi

  if [ "$CONTROL" = "rpc" ]; then
    dist=(--name "peer$i@$HOST" --cookie "$COOKIE")
  else
    dist=()
  fi

  ROLE=peer REGION="$region" PEER_HOST="$HOST" \
    UDP_PORT=$((6788 + i)) CTRL_PORT=$((5690 + i)) PORT=$((4000 + i)) \
    DELAY_MIN="$delay_min" DELAY_MAX="$delay_max" \
    elixir ${dist[@]+"${dist[@]}"} -S mix phx.server >"$RUN/peer$i.log" 2>&1 &
  echo $! >>"$RUN/pids"
done

echo "Grupo subindo: controle + $N peers (ORDERING=$ORDERING, CONTROL=$CONTROL)"
for i in $(seq 1 "$N"); do echo "  peer $i → http://$HOST:$((4000 + i))"; done
echo "Console do Verifier: scripts/console.sh   |   parar: scripts/down.sh"
