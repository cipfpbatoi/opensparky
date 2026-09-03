ARG VLLM_IMAGE=vllm/vllm-openai
ARG VLLM_VERSION=latest
FROM ${VLLM_IMAGE}:${VLLM_VERSION}

ARG APP_UID=10001
ARG APP_GID=10001

USER root
RUN groupadd --gid "${APP_GID}" vllm-app \
    && useradd --uid "${APP_UID}" --gid "${APP_GID}" \
       --home-dir /home/vllm --create-home \
       --shell /usr/sbin/nologin vllm-app \
    && mkdir -p /home/vllm/.cache/huggingface /home/vllm/.cache/vllm \
    && chown -R "${APP_UID}:${APP_GID}" /home/vllm

ENV HOME=/home/vllm \
    HF_HOME=/home/vllm/.cache/huggingface \
    VLLM_CACHE_ROOT=/home/vllm/.cache/vllm

USER ${APP_UID}:${APP_GID}
# ENTRYPOINT/CMD s'hereten de la imatge base (vllm/vllm-openai o l'equivalent
# ARM64/DGX Spark que trie l'operador). Els arguments d'arrencada (model,
# port, clau, etc.) es passen des de `command:` en compose.yaml.
