# DGX Spark: Ollama i Open WebUI nets, amb API controlada i Tika

Desplegament ARM64 per a DGX Spark amb:

- Ollama, Open WebUI, PostgreSQL+pgvector i Apache Tika en contenidors separats;
- GPU NVIDIA disponible per a Ollama;
- volums nous `dgx_ollama_data`, `dgx_openwebui_data` i `dgx_postgres_data`;
- PostgreSQL amb l'extensió `vector` com a base principal i base vectorial d'Open WebUI, sense cap port publicat;
- Apache Tika disponible internament en `tika:9998` per a Open WebUI;
- Ollama disponible en `127.0.0.1:11434` per a proves locals;
- Open WebUI disponible en `127.0.0.1:3000` per al proxy invers;
- Apache Tika exposat opcionalment en `127.0.0.1:9998` només per a proves de desenvolupament;
- claus API personals d'Open WebUI;
- rutes API limitades a inferència, models i embeddings;
- contenidors no privilegiats i sense capacitats Linux addicionals.

## Arquitectura

```text
Clients API / navegador
          │
       HTTPS 443
          │
Proxy invers o Cloudflare Tunnel
          │
127.0.0.1:3000
          │
Open WebUI ────── clau personal, grups i permisos
          │
     xarxa Docker (ai_backend)
          │
    ┌─────┴──────┐
    │            │
    │      ┌─────┴───────┐
    │      │             │
Ollama:11434  postgres:5432   tika:9998
GPU NVIDIA     (usuaris, xats, vectors)  (extracció documental)
    │            │             │
dgx_ollama_data  dgx_postgres_data  (intern)
                                             │
                                      localhost:9998 (opcional, proves)
```

## Apache Tika

Apache Tika és un servei d'extracció de contingut que Open WebUI utilitza per a processar documents PDF, DOCX, ODT i altres formats. El servei:

- Executa Apache Tika 3.x en un contenidor separat;
- És accessible des de la xarxa Docker interna `dgx_ai_backend` a través de `http://tika:9998`;
- **No s'exposa a la LAN en producció**; només es publica el port 9998 en `127.0.0.1` quan s'activa l'override de desenvolupament;
- Compta amb healthcheck i límits de recursos (4 vCPUs, 4 GB memòria);

Per a activar l'accés des de l'amfitrió per a proves:

```bash
docker compose -f compose.yaml -f compose.dev.yaml up -d
```

## Desplegament

### 1. Parar l'entorn antic, sense eliminar-lo encara

```bash
docker stop open-webui 2>/dev/null || true
docker rename open-webui open-webui-legacy 2>/dev/null || true
```

Els volums antics poden quedar guardats fins que el nou desplegament estiga validat.

### 2. Preparar `.env`

```bash
cp .env.example .env
SECRET="$(openssl rand -base64 48 | tr -d '\n')"
sed -i "s|CANVIA_AQUEST_SECRET|${SECRET}|" .env
nano .env
chmod 600 .env
```

Cal canviar, com a mínim:

```dotenv
WEBUI_URL=https://spark-6169.cipfpbatoi.lan
WEBUI_ADMIN_EMAIL=correu-administrador
WEBUI_ADMIN_PASSWORD=contrasenya-llarga-i-unica
POSTGRES_PASSWORD=contrasenya-llarga-i-unica
```

`POSTGRES_PASSWORD` es pot generar amb `openssl rand -base64 36`. Només s'aplica en el primer arrancada del volum `dgx_postgres_data`; canviar-la després requereix actualitzar-la també dins de PostgreSQL.

### 3. Validar la DGX

```bash
./scripts/preflight.sh
```

### 4. Construir i arrancar

```bash
docker compose build --pull
docker compose up -d
```

Per a proves locals amb Tika accessible des de localhost:

```bash
docker compose -f compose.yaml -f compose.dev.yaml up -d
```

### 5. Descarregar un model

```bash
make pull-model MODEL=gpt-oss:120b
```

### 6. Comprovar

```bash
./scripts/smoke-test.sh
curl http://127.0.0.1:11434/api/tags
curl http://127.0.0.1:3000/health
```

### 7. Validar Apache Tika

```bash
docker compose ps
docker compose exec openwebui \
  python -c "import urllib.request; print(urllib.request.urlopen('http://tika:9998/version').read().decode())"
```

## Accés local a Ollama

La publicació és:

```yaml
ports:
  - "127.0.0.1:11434:11434"
```

`OLLAMA_HOST=0.0.0.0:11434` només afecta l'interior del contenidor. Docker continua limitant l'accés de l'amfitrió al loopback.

No s'ha de canviar per:

```yaml
- "11434:11434"
```

perquè això publicaria Ollama en les interfícies de xarxa de la DGX sense autenticació.

## Apache Tika

