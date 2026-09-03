# DGX Spark: vLLM + LiteLLM + Open WebUI, amb API centralitzada i Tika

Desplegament ARM64 per a DGX Spark amb:

- vLLM com a motor d'inferència (un servidor OpenAI-compatible per model), GPU NVIDIA compartida;
- LiteLLM com a gateway central: unifica models, claus (usuàries/aplicacions) i pressupostos en una única API OpenAI-compatible, amb estat en PostgreSQL;
- Open WebUI com a client més de LiteLLM (ja no parla amb el motor d'inferència directament ni gestiona les seues pròpies claus API);
- PostgreSQL+pgvector com a base compartida: base d'Open WebUI (usuaris, xats, vectors) i base de LiteLLM (claus, usuaris, pressupostos, logs), en rols separats;
- Apache Tika disponible internament per a l'extracció de contingut de documents que fa servir Open WebUI;
- volums nous `dgx_openwebui_data`, `dgx_postgres_data` i una caché per vLLM (`dgx_vllm_*_cache`, regenerable, no es fa còpia);
- contenidors no privilegiats i sense capacitats Linux addicionals.

## Arquitectura

```text
Clients API / navegador
          │
       HTTPS 443
          │
        Caddy (dos subdominis, mateixa CA interna)
          │
   ┌──────┴───────────────────────┐
   │                               │
spark-6169.cipfpbatoi.lan   api.spark-6169.cipfpbatoi.lan
   │                               │
127.0.0.1:3000                127.0.0.1:4000
   │                               │
Open WebUI                     LiteLLM ── claus virtuals, usuaris, pressupostos
   │  (client OpenAI-compatible)   │        (gateway central de models)
   │                               │
   └──────────┬────────────────────┘
              │
        xarxa Docker (ai_backend)
              │
   ┌──────────┼──────────┬───────────────┬───────────────┐
   │          │          │               │               │
postgres:5432 tika:9998  vllm-embeddings vllm-reasoning  vllm-coding (opcional)
(openwebui +  (extracció (bge-m3)        (gpt-oss:120b)  (perfil "coding")
 litellm,     documental)     │               │               │
 sense port)                   └───────────────┴───────┬───────┘
   │                                            GPU NVIDIA compartida
dgx_postgres_data
```

Cap servei d'inferència (vLLM) ni la base de dades es publica fora de la xarxa Docker. Només Open WebUI i LiteLLM tenen una publicació en `127.0.0.1` per a administració/proves locals, a més del que exposa Caddy per HTTPS.

## Per què LiteLLM davant de vLLM (i no Open WebUI)

- Un únic lloc per crear/revocar claus i assignar pressupostos, per usuari o aplicació, independentment de si el client és Open WebUI, un script o una integració futura.
- Els clients no necessiten conèixer quin `vllm-*` serveix quin model: LiteLLM exposa un únic catàleg (`bge-m3`, `gpt-oss-120b`, opcionalment `coding-model`) sobre una única API OpenAI-compatible.
- Prepara separar peces en el futur (p. ex. moure `vllm-reasoning` a una altra màquina) sense tocar els clients: només caldria canviar `api_base` en `litellm/config.yaml`.

Per això Open WebUI ja **no** gestiona claus API pròpies (`ENABLE_API_KEYS` i relacionades s'han eliminat: eren la via d'accés extern quan Open WebUI parlava directament amb Ollama; ara eixa via és LiteLLM).

## vLLM: un servidor per model

Cada model corre en el seu propi contenidor vLLM (`vllm-embeddings`, `vllm-reasoning`, `vllm-coding`), tots compartint la mateixa GPU. Això és deliberat: vLLM no barreja models totalment diferents en un mateix procés, i mantindre'ls separats permet aturar-ne un (per exemple `vllm-coding`) sense afectar els altres.

**Memòria unificada compartida.** La DGX Spark reparteix memòria entre CPU, sistema operatiu i GPU. `VLLM_*_GPU_MEM_UTIL` reserva un percentatge de la memòria de GPU per procés; si actives `vllm-coding` a més de `vllm-reasoning`, comprova que la suma (més marge per al sistema) no supere el total físic abans d'arrancar-los alhora. Els valors per defecte en `.env.example` són conservadors per a `gpt-oss:120b` + `bge-m3` funcionant junts; `vllm-coding` és opcional i pensat per activar-lo quan calga, no necessàriament de forma permanent.

**Verificat el 2026-09-02 en esta DGX Spark concreta** amb `vllm/vllm-openai:v0.28.0` (build `linux/arm64` confirmada: `docker manifest inspect vllm/vllm-openai:v0.28.0`) i `ghcr.io/berriai/litellm-database:main-stable` (també `arm64`). Si canvies de versió, torna a comprovar-ho abans de desplegar.

**Problema conegut i ja resolt en `vllm-reasoning`: vocabulari "harmony" de gpt-oss.** `openai/gpt-oss-120b` (i -20b) fan servir el format de resposta "harmony" d'OpenAI. El client Rust intern (`openai_harmony`) intenta baixar el seu fitxer de vocabulari des de `openaipublic.blob.core.windows.net` en arrancar, i eixe client falla en molts entorns — també reportat als playbooks oficials de DGX Spark ([NVIDIA/dgx-spark-playbooks#17](https://github.com/NVIDIA/dgx-spark-playbooks/issues/17)) — encara que la resta de xarxa (baixada del model des de HuggingFace, etc.) funcione perfectament. Sense això, `vllm-reasoning` arranca i marca healthy, però `/v1/chat/completions` respon `500 error downloading or loading vocab file`.

La solució és pre-descarregar eixe fitxer amb el nom que espera la seua caché (SHA1 de la URL) dins del volum persistent `dgx_vllm_reasoning_cache`, i apuntar-hi amb `TIKTOKEN_RS_CACHE_DIR` (ja configurat en `compose.yaml`). Si es recrea el volum des de zero, cal repetir-ho una vegada:

```bash
docker compose exec vllm-reasoning python3 -c "
import hashlib, urllib.request, os
CACHE_DIR = '/home/vllm/.cache/tiktoken-rs-cache'
os.makedirs(CACHE_DIR, exist_ok=True)
for url in [
    'https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken',
    'https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken',
]:
    dest = os.path.join(CACHE_DIR, hashlib.sha1(url.encode()).hexdigest())
    if not os.path.exists(dest):
        open(dest, 'wb').write(urllib.request.urlopen(url, timeout=30).read())
        print('baixat', dest)
"
docker compose restart vllm-reasoning
```

**El model de `vllm-coding`** és `Qwen/Qwen3-Coder-30B-A3B-Instruct` per defecte (ja el tenies baixat via Ollama com `qwen3-coder:30b`); canvia `VLLM_CODING_MODEL` si en vols un altre.

## Desplegament

### 1. Preparar `.env`

```bash
cp .env.example .env
SECRET="$(openssl rand -base64 48 | tr -d '\n')"
sed -i "0,/CANVIA_AQUEST_SECRET/s//${SECRET}/" .env
nano .env
chmod 600 .env
```

Cal generar/canviar, com a mínim:

```dotenv
WEBUI_URL=https://spark-6169.cipfpbatoi.lan
LITELLM_URL=https://api.spark-6169.cipfpbatoi.lan
WEBUI_ADMIN_EMAIL=correu-administrador
WEBUI_ADMIN_PASSWORD=contrasenya-llarga-i-unica
POSTGRES_PASSWORD=...              # openssl rand -base64 36
LITELLM_POSTGRES_PASSWORD=...      # openssl rand -base64 36
LITELLM_MASTER_KEY=...             # echo "sk-$(openssl rand -hex 32)"
LITELLM_SALT_KEY=...               # openssl rand -base64 48
VLLM_EMBEDDINGS_API_KEY=...        # echo "sk-$(openssl rand -hex 32)"
VLLM_REASONING_API_KEY=...         # echo "sk-$(openssl rand -hex 32)"
VLLM_CODING_API_KEY=...            # echo "sk-$(openssl rand -hex 32)", només si actives el perfil coding
VLLM_CODING_MODEL=...              # confirma el model, vegeu secció anterior
```

`OPENWEBUI_LITELLM_API_KEY` es genera més avant (pas 4): deixa el placeholder de moment.

### 2. Validar la DGX

```bash
./scripts/preflight.sh
```

### 3. Alçar la base, els vLLM i LiteLLM (encara sense Open WebUI)

```bash
docker compose up -d --build postgres vllm-embeddings vllm-reasoning litellm
docker compose ps
```

Espera que `vllm-reasoning` estiga `healthy` (la primera càrrega d'un model de 120B pot trigar molts minuts a descarregar-se i carregar-se).

### 4. Generar la clau d'Open WebUI en LiteLLM

```bash
./scripts/litellm-create-key.sh openwebui-service 0 bge-m3,gpt-oss-120b
```

Copia el `key` de la resposta a `OPENWEBUI_LITELLM_API_KEY` en `.env`.

### 5. Alçar Open WebUI i Caddy

```bash
docker compose up -d --build
```

Per a proves locals amb Tika i cada vLLM accessibles des de localhost:

```bash
docker compose -f compose.yaml -f compose.dev.yaml up -d
```

### 6. Activar el model de programació (opcional)

```bash
docker compose --profile coding up -d --build vllm-coding
```

Després, descomenta el bloc `coding-model` en `litellm/config.yaml` i:

```bash
docker compose up -d litellm
```

### 7. Comprovar

```bash
./scripts/smoke-test.sh
curl http://127.0.0.1:4000/health/liveliness
curl http://127.0.0.1:3000/health
```

## Gestió d'usuaris i claus (LiteLLM)

Tota la gestió de claus es fa contra LiteLLM, en loopback, amb la clau mestra — mai amb la clau mestra des d'un client final:

```bash
./scripts/litellm-create-key.sh professorat-maria 20 gpt-oss-120b,bge-m3
./scripts/litellm-create-key.sh alumnat-grup1a 5 gpt-oss-120b
./scripts/litellm-create-key.sh integracio-moodle 0
```

- El 2n paràmetre és el pressupost en USD (0 = sense límit; útil encara sense facturació real, LiteLLM comptabilitza l'ús igualment).
- El 3r paràmetre restringeix els models visibles per a eixa clau; buit = tots els de `model_list`.
- La UI d'administració (usuaris, claus, despesa per clau) és `https://api.spark-6169.cipfpbatoi.lan/ui`, autenticada amb `LITELLM_MASTER_KEY`.

Detalls i exemples de crida a l'API queden en [API_USUARIS.md](API_USUARIS.md).

## PostgreSQL + pgvector

El contenidor `postgres` no publica cap port: només és accessible des de la xarxa Docker `dgx_ai_backend`. Allotja dues bases amb rols separats:

- `openwebui` (rol `openwebui`): usuaris, xats i, mitjançant `VECTOR_DB=pgvector`, els embeddings de la RAG d'Open WebUI.
- `litellm` (rol `litellm`): claus virtuals, usuaris, pressupostos i logs d'ús de LiteLLM.

`postgres-init/01-enable-vector.sql` crea l'extensió `vector`; `postgres-init/02-create-litellm-db.sh` crea el rol i la base de LiteLLM. Tots dos només s'executen quan el volum `dgx_postgres_data` és nou.

## Apache Tika

Sense canvis respecte al backend d'inferència: Open WebUI hi continua accedint via `http://tika:9998` per a extracció de contingut (PDF, DOCX, ODT...). No publica cap port en producció.

```bash
docker compose -f compose.yaml -f compose.dev.yaml up -d tika
curl http://127.0.0.1:9998/version
```

## Còpies

```bash
make backup
```

Còpia només `dgx_openwebui_data` i `dgx_postgres_data` (usuaris, xats, vectors, claus i pressupostos de LiteLLM): és l'única dada irrecuperable. Les caches de vLLM (`dgx_vllm_*_cache`) es regeneren descarregant de nou des de Hugging Face i no es copien.

Restauració:

```bash
./scripts/restore.sh backups/AAAAMMDD-HHMMSS
```

## Proves

```bash
make test-vllm SERVICE=reasoning       # requereix compose.dev.yaml
make test-litellm API_KEY=sk-... MODEL=gpt-oss-120b
LITELLM_API_BASE_URL=https://api.spark-6169.cipfpbatoi.lan \
LITELLM_API_KEY=sk-... \
./scripts/test-litellm-api.sh gpt-oss-120b
```

## GitHub

```bash
git init
git add .
git commit -m "feat: substitueix Ollama per vLLM+LiteLLM com a backend d'inferència"
git branch -M main
git remote add origin git@github.com:ORGANITZACIO/dgx-spark-ai.git
git push -u origin main
```

El repositori ha de ser privat. `.env`, còpies i secrets no s'han de pujar.

## Notes de seguretat

- Cap servei d'inferència (vLLM) ni la base de dades es publica fora de la xarxa Docker; només Open WebUI i LiteLLM tenen loopback per a administració local.
- `LITELLM_MASTER_KEY` dona accés total (crear/revocar claus, `/ui`, veure despesa de tothom): no s'usa mai en Open WebUI, scripts d'usuari final ni automatitzacions — sols en `scripts/litellm-create-key.sh`, en loopback.
- Cada usuari o aplicació ha de tindre una clau virtual pròpia amb els models i el pressupost mínims necessaris.
- `LITELLM_SALT_KEY` s'ha de fixar i conservar: xifra les claus de proveïdor guardades en PostgreSQL; perdre-la trenca el desxifratge d'eixes dades.
- Les claus internes `VLLM_*_API_KEY` viatgen només per la xarxa Docker, però mai han d'estar buides (defensa en profunditat).
- `litellm` encara no porta `read_only`/`user:` propi com la resta de contenidors (gap conegut, no una excepció silenciosa): abans de confiar-hi en producció, valida que arranca bé amb eixe enduriment afegit i aplica'l.
- Encara falten quotes estrictes per usuari més enllà del pressupost de LiteLLM. Per a alumnat a escala, revisa `max_budget` i `rpm`/`tpm` per clau.
