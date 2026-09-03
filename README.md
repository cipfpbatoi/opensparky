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

**Migrar una instància d'Open WebUI ja existent (no un desplegament nou).** Open WebUI guarda la configuració de connexions (`openai.*`, `ollama.*`, `rag.*`, entre altres) en la taula `config` de la seua base de dades la primera vegada que arranca, i des d'aleshores **ignora les variables d'entorn** del `compose.yaml` per a eixes claus concretes — només les aplica si encara no existeix cap valor guardat. Un contenidor que ja portava temps funcionant amb Ollama (com este desplegament abans de la migració) es queda amb `ollama.base_urls` apuntant a un host que ja no existeix, amb `openai.api_base_urls`/`openai.api_keys` pel connector "OpenAI" per defecte (`https://api.openai.com/v1`, clau buida) en lloc de LiteLLM, i amb `rag.embedding_engine=ollama` per als embeddings de la RAG (fitxers/coneixement pujats), també apuntant a Ollama. Es nota perquè el selector de models d'Open WebUI queda buit i la indexació de documents falla, encara que `docker compose up` s'haja executat correctament amb els envs nous.

La solució és corregir eixes files directament (una única vegada per instància migrada, no cada desplegament):

```bash
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'EOSQL'
UPDATE config SET value = 'false'::json WHERE key = 'ollama.enable';
UPDATE config SET value = '[]'::json WHERE key = 'ollama.base_urls';
UPDATE config SET value = 'true'::json WHERE key = 'openai.enable';
UPDATE config SET value = '["http://litellm:4000/v1"]'::json WHERE key = 'openai.api_base_urls';
UPDATE config SET value = '["LA_CLAU_VIRTUAL_D_OPENWEBUI"]'::json WHERE key = 'openai.api_keys';
-- Mateix problema per als embeddings de la RAG (fitxers/coneixement pujats
-- a Open WebUI): es queden amb el motor "ollama" apuntant a un host mort.
UPDATE config SET value = '"openai"'::json WHERE key = 'rag.embedding_engine';
UPDATE config SET value = '"bge-m3"'::json WHERE key = 'rag.embedding_model';
UPDATE config SET value = '"http://litellm:4000/v1"'::json WHERE key = 'rag.openai.api_base_url';
UPDATE config SET value = '"LA_CLAU_VIRTUAL_D_OPENWEBUI"'::json WHERE key = 'rag.openai.api_key';
EOSQL
docker compose restart open-webui
```

Un desplegament **nou** (volum `dgx_openwebui_data`/base de dades buits) no pateix açò: aplica directament els valors de `compose.yaml` en el primer arrancada.

## Clients externs (OpenCode i altres eines OpenAI-compatibles)

Qualsevol eina que parle el protocol OpenAI (OpenCode, scripts, IDEs) s'ha de connectar a LiteLLM, mai a Open WebUI ni directament a un `vllm-*`. Crea-li una clau pròpia, restringida als models que necessita:

```bash
./scripts/litellm-create-key.sh opencode-local 0 gpt-oss-120b
```

Configuració OpenAI-compatible per a l'eina:

```text
Base URL: https://api.spark-6169.cipfpbatoi.lan/v1
API key:  la clau virtual generada (sk-...)
Model:    gpt-oss-120b
```

## Magatzem de vectors de LiteLLM (pgvector)

LiteLLM pot exposar la seua pròpia Vector Store API OpenAI-compatible (`/v1/vector_stores/{id}/search`), perquè qualsevol client (OpenCode, scripts) puga fer RAG sense passar per Open WebUI. No és el mateix magatzem que la RAG interna d'Open WebUI (fitxers pujats des de la UI) — són dos usos diferents de la mateixa infraestructura pgvector.

**Arquitectura:** `litellm-pgvector` (connector no oficial de BerriAI, es construeix des del codi font fixat a un commit) reutilitza la base **`openwebui`** existent (taules pròpies `vector_stores`/`embeddings`, sense col·lisió) i genera els embeddings cridant de nou a LiteLLM amb bge-m3, amb una clau virtual restringida a eixe model.

```text
client ──/v1/vector_stores/{id}/search──▶ litellm ──pg_vector──▶ litellm-pgvector ──openai/bge-m3──▶ litellm ──▶ vllm-embeddings
                                                                        │
                                                                  postgres:openwebui (taules vector_stores/embeddings)
```

**Problemes reals trobats i resolts (2026-09-03), per si es torna a desplegar de zero:**

