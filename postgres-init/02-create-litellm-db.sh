#!/usr/bin/env bash
# Crea el rol i la base de dades propis de LiteLLM (claus virtuals, usuaris,
# pressupostos, logs d'ús), separats del rol/base d'Open WebUI. Igual que
# 01-enable-vector.sql, només s'executa quan el volum dgx_postgres_data és
# nou (docker-entrypoint-initdb.d). Idempotent per si de cas.
set -euo pipefail

: "${LITELLM_POSTGRES_DB:?falta LITELLM_POSTGRES_DB}"
: "${LITELLM_POSTGRES_USER:?falta LITELLM_POSTGRES_USER}"
: "${LITELLM_POSTGRES_PASSWORD:?falta LITELLM_POSTGRES_PASSWORD}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE ROLE ${LITELLM_POSTGRES_USER} LOGIN PASSWORD ''${LITELLM_POSTGRES_PASSWORD}'''
    WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${LITELLM_POSTGRES_USER}')\gexec

    SELECT 'CREATE DATABASE ${LITELLM_POSTGRES_DB} OWNER ${LITELLM_POSTGRES_USER}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${LITELLM_POSTGRES_DB}')\gexec

    GRANT ALL PRIVILEGES ON DATABASE ${LITELLM_POSTGRES_DB} TO ${LITELLM_POSTGRES_USER};
EOSQL
