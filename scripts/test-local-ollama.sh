#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

PORT="${OLLAMA_PORT:-11434}"
MODEL="${1:-}"

if [[ -z "$MODEL" ]]; then
  echo "Models disponibles en http://127.0.0.1:${PORT}:"
  curl --fail --silent --show-error "http://127.0.0.1:${PORT}/api/tags"
  echo
  echo "Per provar inferència: $0 nom:model" >&2
  exit 0
fi

curl --fail --silent --show-error \
  "http://127.0.0.1:${PORT}/api/chat" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"${MODEL}\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"Respon només amb: API Ollama correcta\"}]}"
echo