1. **`vector_store_registry` en `config.yaml` no funciona.** És una issue oberta i coneguda de LiteLLM ([BerriAI/litellm#25947](https://github.com/BerriAI/litellm/issues/25947)) en la imatge `litellm-database:main-stable`: la secció es llig bé del YAML, però LiteLLM no l'aplica en arrancar (`vector_store_id is required..., got vector_store_id=None`, encara que hi estiga). Per això `litellm/config.yaml` no en declara cap i el registre es fa en canvi via l'API de gestió (`POST /vector_store/new`), que sí funciona i persisteix en la base de dades de LiteLLM.
2. **L'ID del magatzem el genera SEMPRE el connector** (UUID), no es pot triar un nom propi com `pgvector-bge-m3` per a fer-hi cerques — eixe nom només val com a etiqueta (`vector_store_name`) en el registre de LiteLLM. `scripts/litellm-register-vectorstore.sh` fa els dos passos (crear al connector, registrar l'UUID resultant a LiteLLM) automàticament.
3. **`EMBEDDING__MODEL` necessita el prefix `openai/`** (`openai/bge-m3`, no `bge-m3` a soles): el connector crida el SDK Python de LiteLLM directament (`litellm.aembedding(model=...)`), que necessita eixe prefix per a saber que ha de parlar el protocol OpenAI contra `EMBEDDING__BASE_URL` — sense ell falla amb `LLM Provider NOT provided`.
4. **La contrasenya de Postgres amb `/` o `+` trenca Prisma** (`invalid port number in database URL`), igual que amb `LITELLM_POSTGRES_PASSWORD` (vegeu més avall) — però ací és `POSTGRES_PASSWORD`, una credencial ja en ús per Open WebUI en producció, que no convé rotar només per això. La imatge codifica la contrasenya per URL en arrancar (`containers/litellm-pgvector.Dockerfile`), no cal tocar cap contrasenya existent.
5. **`prisma generate` (client Python) baixa el motor a `$HOME/.cache/prisma-python/`**, no dins de `site-packages`: cal fixar `HOME` a un directori de l'usuari no-root *abans* de generar, o l'usuari no-root rep "Permission denied" en arrancar (la cau quedaria sota `/root`, il·legible).

**Ús** (amb una clau virtual de LiteLLM, mai la mestra):

```bash
curl https://api.spark-6169.cipfpbatoi.lan/v1/vector_stores/EL_UUID/search \
  -H 'Authorization: Bearer sk-CANVIA_ACI' \
  -H 'Content-Type: application/json' \
  -d '{"query": "text a cercar"}'
```

Inserir contingut requereix l'embedding ja calculat (el connector no l'accepta en text pla per a inserir, només per a cercar) — via LiteLLM i després el connector directament (loopback, `LITELLM_PGVECTOR_PORT`):

```bash
VEC=$(curl -s https://api.spark-6169.cipfpbatoi.lan/v1/embeddings \
  -H 'Authorization: Bearer sk-CANVIA_ACI' -H 'Content-Type: application/json' \
  -d '{"model":"bge-m3","input":"text a indexar"}' \
  | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)['data'][0]['embedding']))")
curl "http://127.0.0.1:${LITELLM_PGVECTOR_PORT:-8010}/v1/vector_stores/EL_UUID/embeddings" \
  -H "Authorization: Bearer ${LITELLM_PGVECTOR_SERVER_API_KEY}" -H 'Content-Type: application/json' \
  -d "{\"content\":\"text a indexar\",\"embedding\":${VEC}}"
```

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
POSTGRES_PASSWORD=...              # openssl rand -hex 24
LITELLM_POSTGRES_PASSWORD=...      # openssl rand -hex 24
LITELLM_MASTER_KEY=...             # echo "sk-$(openssl rand -hex 32)"
LITELLM_SALT_KEY=...               # openssl rand -base64 48
VLLM_EMBEDDINGS_API_KEY=...        # echo "sk-$(openssl rand -hex 32)"
VLLM_REASONING_API_KEY=...         # echo "sk-$(openssl rand -hex 32)"
VLLM_CODING_API_KEY=...            # echo "sk-$(openssl rand -hex 32)", només si actives el perfil coding
VLLM_CODING_MODEL=...              # confirma el model, vegeu secció anterior
LITELLM_PGVECTOR_SERVER_API_KEY=...  # echo "sk-$(openssl rand -hex 32)", només si vols el magatzem de vectors
```

`OPENWEBUI_LITELLM_API_KEY` (pas 4) i `LITELLM_PGVECTOR_EMBEDDING_API_KEY` (pas 6) es generen més avant: deixa els placeholders de moment.

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

### 6. Magatzem de vectors de LiteLLM (opcional)

```bash
docker compose up -d --build litellm-pgvector
./scripts/litellm-create-key.sh litellm-pgvector-service 0 bge-m3
```

Copia el `key` de la resposta a `LITELLM_PGVECTOR_EMBEDDING_API_KEY` en `.env`, aplica-ho i registra el magatzem:

```bash
docker compose up -d litellm-pgvector
./scripts/litellm-register-vectorstore.sh
```

Anota el `vector_store_id` (UUID) que imprimeix: cal per a `/v1/vector_stores/{id}/search`. Detalls en la secció següent.

### 7. Activar el model de programació (opcional)

```bash
docker compose --profile coding up -d --build vllm-coding
```

Després, descomenta el bloc `coding-model` en `litellm/config.yaml` i:

```bash
docker compose up -d litellm
```

### 8. Comprovar

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