El contenidor `tika` no publica cap port a la xarxa de producció: només és accessible des de la xarxa Docker interna `dgx_ai_backend`. Open WebUI hi accedeix via `http://tika:9998` per a extracció de contingut de documents.

Per a provar Apache Tika des de l'amfitrió (desenvolupament):

```bash
docker compose -f compose.yaml -f compose.dev.yaml up -d tika
curl http://127.0.0.1:9998/version
```

### Configuració d'Open WebUI

Open WebUI s'automàtica amb Apache Tika mitjançant les variables:

```yaml
CONTENT_EXTRACTION_ENGINE: tika
TIKA_SERVER_URL: http://tika:9998
```

### Proves d'extracció

Prova des del contenidor d'Open WebUI:

```bash
docker compose exec openwebui \
  python -c "import urllib.request; print(urllib.request.urlopen('http://tika:9998/version').read().decode())"
```

**Nota:** L'OCR de PDFs escanejats no està habilitat per defecte i requereix configuració addicional.

## PostgreSQL + pgvector

El contenidor `postgres` no publica cap port: només és accessible des de la xarxa Docker `dgx_ai_backend`. Open WebUI hi guarda usuaris, xats i, mitjançant `VECTOR_DB=pgvector`, els embeddings de la RAG.

`postgres-init/01-enable-vector.sql` crea l'extensió `vector` i només s'executa quan el volum `dgx_postgres_data` és nou. Si cal tornar a executar-lo sobre dades existents, cal fer-ho manualment:

```bash
docker compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

## API dels usuaris

Estan activades:

```yaml
ENABLE_API_KEYS: "true"
USER_PERMISSIONS_FEATURES_API_KEYS: "true"
ENABLE_API_KEYS_ENDPOINT_RESTRICTIONS: "true"
```

Cada usuari genera una clau personal en `Settings → Account → API Keys`. La guia completa està en [API_USUARIS.md](API_USUARIS.md).

La configuració permet:

- `/api/models`;
- `/api/chat/completions`;
- algunes rutes d'inferència i embeddings del proxy d'Ollama.

No permet descarregar, copiar o eliminar models mitjançant una clau d'usuari.

## Proxy o túnel

El proxy ha d'apuntar a:

```text
http://127.0.0.1:3000
```

No ha d'apuntar a Ollama. Tant la interfície web com l'API autenticada viatgen pel mateix domini HTTPS.

## Proves API

API directa d'Ollama:

```bash
make test-ollama
make test-ollama MODEL=nom:model
```

API autenticada d'Open WebUI:

```bash
make test-api API_KEY=sk-...
make test-api API_KEY=sk-... MODEL=nom:model
```

Per provar contra el domini HTTPS:

```bash
OPENWEBUI_API_BASE_URL=https://spark-6169.cipfpbatoi.lan \
OPENWEBUI_API_KEY=sk-... \
./scripts/test-openwebui-api.sh nom:model
```

## Còpies

```bash
make backup
```

Restauració:

```bash
./scripts/restore.sh backups/AAAAMMDD-HHMMSS
```

La còpia dels models pot ocupar centenars de gigabytes. En producció convé separar la política de còpia de la base d'Open WebUI de la política de recuperació dels models descarregables.

`make backup` també para i copia `dgx_postgres_data` (usuaris, xats i vectors). La còpia és en fred: els tres serveis es paren mentre dura.

## Actualització i rollback

### Actualització d'Apache Tika

1. Fixar la nova versió a `.env.example`:
   ```dotenv
   TIKA_VERSION=3.0.0-java21
   ```
2. Executar `docker compose pull tika`
3. Validar amb `docker compose config --quiet`
4. Recrear només Tika: `docker compose up -d tika`
5. Comprovar healthcheck: `docker compose ps`
6. Provar una ingesta documental

### Rollback

Si falla, tornar a la versió anterior al `.env`:

```bash
sed -i 's/TIKA_VERSION=nova-versio/TIKA_VERSION=versio-anterior/' .env
docker compose pull tika
docker compose up -d tika
```

No s'eliminen volums ni dades d'Open WebUI.

## GitHub

```bash
git init
git add .
git commit -m "chore: desplegament net DGX Spark amb API"
git branch -M main
git remote add origin git@github.com:ORGANITZACIO/dgx-spark-ai.git
git push -u origin main
```

El repositori ha de ser privat. `.env`, còpies i secrets no s'han de pujar.

## Notes de seguretat

- L'API local d'Ollama no autentica: només loopback.
- L'API d'usuaris s'ha de publicar amb HTTPS.
- Cada usuari o aplicació ha de tindre una clau pròpia.
- Les claus hereten permisos; cal separar professorat, alumnat i comptes de servei.
- No s'ha d'usar una clau d'administrador en OpenCode, scripts o automatitzacions.
- Encara falten quotes estrictes per usuari. Per a alumnat a escala, s'haurà d'afegir un gateway d'IA davant d'Open WebUI o Ollama.
