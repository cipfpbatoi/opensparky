#!/usr/bin/env bash
# Crea el rol i l'esquema del connector litellm-pgvector DINS de la base
# 'openwebui' ja existent (reutilitzada a propòsit, no una base nova). El
# rol només té privilegis sobre el seu propi esquema (LITELLM_PGVECTOR_SCHEMA)
# — MAI sobre 'public', on viuen les taules reals d'Open WebUI.
#
# INCIDENT REAL (2026-09-03): la primera versió connectava amb el rol
# 'openwebui' directament a l'esquema 'public' i deixava que
# "prisma db push --accept-data-loss" hi sincronitzara l'esquema. Com que
# "db push" esborra qualsevol taula de l'esquema connectat que no siga
# seua, va ESBORRAR TOTES LES TAULES D'OPEN WEBUI (chat, user, message,
# file...) — producció real. Un rol amb permisos NOMÉS sobre el seu propi
# esquema fa que això siga estructuralment impossible: encara que
# l'eina volguera fer-ho, no tindria privilegis per a tocar 'public'.
#
# Només s'executa quan el volum dgx_postgres_data és nou. Idempotent.
set -euo pipefail

: "${LITELLM_PGVECTOR_POSTGRES_USER:?falta LITELLM_PGVECTOR_POSTGRES_USER}"
: "${LITELLM_PGVECTOR_POSTGRES_PASSWORD:?falta LITELLM_PGVECTOR_POSTGRES_PASSWORD}"
: "${LITELLM_PGVECTOR_SCHEMA:?falta LITELLM_PGVECTOR_SCHEMA}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE ROLE ${LITELLM_PGVECTOR_POSTGRES_USER} LOGIN PASSWORD ''${LITELLM_PGVECTOR_POSTGRES_PASSWORD}'''
    WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${LITELLM_PGVECTOR_POSTGRES_USER}')\gexec

    GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${LITELLM_PGVECTOR_POSTGRES_USER};

    CREATE SCHEMA IF NOT EXISTS "${LITELLM_PGVECTOR_SCHEMA}" AUTHORIZATION ${LITELLM_PGVECTOR_POSTGRES_USER};

    -- NOMÉS este esquema: sense GRANT sobre 'public' ni cap altre.
    GRANT USAGE, CREATE ON SCHEMA "${LITELLM_PGVECTOR_SCHEMA}" TO ${LITELLM_PGVECTOR_POSTGRES_USER};

    -- Taules noves d'este esquema, creades pel propi rol: ell ja n'és
    -- l'autoritzat (AUTHORIZATION, dalt) i per tant l'owner per defecte.

    -- El tipus "vector" el va crear l'extensió en 'public'
    -- (01-enable-vector.sql); cal poder-lo llegir sense poder escriure-hi
    -- res més. USAGE sobre 'public' ja és per defecte de PUBLIC en
    -- PostgreSQL 15+; ho fem explícit igualment per claredat i per si de
    -- cas s'ha revocat en algun moment.
    GRANT USAGE ON SCHEMA public TO ${LITELLM_PGVECTOR_POSTGRES_USER};

    ALTER ROLE ${LITELLM_PGVECTOR_POSTGRES_USER} IN DATABASE ${POSTGRES_DB} SET search_path = "${LITELLM_PGVECTOR_SCHEMA}", public;
EOSQL
