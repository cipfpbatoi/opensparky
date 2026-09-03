#!/usr/bin/env bash
# Prova un servidor vLLM DIRECTAMENT (sense passar per LiteLLM), útil per
# distingir un problema del model/vLLM d'un problema de LiteLLM. Requereix
# tindre publicat el port de depuració corresponent:
#   docker compose -f compose.yaml -f compose.dev.yaml up -d
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

SERVICE="${1:-}"
if [[ -z "$SERVICE" ]]; then
  echo "Ús: $0 <embeddings|reasoning|coding>" >&2
  exit 1
fi

case "$SERVICE" in
  embeddings)
    PORT="${VLLM_EMBEDDINGS_HOST_PORT:-8001}"
    API_KEY="${VLLM_EMBEDDINGS_API_KEY:-}"
    MODEL="bge-m3"
    ;;
  reasoning)
    PORT="${VLLM_REASONING_HOST_PORT:-8002}"
    API_KEY="${VLLM_REASONING_API_KEY:-}"
    MODEL="gpt-oss-120b"
    ;;
  coding)
    PORT="${VLLM_CODING_HOST_PORT:-8003}"
    API_KEY="${VLLM_CODING_API_KEY:-}"
    MODEL="coding-model"
    ;;
  *)
    echo "ERROR: servei desconegut '${SERVICE}'. Usa embeddings, reasoning o coding." >&2
    exit 1
    ;;
esac

echo "Models servits en http://127.0.0.1:${PORT}:"
curl --fail --silent --show-error \
  "http://127.0.0.1:${PORT}/v1/models" \
  -H "Authorization: Bearer ${API_KEY}"
echo

if [[ "$SERVICE" == "embeddings" ]]; then
  echo
  echo "Prova d'embedding:"
  curl --fail --silent --show-error \
    "http://127.0.0.1:${PORT}/v1/embeddings" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL}\",\"input\":\"prova\"}"
  echo
else
  echo
  echo "Prova de chat completion:"
  curl --fail --silent --show-error \
    "http://127.0.0.1:${PORT}/v1/chat/completions" \
    -H "Authorization: Bearer ${API_KEY}" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${MODEL}\",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"Respon només amb: API vLLM correcta\"}]}"
  echo
fi
