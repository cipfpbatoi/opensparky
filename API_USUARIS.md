# Accés a les APIs

Tot l'accés extern (aplicacions, scripts, integracions) es fa contra **LiteLLM**, no contra Open WebUI ni contra vLLM directament. LiteLLM és qui centralitza el catàleg de models i les claus.

## 1. API de LiteLLM: models i claus

```text
https://api.spark-6169.cipfpbatoi.lan
```

Compatible amb el format OpenAI. Cada usuari o aplicació ha de tindre la seua **clau virtual pròpia** (mai compartir-ne una, mai usar `LITELLM_MASTER_KEY`).

### Crear una clau virtual

Només un administrador, en loopback, amb la clau mestra:

```bash
./scripts/litellm-create-key.sh <identificador> [pressupost_usd] [model1,model2,...]

# Exemples
./scripts/litellm-create-key.sh professorat-maria 20 gpt-oss-120b,bge-m3
./scripts/litellm-create-key.sh alumnat-grup1a 5 gpt-oss-120b
./scripts/litellm-create-key.sh integracio-moodle 0
```

La resposta inclou `"key": "sk-..."`. Eixa és la clau que rep la persona o el sistema, res més.

### Llistar models

```bash
curl https://api.spark-6169.cipfpbatoi.lan/v1/models \
  -H 'Authorization: Bearer sk-CANVIA_ACI'
```

Models disponibles: `bge-m3` (embeddings), `gpt-oss-120b` (raonament) i, si el perfil `coding` està actiu, `coding-model`.

### Chat completions compatible amb OpenAI

```bash
curl https://api.spark-6169.cipfpbatoi.lan/v1/chat/completions \
  -H 'Authorization: Bearer sk-CANVIA_ACI' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gpt-oss-120b",
    "stream": false,
    "messages": [{"role": "user", "content": "Hola"}]
  }'
```

### Embeddings

```bash
curl https://api.spark-6169.cipfpbatoi.lan/v1/embeddings \
  -H 'Authorization: Bearer sk-CANVIA_ACI' \
  -H 'Content-Type: application/json' \
  -d '{"model": "bge-m3", "input": "text a vectoritzar"}'
```

Per a clients compatibles amb OpenAI:

```text
Base URL: https://api.spark-6169.cipfpbatoi.lan/v1
API key:  la clau virtual sk-...
```

Exemple Python:

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://api.spark-6169.cipfpbatoi.lan/v1",
    api_key="sk-CANVIA_ACI",
)

response = client.chat.completions.create(
    model="gpt-oss-120b",
    messages=[{"role": "user", "content": "Hola"}],
)
print(response.choices[0].message.content)
```

## 2. Open WebUI: interfície de xat

Open WebUI (`https://spark-6169.cipfpbatoi.lan`) és ara un client més de LiteLLM: no exposa la seua pròpia API de claus (`ENABLE_API_KEYS` s'ha retirat). Per accedir per API, usa sempre la de LiteLLM (secció 1).

## 3. Administració de claus i pressupostos

La UI d'administració de LiteLLM (usuaris, claus, despesa) és:

```text
https://api.spark-6169.cipfpbatoi.lan/ui
```

S'autentica amb `LITELLM_MASTER_KEY`. Des d'ací (o per API) es poden:

- crear/revocar claus virtuals;
- assignar pressupost (`max_budget`) i límits de peticions (`rpm`/`tpm`) per clau;
- restringir els models visibles per clau;
- consultar despesa per usuari/clau.

Convé mantindre, com a mínim, claus separades per: professorat, alumnat i comptes de servei (integracions), cadascuna amb els models i el pressupost mínims necessaris. Per a una automatització, crea sempre un compte de servei propi — no reutilitzes la clau d'una persona ni la clau mestra.
