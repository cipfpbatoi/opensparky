#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

[[ -f .env ]] || { echo "ERROR: falta .env. Executa: cp .env.example .env" >&2; exit 1; }
command -v docker >/dev/null || { echo "ERROR: falta Docker" >&2; exit 1; }
docker compose version >/dev/null || { echo "ERROR: falta Docker Compose v2" >&2; exit 1; }

printf 'Arquitectura: '
uname -m
if [[ "$(uname -m)" != "aarch64" ]]; then
  echo "AVÍS: este projecte està orientat a DGX Spark ARM64." >&2
fi

echo "Comprovant accés CUDA des d'un contenidor..."
docker run --rm --gpus=all nvcr.io/nvidia/cuda:13.0.1-base-ubuntu24.04 nvidia-smi

echo "Validant Compose..."
docker compose --env-file .env config --quiet

echo "Comprovant que els ports locals estan lliures..."
set -a
# shellcheck disable=SC1091
source .env
set +a
for port in "${OLLAMA_PORT:-11434}" "${OPEN_WEBUI_PORT:-3000}"; do
  if ss -ltnH "sport = :${port}" | grep -q .; then
    echo "AVÍS: el port ${port} ja està ocupat." >&2
  fi
done

echo "Preflight correcte."
