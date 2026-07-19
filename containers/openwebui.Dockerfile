ARG OPEN_WEBUI_VERSION=v0.10.2
FROM ghcr.io/open-webui/open-webui:${OPEN_WEBUI_VERSION}

ARG APP_UID=10001
ARG APP_GID=10001

USER root
RUN groupadd --gid "${APP_GID}" openwebui-app \
    && useradd --uid "${APP_UID}" --gid "${APP_GID}" \
       --home-dir /app/backend/data --no-create-home \
       --shell /usr/sbin/nologin openwebui-app \
    && mkdir -p /app/backend/data /app/backend/open_webui/static \
    && chown -R "${APP_UID}:${APP_GID}" \
       /app/backend/data /app/backend/open_webui/static \
    && chmod -R u+rwX,g+rwX,o-rwx \
       /app/backend/data /app/backend/open_webui/static

ENV HOME=/app/backend/data \
    PYTHONPYCACHEPREFIX=/tmp/pycache

USER ${APP_UID}:${APP_GID}
