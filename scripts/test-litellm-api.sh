#!/usr/bin/env bash
# Prova l'API autenticada de LiteLLM amb una clau VIRTUAL (no la mestra).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

BASE_URL="${LITELLM_API_BASE_URL:-http://127.0.0.1:${LITELLM_PORT:-4000}}"
API_KEY="${LITELLM_API_KEY:-}"
MODEL="${1:-}"

if [[ -z "$API_KEY" ]]; then
  echo "ERROR: defineix LITELLM_API_KEY amb una clau virtual (scripts/litellm-create-key.sh)." >&2
  echo "Exemple: LITELLM_API_KEY='sk-...' $0 gpt-oss-120b" >&2
  exit 1
fi

if [[ -z "$MODEL" ]]; then
  echo "Models visibles per a esta clau:"
  curl --fail --silent --show-error \
    "${BASE_URL}/v1/models" \
    -H "Authorization: Bearer ${API_KEY}"
  echo
  echo "Per provar inferència: LITELLM_API_KEY='sk-...' $0 nom:model" >&2
  exit 0
fi

curl --fail --silent --show-error \
  "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"${MODEL}\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"Respon només amb: API LiteLLM correcta\"}]}"
echo
