#!/usr/bin/env python3
"""Punt d'entrada del contenidor litellm-pgvector.

No hi ha migració automàtica en arrancar (a diferència de litellm-database):
cal fer "prisma db push" abans de servir. Fa servir DUES DATABASE_URL
diferents — vegeu els comentaris llargs a litellm-pgvector.Dockerfile per
al perquè exacte (esborrat real de taules d'Open WebUI en un intent
anterior, i per què calen exactament estes dos variants):

- "prisma db push": AMB "?schema=<PG_SCHEMA>" — imprescindible, sense ell
  Prisma assumeix 'public'.
- L'aplicació (uvicorn): SENSE "?schema=" — cada connexió del grup que obri
  Prisma parteix llavors del search_path per defecte del ROL
  ("<PG_SCHEMA>, public", fixat per postgres-init/03-...), en lloc que
  cadascuna torne a fixar-lo a soles NOMÉS amb <PG_SCHEMA> (sense
  'public'), que és el que passa quan "?schema=" viatja en la URL.

Usat només en construcció/arrancada d'esta imatge
(containers/litellm-pgvector.Dockerfile); no és codi vendored del
connector.
"""
import os
import subprocess
import sys
import urllib.parse as u


def build_database_url(*, with_schema: bool) -> str:
    user = u.quote(os.environ["PG_USER"], safe="")
    password = u.quote(os.environ["PG_PASSWORD"], safe="")
    host = os.environ["PG_HOST"]
    port = os.environ["PG_PORT"]
    database = os.environ["PG_DATABASE"]
    url = f"postgresql://{user}:{password}@{host}:{port}/{database}"
    if with_schema:
        schema = u.quote(os.environ["PG_SCHEMA"], safe="")
        url += f"?schema={schema}"
    return url


def main() -> None:
    push_env = {**os.environ, "DATABASE_URL": build_database_url(with_schema=True)}
    result = subprocess.run(
        ["prisma", "db", "push", "--accept-data-loss", "--skip-generate"],
        env=push_env,
    )
    if result.returncode != 0:
        sys.exit(result.returncode)

    os.environ["DATABASE_URL"] = build_database_url(with_schema=False)
    os.execvp("uvicorn", ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"])


if __name__ == "__main__":
    main()
