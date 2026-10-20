#!/usr/bin/env bash
# Gera o frontend (Expo Web) e copia para priv/static: cada peer passa a
# servir o app em http://<peer>/ (e os links /m/<código> funcionam).
set -euo pipefail
cd "$(dirname "$0")/../app"
[ -d node_modules ] || npm install
npx expo export --platform web --output-dir dist
cd ..
rm -rf priv/static
mkdir -p priv/static
cp -R app/dist/. priv/static/
echo "Frontend copiado para priv/static/"
