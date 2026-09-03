#!/usr/bin/env bash
# Crea (o amplia) un usuari i una clau virtual de LiteLLM. Fa servir sempre
# la clau MESTRA i el port en loopback: mai exposes esta operació via Caddy.
#
# Ús: ./scripts/litellm-create-key.sh <user_id> [pressupost_usd] [model1,model2,...]
#
# Exemples:
#   ./scripts/litellm-create-key.sh openwebui-service 0 bge-m3,gpt-oss-120b
#   ./scripts/litellm-create-key.sh professorat@cipfpbatoi.lan 20
#   ./scripts/litellm-create-key.sh alumnat-grup1 5 gpt-oss-120b
#
# Sense llista de models, la clau té accés a tots els models de model_list.
# Sense pressupost (o 0), la clau no té límit de despesa.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${LITELLM_MASTER_KEY:?Defineix LITELLM_MASTER_KEY en el fitxer .env}"

USER_ID="${1:-}"
MAX_BUDGET="${2:-0}"
MODELS="${3:-}"
PORT="${LITELLM_PORT:-4000}"

if [[ -z "$USER_ID" ]]; then
  echo "Ús: $0 <user_id> [pressupost_usd] [model1,model2,...]" >&2
  exit 1
fi

PAYLOAD="$(python3 - "$USER_ID" "$MAX_BUDGET" "$MODELS" <<'PY'
import json
import sys

user_id, max_budget, models = sys.argv[1:4]
body = {"user_id": user_id}
if float(max_budget or 0) > 0:
    body["max_budget"] = float(max_budget)
if models:
    body["models"] = [m.strip() for m in models.split(",") if m.strip()]
print(json.dumps(body))
PY
)"

curl --fail --silent --show-error \
  "http://127.0.0.1:${PORT}/key/generate" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d "${PAYLOAD}"
echo
