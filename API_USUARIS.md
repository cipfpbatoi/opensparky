# Accés a les APIs

## 1. API directa d'Ollama: només administració local

El port `11434` es publica exclusivament en el loopback de la DGX:

```text
http://127.0.0.1:11434
```

No incorpora autenticació. Per això no s'ha de canviar mai la publicació Docker a `0.0.0.0:11434` ni publicar-la mitjançant Cloudflare Tunnel.

Proves:

```bash
curl http://127.0.0.1:11434/api/tags
./scripts/test-local-ollama.sh nom:model
```

Compatibilitat OpenAI directa d'Ollama:

```bash
curl http://127.0.0.1:11434/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "nom:model",
    "messages": [{"role": "user", "content": "Hola"}]
  }'
```

## 2. API autenticada d'Open WebUI: usuaris

Cada usuari genera la seua clau des de:

```text
Settings → Account → API Keys
```

La clau hereta el rol, grups i models visibles de l'usuari. No s'ha de compartir una única clau entre alumnat o professorat.

### Llistar models

```bash
curl https://ia-professorat.cipfpbatoi.lan/api/models \
  -H 'Authorization: Bearer sk-CANVIA_ACI'
```

### Chat completions compatible amb OpenAI

```bash
curl https://ia-professorat.cipfpbatoi.lan/api/chat/completions \
  -H 'Authorization: Bearer sk-CANVIA_ACI' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "nom:model",
    "stream": false,
    "messages": [{"role": "user", "content": "Hola"}]
  }'
```

Per a clients compatibles amb OpenAI:

```text
Base URL: https://ia-professorat.cipfpbatoi.lan/api
API key:  la clau personal sk-...
```

Exemple Python:

```python
from openai import OpenAI

client = OpenAI(
    base_url="https://ia-professorat.cipfpbatoi.lan/api",
    api_key="sk-CANVIA_ACI",
)

response = client.chat.completions.create(
    model="nom:model",
    messages=[{"role": "user", "content": "Hola"}],
)
print(response.choices[0].message.content)
```

### API nativa d'Ollama, però autenticada per Open WebUI

S'han autoritzat únicament rutes d'inferència, llistat i embeddings. No s'han autoritzat descàrrega, eliminació ni còpia de models.

```bash
curl https://ia-professorat.cipfpbatoi.lan/ollama/api/tags \
  -H 'Authorization: Bearer sk-CANVIA_ACI'
```

```bash
curl https://ia-professorat.cipfpbatoi.lan/ollama/api/chat \
  -H 'Authorization: Bearer sk-CANVIA_ACI' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "nom:model",
    "stream": false,
    "messages": [{"role": "user", "content": "Hola"}]
  }'
```

## 3. Administració de permisos

En Open WebUI s'han de crear grups diferents, com a mínim:

- professorat;
- alumnat;
- comptes de servei.

Els models s'assignaran als grups corresponents. Les claus API hereten eixos permisos. Per a una automatització s'ha de crear un compte de servei propi i no usar la clau d'un administrador.

Les rutes autoritzades es troben en `API_KEYS_ALLOWED_ENDPOINTS` dins de `compose.yaml`. Qualsevol ampliació s'ha de revisar abans de desplegar-la.
