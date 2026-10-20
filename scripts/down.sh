#!/usr/bin/env bash
# Para tudo que o scripts/up.sh subiu.
cd "$(dirname "$0")/.."
if [ -f tmp/run/pids ]; then
  while read -r pid; do kill "$pid" 2>/dev/null || true; done <tmp/run/pids
  rm -f tmp/run/pids
  echo "Grupo parado."
else
  echo "Nada rodando."
fi
