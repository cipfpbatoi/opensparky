#!/usr/bin/env python3
"""Trossos un fitxer de text, calcula els embeddings amb bge-m3 via LiteLLM i
els insereix per lots en un magatzem de vectors del connector litellm-pgvector.

No hi ha cap ruta que faça açò automàticament: l'API de Fitxers d'OpenAI
(/v1/files) que exposa LiteLLM és per a proveïdors amb Files API nativa
(OpenAI, Azure, Vertex) — el nostre connector pg_vector no en té, només
accepta embeddings ja calculats (vegeu README.md, secció "Magatzem de
vectors de LiteLLM").

Ús:
    ./scripts/litellm-vectorstore-add-file.py <fitxer> <vector_store_id> \
        [--chunk-size 1200] [--overlap 150] [--base-url URL]

Requereix en .env: LITELLM_PGVECTOR_SERVER_API_KEY (per al connector).
Requereix una clau virtual de LiteLLM amb accés a bge-m3, via la variable
d'entorn LITELLM_API_KEY (mai la mestra):

    LITELLM_API_KEY=sk-... ./scripts/litellm-vectorstore-add-file.py prova.txt EL_UUID
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent


def load_dotenv(path: Path) -> dict[str, str]:
    env: dict[str, str] = {}
    if not path.exists():
        return env
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def chunk_text(text: str, chunk_size: int, overlap: int) -> list[str]:
    """Trossos per paràgrafs, ajuntant-los fins a chunk_size caràcters, amb
    solapament entre trossos consecutius perquè el context no es talle just
    al canvi de tros."""
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    if not paragraphs:
        paragraphs = [text.strip()] if text.strip() else []

    chunks: list[str] = []
    current = ""
    for para in paragraphs:
        candidate = f"{current}\n\n{para}" if current else para
        if len(candidate) <= chunk_size or not current:
            current = candidate
        else:
            chunks.append(current)
            tail = current[-overlap:] if overlap > 0 else ""
            current = f"{tail}\n\n{para}" if tail else para
    if current:
        chunks.append(current)

    # Talls durs per a paràgrafs individuals més llargs que chunk_size.
    final_chunks: list[str] = []
    for c in chunks:
        if len(c) <= chunk_size:
            final_chunks.append(c)
            continue
        start = 0
        while start < len(c):
            end = start + chunk_size
            final_chunks.append(c[start:end])
            start = end - overlap if overlap > 0 else end
    return final_chunks


def http_post_json(url: str, headers: dict[str, str], body: dict) -> dict:
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={**headers, "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"ERROR {e.code} cridant {url}:\n{detail}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", type=Path, help="Fitxer de text a indexar")
    parser.add_argument("vector_store_id", help="UUID del magatzem (litellm-pgvector)")
    parser.add_argument("--chunk-size", type=int, default=1200, help="Caràcters per tros (per defecte 1200)")
    parser.add_argument("--overlap", type=int, default=150, help="Solapament en caràcters entre trossos (per defecte 150)")
    parser.add_argument("--batch-size", type=int, default=20, help="Trossos per crida d'inserció per lots (per defecte 20)")
    args = parser.parse_args()

    env = {**load_dotenv(PROJECT_DIR / ".env"), **os.environ}

    litellm_api_key = env.get("LITELLM_API_KEY")
    if not litellm_api_key:
        raise SystemExit(
            "ERROR: defineix LITELLM_API_KEY amb una clau virtual amb accés a bge-m3 "
            "(mai la mestra). Exemple:\n"
            "  LITELLM_API_KEY=sk-... ./scripts/litellm-vectorstore-add-file.py fitxer.txt UUID"
        )
    server_api_key = env.get("LITELLM_PGVECTOR_SERVER_API_KEY")
    if not server_api_key:
        raise SystemExit("ERROR: falta LITELLM_PGVECTOR_SERVER_API_KEY en .env")

    litellm_port = env.get("LITELLM_PORT", "4000")
    pgvector_port = env.get("LITELLM_PGVECTOR_PORT", "8010")
    litellm_url = env.get("LITELLM_API_BASE_URL", f"http://127.0.0.1:{litellm_port}")
    pgvector_url = f"http://127.0.0.1:{pgvector_port}"

    if not args.file.exists():
        raise SystemExit(f"ERROR: no existeix {args.file}")
    text = args.file.read_text(encoding="utf-8", errors="replace")

    chunks = chunk_text(text, args.chunk_size, args.overlap)
    if not chunks:
        raise SystemExit("ERROR: el fitxer no té contingut de text per indexar")
    print(f"{len(chunks)} trossos de fins a {args.chunk_size} caràcters (solapament {args.overlap})", file=sys.stderr)

    embeddings_payload = []
    for i, chunk in enumerate(chunks, start=1):
        print(f"  embedding {i}/{len(chunks)}...", file=sys.stderr)
        resp = http_post_json(
            f"{litellm_url}/v1/embeddings",
            {"Authorization": f"Bearer {litellm_api_key}"},
            {"model": "bge-m3", "input": chunk},
        )
        vector = resp["data"][0]["embedding"]
        embeddings_payload.append(
            {"content": chunk, "embedding": vector, "metadata": {"filename": args.file.name, "chunk": i}}
        )

    inserted = 0
    for start in range(0, len(embeddings_payload), args.batch_size):
        batch = embeddings_payload[start : start + args.batch_size]
        http_post_json(
            f"{pgvector_url}/v1/vector_stores/{args.vector_store_id}/embeddings/batch",
            {"Authorization": f"Bearer {server_api_key}"},
            {"embeddings": batch},
        )
        inserted += len(batch)
        print(f"  inserits {inserted}/{len(embeddings_payload)}...", file=sys.stderr)

    print(f"Fet: {inserted} trossos de {args.file.name} indexats en {args.vector_store_id}", file=sys.stderr)


if __name__ == "__main__":
    main()
