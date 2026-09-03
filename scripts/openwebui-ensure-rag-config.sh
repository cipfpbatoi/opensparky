#!/usr/bin/env bash
# Comprova (i corregeix si cal) que la RAG d'Open WebUI use bge-m3 via
# LiteLLM, no el motor local per defecte. Idempotent: no fa res si ja és
# correcte.
#
# Necessari perquè és configuració "PersistentConfig", guardada a la taula
# 'config' de la base de dades des del primer arrancada — les variables
# d'entorn de compose.yaml (RAG_EMBEDDING_ENGINE, etc.) NOMÉS s'apliquen
# quan encara no hi ha cap valor guardat. Comprovat en viu que una
# ACTUALITZACIÓ d'Open WebUI pot "re-sembrar" estes claus als valors de
# fàbrica sense avís (v0.11.0 -> v0.11.3, 2026-09-03: log "Seeded 4 new
# config defaults") — executa este script després de cada actualització,
# a més d'en una migració des d'una instància ja existent (vegeu README.md).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${OPENWEBUI_LITELLM_API_KEY:?Defineix OPENWEBUI_LITELLM_API_KEY en el fitxer .env}"

CURRENT="$(docker compose exec -T postgres psql -U "${POSTGRES_USER:-openwebui}" -d "${POSTGRES_DB:-openwebui}" -t -A \
  -c "SELECT value FROM config WHERE key = 'rag.embedding_engine';")"

if [[ "$CURRENT" == '"openai"' ]]; then
  echo "rag.embedding_engine ja és \"openai\" (bge-m3 via LiteLLM). Res a fer."
  exit 0
fi

echo "rag.embedding_engine és ${CURRENT:-<buit>}, no \"openai\": corregint..."
docker compose exec -T postgres psql -U "${POSTGRES_USER:-openwebui}" -d "${POSTGRES_DB:-openwebui}" -v ON_ERROR_STOP=1 <<EOSQL
UPDATE config SET value = '"openai"'::json WHERE key = 'rag.embedding_engine';
UPDATE config SET value = '"bge-m3"'::json WHERE key = 'rag.embedding_model';
UPDATE config SET value = '"http://litellm:4000/v1"'::json WHERE key = 'rag.openai.api_base_url';
UPDATE config SET value = '"${OPENWEBUI_LITELLM_API_KEY}"'::json WHERE key = 'rag.openai.api_key';
EOSQL

docker compose restart open-webui
echo "Corregit i open-webui reiniciat."
