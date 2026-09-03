# Connector no oficial de BerriAI (https://github.com/BerriAI/litellm-pgvector)
# que exposa una Vector Store API OpenAI-compatible sobre PostgreSQL+pgvector,
# per a la Vector Store API de LiteLLM (/v1/vector_stores). No publica cap
# imatge Docker: es construeix des del codi font, fixat a un commit concret
# (mai 'main') seguint la convenció d'este projecte de no usar 'latest'.
FROM python:3.11-slim

ARG LITELLM_PGVECTOR_REF=b553f84a32f580b4303297df5567f25912b59d93
ARG EMBEDDING_DIMENSIONS=1024
ARG APP_UID=10001
ARG APP_GID=10001

RUN apt-get update && apt-get install -y --no-install-recommends \
      git build-essential curl postgresql-client ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid "${APP_GID}" pgvector-app \
    && useradd --uid "${APP_UID}" --gid "${APP_GID}" \
       --home-dir /home/pgvector-app --create-home \
       --shell /usr/sbin/nologin pgvector-app

WORKDIR /app
RUN git clone https://github.com/BerriAI/litellm-pgvector.git . \
    && git checkout "${LITELLM_PGVECTOR_REF}" \
    && rm -rf .git

# BAAI/bge-m3 genera vectors de 1024 dimensions. L'esquema Prisma d'este
# projecte porta "vector(1536)" fixat per a OpenAI ada-002/3-small, sense
# parametritzar per variable d'entorn: cal pedaçar-lo abans de generar el
# client, o la inserció d'embeddings de bge-m3 fallaria per "expected 1536
# dimensions, not 1024". Qualifiquem el tipus amb "public." perquè este
# connector es connecta amb schema= a un esquema propi (mai 'public', vegeu
# el CMD més avall): sense qualificar, Postgres no trobaria el tipus
# "vector" (el crea l'extensió en 'public', 01-enable-vector.sql).
RUN grep -q "vector(1536)" prisma/schema.prisma \
    && sed -i "s/vector(1536)/public.vector(${EMBEDDING_DIMENSIONS})/" prisma/schema.prisma

RUN pip install --no-cache-dir -r requirements.txt

# "prisma generate" (client Python) escriu el schema generat dins de
# site-packages (propietat de root en este punt: ha d'executar-se abans de
# canviar a l'usuari no-root) i, a més, baixa el binari del motor Prisma a
# $HOME/.cache/prisma-python/. Fixem HOME abans de generar perquè eixa
# caché quede sota /home/pgvector-app (llegible per l'usuari no-root que
# arrancarà el contenidor) en lloc de /root (770, il·legible per a
# qualsevol altre usuari: "Permission denied" en arrancar).
ENV HOME=/home/pgvector-app \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
RUN prisma generate

RUN chown -R "${APP_UID}:${APP_GID}" /app /home/pgvector-app

USER ${APP_UID}:${APP_GID}

EXPOSE 8000
# No hi ha migració automàtica en arrancar (a diferència de litellm-database):
# cal fer "prisma db push" abans de servir. Idempotent i segur d'executar en
# cada arrancada NOMÉS perquè està aïllat en el seu propi esquema Postgres
# (PG_SCHEMA), mai en 'public'.
#
# INCIDENT REAL (2026-09-03): la primera versió apuntava "prisma db push
# --accept-data-loss" directament a l'esquema 'public' de la base
# 'openwebui' (reutilitzada, sense esquema propi). "db push" introspecciona
# TOT l'esquema connectat i el reconcilia amb el de Prisma (només
# vector_stores/embeddings) — va ESBORRAR totes les taules d'Open WebUI
# (chat, user, message, file...), producció real, sense avís previ més
# enllà del flag que ja vam passar nosaltres mateixos. Open WebUI es va
# poder recuperar (Alembic recrea l'esquema sencer si no en troba cap),
# però els xats, usuaris i fitxers de veritat es van perdre igualment.
# Per això CAL crear i usar sempre un esquema Postgres DEDICAT dins la base
# compartida (mai el 'public' d'una base amb dades d'altres serveis) abans
# de deixar que cap eina de sincronització d'esquema hi toque res.
#
# L'esquema i el rol ja existeixen sempre (creats per
# postgres-init/03-create-litellm-pgvector-role.sh, la font única de
# veritat): el rol amb què es connecta este contenidor NOMÉS té privilegis
# sobre el seu propi esquema, expressament SENSE el privilegi CREATE sobre
# la base de dades (calent per a poder crear esquemes nous) — mínim
# privilegi possible, res que un "CREATE SCHEMA IF NOT EXISTS" ací poguera
# fer per si mateix encara que ho intentara.
#
# DATABASE_URL es construeix ací (no en compose.yaml) codificant PG_PASSWORD
# per URL perquè Prisma no accepta '/', '+' ni altres caràcters especials
# sense escapar en una connection string ("invalid port number in database
# URL" encara que la contrasenya siga vàlida per a Postgres) — així es pot
# reutilitzar qualsevol contrasenya ja existent (com la de
# POSTGRES_PASSWORD, generada abans que este connector existira) sense
# haver-la de canviar.
#
# DOS DATABASE_URL diferents (vegeu docker-entrypoint.py), no una:
#
# - Per a "prisma db push": AMB "?schema=". Imprescindible — sense ell,
#   Prisma assumeix 'public' com a esquema (independentment del search_path
#   real de la connexió/rol). Comprovat en directe: sense "?schema=",
#   "prisma db push" va intentar tocar taules reals d'Open WebUI en
#   'public' (access_grant) i només el fet que el rol NO hi té privilegis
#   ho va evitar ("permission denied") — eixe rebuig és la xarxa de
#   seguretat real, no una convenció de client.
#
# - Per a l'aplicació (uvicorn/main.py): SENSE "?schema=". "?schema="
#   fixa el search_path NOMÉS de la connexió que l'estableix — Prisma obri
#   un grup de connexions per a l'aplicació, i cadascuna el torna a aplicar
#   pel seu compte (només 'litellm_pgvector', sense 'public'), fent que les
#   consultes internes del connector amb "::vector" sense qualificar
#   fallen de forma intermitent segons quina connexió del grup atenga la
#   petició (comprovat en directe). Sense "?schema=" en la URL de
#   l'aplicació, cada connexió nova parteix del search_path per defecte que
#   ja té fixat el ROL (postgres-init/03-..., "litellm_pgvector, public")
#   — s'aplica sol a totes, sense dependre de cap connexió concreta.
COPY --chown=${APP_UID}:${APP_GID} containers/litellm-pgvector-entrypoint.py /app/docker-entrypoint.py
CMD ["python3", "/app/docker-entrypoint.py"]
