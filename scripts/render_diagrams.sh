#!/usr/bin/env bash
# Gera docs/diagramas/*.svg e *.png a partir dos fontes Mermaid (*.mmd).
# Usa o mermaid-cli via npx; aponte CHROME para um Chrome/Chromium local se o
# puppeteer não conseguir baixar o seu.
#   scripts/render_diagrams.sh
set -euo pipefail
cd "$(dirname "$0")/../docs/diagramas"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
cfg=$(mktemp)
if [ -x "$CHROME" ]; then
  printf '{"executablePath":"%s","args":["--no-sandbox"]}' "$CHROME" >"$cfg"
else
  echo '{"args":["--no-sandbox"]}' >"$cfg"
fi
for f in *.mmd; do
  base="${f%.mmd}"
  npx -y @mermaid-js/mermaid-cli@11.4.2 -q -i "$f" -o "$base.svg" -p "$cfg" -b white
  npx -y @mermaid-js/mermaid-cli@11.4.2 -q -i "$f" -o "$base.png" -p "$cfg" -b white -s 3
  echo "ok $base"
done
rm -f "$cfg"
