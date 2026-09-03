#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${1:-backups/${STAMP}}"
mkdir -p "$DEST"

# Els vLLM només guarden en el seu volum una caché de models descarregables
# de nou des de Hugging Face: no és dada irrecuperable i no es copia ací per
# no inflar la còpia amb centenars de gigabytes regenerables.
restart_services() {
  docker compose start postgres open-webui >/dev/null 2>&1 || true
}
trap restart_services EXIT

echo "Parant serveis per obtindre una còpia consistent..."
docker compose stop open-webui postgres

backup_one() {
  local logical="$1" volume="$2"
  echo "Copiant ${volume} com ${logical}.tar.gz..."
  docker run --rm \
    -v "${volume}:/source:ro" \
    -v "$(pwd)/${DEST}:/backup" \
    alpine:3.22 \
    sh -c "cd /source && tar -czf /backup/${logical}.tar.gz ."
}

backup_one openwebui_data dgx_openwebui_data
backup_one postgres_data dgx_postgres_data

(
  cd "$DEST"
  sha256sum ./*.tar.gz > SHA256SUMS
)

echo "Còpia creada en ${DEST}"
