#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

BACKUP_DIR="${1:-}"
if [[ -z "$BACKUP_DIR" || ! -d "$BACKUP_DIR" ]]; then
  echo "Ús: $0 backups/AAAAMMDD-HHMMSS" >&2
  exit 1
fi

(
  cd "$BACKUP_DIR"
  sha256sum -c SHA256SUMS
)

read -r -p "Açò substituirà totes les dades. Escriu RESTAURA: " CONFIRM
[[ "$CONFIRM" == "RESTAURA" ]] || { echo "Cancel·lat"; exit 1; }

docker compose down

restore_one() {
  local logical="$1" volume="$2"
  docker volume inspect "$volume" >/dev/null 2>&1 || docker volume create "$volume" >/dev/null
  docker run --rm \
    -v "${volume}:/target" \
    -v "$(pwd)/${BACKUP_DIR}:/backup:ro" \
    alpine:3.22 \
    sh -c "rm -rf /target/* /target/.[!.]* /target/..?* 2>/dev/null || true; tar -xzf /backup/${logical}.tar.gz -C /target"
}

restore_one ollama_data dgx_ollama_data
restore_one openwebui_data dgx_openwebui_data
restore_one postgres_data dgx_postgres_data

docker compose up -d
echo "Restauració completada. Executa scripts/smoke-test.sh"
