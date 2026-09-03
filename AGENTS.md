# AGENTS.md

Desplegament Docker Compose per a DGX Spark (vLLM + LiteLLM + Open WebUI + PostgreSQL/pgvector). vLLM serveix els models (un contenidor per model), LiteLLM centralitza el catàleg de models i la gestió de claus/usuaris/pressupostos darrere d'una única API OpenAI-compatible, i Open WebUI n'és un client més. No és una aplicació amb codi font a compilar: la major part dels canvis toquen `compose.yaml`, `.env.example`, `litellm/config.yaml`, scripts de `scripts/` i documentació.

## Ordres útils

```bash
make preflight       # ./scripts/preflight.sh — valida la DGX abans de desplegar
make build            # docker compose build --pull
make up                # docker compose up -d --build
docker compose --profile coding up -d --build vllm-coding   # model de codi opcional
make smoke            # ./scripts/smoke-test.sh
make test-vllm SERVICE=embeddings|reasoning|coding   # prova un vLLM directament (compose.dev.yaml)
make test-litellm API_KEY=sk-... MODEL=gpt-oss-120b  # prova l'API de LiteLLM
make litellm-create-key USER=id [BUDGET=usd] [MODELS=m1,m2]
make litellm-register-vectorstore   # magatzem de vectors LiteLLM+pgvector, opcional
make backup
docker compose config --quiet   # valida compose.yaml (el que fa CI)
bash -n scripts/*.sh            # valida sintaxi dels scripts (el que fa CI)
```

CI (`.github/workflows/validate.yml`) genera un `.env` de validació a partir de `.env.example` amb valors ficticis i executa `docker compose config` i `bash -n`. Reprodueix eixos mateixos passos abans de dir que un canvi està llest.

## Regles de seguretat, no negociables

- **Mai** publicar els ports dels contenidors `vllm-*` (motor d'inferència, sense autenticació pròpia real davant la xarxa) fora de `127.0.0.1` — i només en `compose.dev.yaml`, mai en `compose.yaml` de producció.
- **Mai** commitejar `.env`, contingut de `backups/` ni cap secret real. `.env` ja està en `.gitignore`; `.env.example` només ha de tindre placeholders (`CANVIA_AQUEST_SECRET`, `CANVIA_AQUESTA_CONTRASENYA`, `sk-CANVIA_ACI`).
- El contenidor `postgres` no ha de publicar cap port; només accessible des de la xarxa Docker `dgx_ai_backend`.
- **Mai** usar `LITELLM_MASTER_KEY` (accés total a LiteLLM: crear/revocar claus, `/ui`, despesa de tothom) en Open WebUI, scripts d'usuari final ni automatitzacions. Només en `scripts/litellm-create-key.sh`, en loopback. Cada usuari o aplicació ha de tindre la seua clau virtual pròpia.
- `LITELLM_SALT_KEY` s'ha de fixar en `.env` i no canviar-la mai sense motiu: xifra en PostgreSQL les claus de proveïdor que guarda LiteLLM.
- Els contenidors s'executen sense privilegis ni capacitats Linux addicionals (`APP_UID`/`APP_GID`); no revertir això per conveniència. `litellm-database` i `litellm-pgvector` encara no s'han endurit igual (sense `read_only` propi): és un gap conegut, documentat en README.md, no una excepció silenciosa.
- **Mai** connectar cap eina de sincronització/migració d'esquema (`prisma db push`, `prisma migrate`, `alembic upgrade` d'un servei aliè, etc.) a un esquema Postgres que continga taules d'un altre servei, ni tan sols amb un rol "de confiança". **Incident real (2026-09-03):** `litellm-pgvector` connectat amb el rol `openwebui` a l'esquema `public` i `prisma db push --accept-data-loss` van esborrar TOTES les taules d'Open WebUI en producció (chat, user, message, file...) perquè "db push" reconcilia tot l'esquema on es connecta amb el seu propi esquema Prisma. Cap nou servei que comparteixca una base de dades amb un altre (`litellm-pgvector` reutilitza `openwebui`, indicació explícita: no crear-li una base nova) ha de tindre el seu **propi esquema Postgres** i un **rol propi sense cap privilegi sobre l'esquema d'altri** (ni `public` d'una base amb dades reals) — la convenció (esquema separat) sola no basta, cal el límit de privilegis (`GRANT`/`REVOKE`) perquè siga estructuralment impossible, no només improbable. Vegeu `postgres-init/03-create-litellm-pgvector-role.sh` com a patró de referència.

## Convencions

- Documentació i missatges de commit en català.
- Commits en estil Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), verb en present, resum breu.
- Qualsevol variable nova a `.env.example` ha de portar comentari explicant-ne el propòsit i, si és un secret, com generar-lo. Contrasenyes que acaben dins d'una URL de connexió (Postgres): `openssl rand -hex 24`, mai `-base64` (`/`, `+` i `=` trenquen l'anàlisi de la URL a Prisma). Altres secrets: `openssl rand -base64 ...` va bé.
- Actualitzar `README.md` (i `API_USUARIS.md` si afecta l'API d'usuaris) quan un canvi afecte el desplegament o l'ús.
