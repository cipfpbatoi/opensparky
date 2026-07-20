# AGENTS.md

Desplegament Docker Compose per a DGX Spark (Ollama + Open WebUI + PostgreSQL/pgvector). No és una aplicació amb codi font a compilar: la major part dels canvis toquen `compose.yaml`, `.env.example`, scripts de `scripts/` i documentació.

## Ordres útils

```bash
make preflight      # ./scripts/preflight.sh — valida la DGX abans de desplegar
make build           # docker compose build --pull
make up               # docker compose up -d --build
make smoke           # ./scripts/smoke-test.sh
make test-ollama MODEL=nom:model
make test-api API_KEY=sk-... MODEL=nom:model
make backup
docker compose config --quiet   # valida compose.yaml (el que fa CI)
bash -n scripts/*.sh            # valida sintaxi dels scripts (el que fa CI)
```

CI (`.github/workflows/validate.yml`) genera un `.env` de validació a partir de `.env.example` amb valors ficticis i executa `docker compose config` i `bash -n`. Reprodueix eixos mateixos passos abans de dir que un canvi està llest.

## Regles de seguretat, no negociables

- **Mai** publicar el port d'Ollama més enllà de `127.0.0.1:11434:11434`. Publicar-lo com `11434:11434` exposa una API sense autenticació a la xarxa de la DGX.
- **Mai** commitejar `.env`, contingut de `backups/` ni cap secret real. `.env` ja està en `.gitignore`; `.env.example` només ha de tindre placeholders (`CANVIA_AQUEST_SECRET`, `CANVIA_AQUESTA_CONTRASENYA`, `sk-CANVIA_ACI`).
- El contenidor `postgres` no ha de publicar cap port; només accessible des de la xarxa Docker `dgx_ai_backend`.
- No usar mai una clau d'administrador d'Open WebUI en scripts, automatitzacions o exemples.
- Els contenidors s'executen sense privilegis ni capacitats Linux addicionals (`APP_UID`/`APP_GID`); no revertir això per conveniència.

## Convencions

- Documentació i missatges de commit en català.
- Commits en estil Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), verb en present, resum breu.
- Qualsevol variable nova a `.env.example` ha de portar comentari explicant-ne el propòsit i, si és un secret, com generar-lo (`openssl rand -base64 ...`).
- Actualitzar `README.md` (i `API_USUARIS.md` si afecta l'API d'usuaris) quan un canvi afecte el desplegament o l'ús.
