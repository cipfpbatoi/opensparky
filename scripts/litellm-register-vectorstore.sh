#!/usr/bin/env bash
# Crea un magatzem de vectors nou al connector litellm-pgvector i el
# registra en LiteLLM. Fa els dos passos perquè l'ID del magatzem el
# genera SEMPRE el connector (UUID, no es pot triar): cal crear-lo ahí
# primer i usar eixe mateix UUID en registrar-lo a LiteLLM.
#
# El registre en LiteLLM es fa via l'API de gestió (POST /vector_store/new)
# en lloc de config.yaml: carregar "vector_store_registry" des del fitxer
# està trencat en litellm-database:main-stable (BerriAI/litellm#25947,
# comprovat 2026-09-03). Idempotent a LiteLLM (actualitza si ja existeix);
# NO ho és al connector (cada execució crea un magatzem NOU, buit).
#
# Requereix litellm i litellm-pgvector ja alçats.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${LITELLM_MASTER_KEY:?Defineix LITELLM_MASTER_KEY en el fitxer .env}"
: "${LITELLM_PGVECTOR_SERVER_API_KEY:?Defineix LITELLM_PGVECTOR_SERVER_API_KEY en el fitxer .env}"

LITELLM_PORT="${LITELLM_PORT:-4000}"
PGVECTOR_PORT="${LITELLM_PGVECTOR_PORT:-8010}"
STORE_NAME="${1:-pgvector-bge-m3}"

echo "1/2: creant el magatzem '${STORE_NAME}' en litellm-pgvector..." >&2
CREATE_RESPONSE="$(curl --fail --silent --show-error \
  "http://127.0.0.1:${PGVECTOR_PORT}/v1/vector_stores" \
  -H "Authorization: Bearer ${LITELLM_PGVECTOR_SERVER_API_KEY}" \
  -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"name": sys.argv[1]}))' "$STORE_NAME")")"

VECTOR_STORE_ID="$(echo "$CREATE_RESPONSE" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
echo "   ID assignat: ${VECTOR_STORE_ID}" >&2

echo "2/2: registrant-lo en LiteLLM..." >&2
PAYLOAD="$(python3 - "$VECTOR_STORE_ID" "$STORE_NAME" "$LITELLM_PGVECTOR_SERVER_API_KEY" <<'PY'
import json
import sys

vector_store_id, store_name, server_api_key = sys.argv[1:4]
body = {
    "vector_store_id": vector_store_id,
    "custom_llm_provider": "pg_vector",
    "vector_store_name": store_name,
    "vector_store_description": "PostgreSQL+pgvector local, embeddings amb bge-m3 via vLLM",
    "litellm_params": {
        "api_base": "http://litellm-pgvector:8000",
        "api_key": server_api_key,
        "embedding_model": "bge-m3",
    },
}
print(json.dumps(body))
PY
)"

curl --fail --silent --show-error \
  "http://127.0.0.1:${LITELLM_PORT}/vector_store/new" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d "${PAYLOAD}"
echo
echo "Fet. vector_store_id per a /v1/vector_stores/{id}/search: ${VECTOR_STORE_ID}" >&2
