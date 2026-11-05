#!/usr/bin/env bash
# Executa uma expressão Elixir no nó de controle e imprime o resultado. Ex.:
#   scripts/run.sh 'V.bench(30)'
#   scripts/run.sh 'S.seat_race(rooms: 10)'
cd "$(dirname "$0")/.."
HOST="${PEER_HOST:-127.0.0.1}"
export TRUCO_EXPR="alias TrucoOn.Control.Verifier, as: V; alias TrucoOn.Control.Scenario, as: S
${1:?expressão}"
export TRUCO_CONTROL="control@$HOST"
exec elixir --name "run$$@$HOST" --cookie "${COOKIE:-trucoon}" -e '
  node = String.to_atom(System.fetch_env!("TRUCO_CONTROL"))
  true = Node.connect(node)
  {result, _} = :erpc.call(node, Code, :eval_string, [System.fetch_env!("TRUCO_EXPR")], :infinity)
  IO.inspect(result, label: "resultado", limit: :infinity, pretty: true)
'
