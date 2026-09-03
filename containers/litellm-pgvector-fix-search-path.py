#!/usr/bin/env python3
"""Patch litellm-pgvector's main.py: right after `await db.connect()`, widen
the session's search_path to include 'public' (where the pgvector extension
lives) alongside the connector's own isolated schema (PG_SCHEMA env var).

Without this, DATABASE_URL's "?schema=" query param restricts the whole
connection's search_path to only the connector's own schema — needed so
"prisma db push" never touches unrelated tables (see the incident note in
litellm-pgvector.Dockerfile), but it also breaks the app's own raw SQL,
which casts values with an unqualified "::vector" and can no longer find
that type.

Used at Docker build time only (containers/litellm-pgvector.Dockerfile);
not part of the vendored upstream source.
"""
import sys

path = sys.argv[1]
anchor = "    await db.connect()\n"
patch = (
    "    await db.connect()\n"
    "    _schema = os.environ.get('PG_SCHEMA', 'litellm_pgvector')\n"
    "    await db.execute_raw('SET search_path TO \"' + _schema + '\", public')\n"
)

src = open(path).read()
count = src.count(anchor)
if count != 1:
    raise SystemExit(
        f"expected exactly one '{anchor.strip()}' in {path}, found {count} "
        "(upstream source changed? adjust this patch)"
    )
open(path, "w").write(src.replace(anchor, patch, 1))
