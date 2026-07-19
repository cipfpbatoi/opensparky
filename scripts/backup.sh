#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${1:-backups/${STAMP}}"
mkdir -p "$DEST"

restart_services() {
  docker compose start postgres ollama open-webui >/dev/null 2>&1 || true
}
trap restart_services EXIT

echo "Parant serveis per obtindre una còpia consistent..."
docker compose stop open-webui ollama postgres

backup_one() {
  local logical="$1" volume="$2"
  echo "Copiant ${volume} com ${logical}.tar.gz..."
  docker run --rm \
    -v "${volume}:/source:ro" \
    -v "$(pwd)/${DEST}:/backup" \
    alpine:3.22 \
    sh -c "cd /source && tar -czf /backup/${logical}.tar.gz ."
}

backup_one ollama_data dgx_ollama_data
backup_one openwebui_data dgx_openwebui_data
backup_one postgres_data dgx_postgres_data

(
  cd "$DEST"
  sha256sum ./*.tar.gz > SHA256SUMS
)

echo "Còpia creada en ${DEST}"
