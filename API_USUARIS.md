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

### Grups grans amb límit compartit (p. ex. alumnat)

Per a molta gent compartint la mateixa GPU (una classe sencera), crea primer un **equip (team)** amb el límit agregat entre totes les claus que s'hi afigen, i després una clau individual per persona dins d'eixe equip (revocable una a una, però totes topen amb el mateix límit compartit):

```bash
./scripts/litellm-create-team.sh <team_id> [model1,model2,...] [rpm_limit] [tpm_limit] [pressupost_usd] [budget_duration]
./scripts/litellm-create-key.sh <identificador> [pressupost_usd] [model1,model2,...] <team_id>

# Exemple (equip real d'este desplegament, 2026-11-25): 30 peticions/min i
# 100.000 tokens/min AGREGATS entre tot l'alumnat, pressupost reiniciat
# cada 30 dies, restringit a gpt-oss-120b i bge-m3.
./scripts/litellm-create-team.sh alumnes-ia gpt-oss-120b,bge-m3 30 100000 0 30d
./scripts/litellm-create-key.sh alumne.nom1 0 gpt-oss-120b,bge-m3 alumnes-ia
./scripts/litellm-create-key.sh alumne.nom2 0 gpt-oss-120b,bge-m3 alumnes-ia
```

`rpm_limit`/`tpm_limit`/pressupost del team són **agregats** (compartits entre totes les claus de l'equip), no per alumne individual — pensats per a que la classe sencera no esgote la GPU compartida amb els altres usos del desplegament, no per limitar algú en concret (per a això, revoca només la seua clau).

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

Per a grups que necessiten accés restringit a documents propis dins d'Open WebUI (p. ex. secretaria amb una base de coneixement que només ells poden veure), el patró és **Grups + Knowledge** d'Open WebUI (Admin Panel → Users/Groups i Workspace → Knowledge), no cap mecanisme de LiteLLM — vegeu README.md, secció "Accés restringit per a grups".

## 3. Administració de claus i pressupostos

La UI d'administració de LiteLLM (usuaris, claus, despesa) és:

```text
https://api.spark-6169.cipfpbatoi.lan/ui
```

S'autentica amb un usuari `proxy_admin` propi (correu+contrasenya, creat des de Internal Users → Invite User) — la clau mestra ja **no** funciona com a contrasenya d'esta UI (`disable_env_credential_login: true`). Des d'ací (o per API) es poden:

- crear/revocar claus virtuals;
- assignar pressupost (`max_budget`) i límits de peticions (`rpm`/`tpm`) per clau;
- restringir els models visibles per clau;
- consultar despesa per usuari/clau.

Convé mantindre, com a mínim, claus separades per: professorat, alumnat i comptes de servei (integracions), cadascuna amb els models i el pressupost mínims necessaris. Per a una automatització, crea sempre un compte de servei propi — no reutilitzes la clau d'una persona ni la clau mestra.
