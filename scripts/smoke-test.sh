#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

set -a
# shellcheck disable=SC1091
source .env
set +a

OPEN_WEBUI_PORT="${OPEN_WEBUI_PORT:-3000}"
LITELLM_PORT="${LITELLM_PORT:-4000}"

echo "Estat dels contenidors:"
docker compose ps

echo
echo "Salut de LiteLLM:"
curl --fail --silent --show-error "http://127.0.0.1:${LITELLM_PORT}/health/liveliness"
echo

echo
echo "Salut d'Open WebUI:"
curl --fail --silent --show-error "http://127.0.0.1:${OPEN_WEBUI_PORT}/health"
echo
