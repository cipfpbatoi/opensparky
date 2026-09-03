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

# "?schema=" en DATABASE_URL fixa el search_path de TOTA la connexió a
# NOMÉS eixe esquema (necessari perquè "prisma db push" no toque 'public',
# vegeu el CMD), però l'aplicació fa consultes pròpies amb "::vector" sense
# qualificar que llavors no troben el tipus (el crea l'extensió en
# 'public'). fix-search-path.py amplia el search_path d'eixa mateixa
# sessió just en connectar, perquè busque també en 'public' — sense tocar
# cap consulta interna del connector.
COPY containers/litellm-pgvector-fix-search-path.py /tmp/fix-search-path.py
RUN python3 /tmp/fix-search-path.py main.py \
    && rm /tmp/fix-search-path.py \
    && grep -q 'SET search_path TO' main.py

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
# "?schema=" és IMPRESCINDIBLE: sense ell, Prisma assumeix 'public' com a
# esquema (independentment del search_path real de la connexió/rol) — ho
# vam comprovar en directe: sense "?schema=", "prisma db push" va intentar
# tocar taules reals d'Open WebUI en 'public' (access_grant) i només el
# fet que el rol NO hi té privilegis ho va evitar ("permission denied").
# Eixe rebuig és la xarxa de seguretat real, no una convenció de client.
CMD ["sh", "-c", "export DATABASE_URL=$(python3 -c \"import os, urllib.parse as u; print('postgresql://' + u.quote(os.environ['PG_USER'], safe='') + ':' + u.quote(os.environ['PG_PASSWORD'], safe='') + '@' + os.environ['PG_HOST'] + ':' + os.environ['PG_PORT'] + '/' + os.environ['PG_DATABASE'] + '?schema=' + u.quote(os.environ['PG_SCHEMA'], safe=''))\") && prisma db push --accept-data-loss --skip-generate && exec uvicorn main:app --host 0.0.0.0 --port 8000"]
