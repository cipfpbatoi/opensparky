# DGX Spark: Ollama i Open WebUI nets, amb API controlada

Desplegament ARM64 per a DGX Spark amb:

- Ollama i Open WebUI en contenidors separats;
- GPU NVIDIA disponible per a Ollama;
- volums nous `dgx_ollama_data` i `dgx_openwebui_data`;
- Ollama disponible en `127.0.0.1:11434` per a proves locals;
- Open WebUI disponible en `127.0.0.1:3000` per al proxy invers;
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
     xarxa Docker
          │
Ollama:11434 ─── GPU NVIDIA
          │
  dgx_ollama_data

Administració local de la DGX
          │
127.0.0.1:11434 ── API Ollama sense autenticació
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
WEBUI_URL=https://ia-professorat.cipfpbatoi.lan
WEBUI_ADMIN_EMAIL=correu-administrador
WEBUI_ADMIN_PASSWORD=contrasenya-llarga-i-unica
```

### 3. Validar la DGX

```bash
./scripts/preflight.sh
```

### 4. Construir i arrancar

```bash
docker compose build --pull
docker compose up -d
docker compose ps
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
OPENWEBUI_API_BASE_URL=https://ia-professorat.cipfpbatoi.lan \
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
