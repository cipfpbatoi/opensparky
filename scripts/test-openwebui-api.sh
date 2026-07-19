#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

BASE_URL="${OPENWEBUI_API_BASE_URL:-http://127.0.0.1:${OPEN_WEBUI_PORT:-3000}}"
API_KEY="${OPENWEBUI_API_KEY:-}"
MODEL="${1:-}"

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: defineix OPENWEBUI_API_KEY amb una clau creada per l'usuari." >&2
  echo "Exemple: OPENWEBUI_API_KEY='sk-...' $0 nom:model" >&2
  exit 1
fi

if [[ -z "$MODEL" ]]; then
  echo "Models visibles per a l'usuari:"
  curl --fail --silent --show-error \
    "${BASE_URL}/api/models" \
    -H "Authorization: Bearer ${API_KEY}"
  echo
  echo "Per provar inferència: OPENWEBUI_API_KEY='sk-...' $0 nom:model" >&2
  exit 0
fi

curl --fail --silent --show-error \
  "${BASE_URL}/api/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"${MODEL}\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"Respon només amb: API Open WebUI correcta\"}]}"
echo
