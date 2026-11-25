#!/usr/bin/env bash
# Crea un equip (team) de LiteLLM amb límits compartits entre totes les
# claus que s'hi afigen després (vegeu litellm-create-key.sh, paràmetre
# team_id). Fa servir sempre la clau MESTRA i el port en loopback: mai
# exposes esta operació via Caddy.
#
# Ús: ./scripts/litellm-create-team.sh <team_id> [model1,model2,...] [rpm_limit] [tpm_limit] [pressupost_usd] [budget_duration]
#
# Exemples:
#   ./scripts/litellm-create-team.sh alumnes-ia2026 gpt-oss-120b,bge-m3 30 100000 50 30d
#
# rpm_limit/tpm_limit/pressupost són AGREGATS: el límit compartit entre
# TOTES les claus de l'equip (no per clau individual) — pensat per a que
# una classe sencera no esgote la GPU compartida, no per limitar un
# alumne concret (per a això, revoca la seua clau individual).
# budget_duration (p. ex. "1d", "30d") fa que el pressupost es reinicie
# sol; sense ell, un cop gastat no es recupera mai.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${LITELLM_MASTER_KEY:?Defineix LITELLM_MASTER_KEY en el fitxer .env}"

TEAM_ID="${1:-}"
MODELS="${2:-}"
RPM_LIMIT="${3:-}"
TPM_LIMIT="${4:-}"
MAX_BUDGET="${5:-0}"
BUDGET_DURATION="${6:-}"
PORT="${LITELLM_PORT:-4000}"

if [[ -z "$TEAM_ID" ]]; then
  echo "Ús: $0 <team_id> [model1,model2,...] [rpm_limit] [tpm_limit] [pressupost_usd] [budget_duration]" >&2
  exit 1
fi

PAYLOAD="$(python3 - "$TEAM_ID" "$MODELS" "$RPM_LIMIT" "$TPM_LIMIT" "$MAX_BUDGET" "$BUDGET_DURATION" <<'PY'
import json
import sys

team_id, models, rpm_limit, tpm_limit, max_budget, budget_duration = sys.argv[1:7]
body = {"team_id": team_id, "team_alias": team_id}
if models:
    body["models"] = [m.strip() for m in models.split(",") if m.strip()]
if rpm_limit:
    body["rpm_limit"] = int(rpm_limit)
if tpm_limit:
    body["tpm_limit"] = int(tpm_limit)
if float(max_budget or 0) > 0:
    body["max_budget"] = float(max_budget)
if budget_duration:
    body["budget_duration"] = budget_duration
print(json.dumps(body))
PY
)"

curl --fail --silent --show-error \
  "http://127.0.0.1:${PORT}/team/new" \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d "${PAYLOAD}"
echo
