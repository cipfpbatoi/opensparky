ARG OLLAMA_VERSION=0.31.1
FROM ollama/ollama:${OLLAMA_VERSION}

ARG APP_UID=10001
ARG APP_GID=10001

USER root
RUN groupadd --gid "${APP_GID}" ollama-app \
    && useradd --uid "${APP_UID}" --gid "${APP_GID}" \
       --home-dir /home/ollama --create-home \
       --shell /usr/sbin/nologin ollama-app \
    && mkdir -p /home/ollama/.ollama/models \
    && chown -R "${APP_UID}:${APP_GID}" /home/ollama

ENV HOME=/home/ollama \
    OLLAMA_MODELS=/home/ollama/.ollama/models

USER ${APP_UID}:${APP_GID}
ENTRYPOINT ["/bin/ollama"]
CMD ["serve"]
