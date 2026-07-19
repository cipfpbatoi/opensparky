#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

set -a
# shellcheck disable=SC1091
source .env
set +a

OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-3000}"

echo "Estat dels contenidors:"
docker compose ps

echo
echo "Ollama local:"
curl --fail --silent --show-error "http://127.0.0.1:${OLLAMA_PORT}/api/tags" | head -c 1000
echo

echo
echo "Salut d'Open WebUI:"
curl --fail --silent --show-error "http://127.0.0.1:${OPEN_WEBUI_PORT}/health"
echo
