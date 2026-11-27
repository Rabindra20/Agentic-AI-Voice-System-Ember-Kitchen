"""
Embedding Lambda — self-hosted sentence-transformers model (BAAI/bge-small-en-v1.5).
Runs as a Lambda container image. Model loads once at cold start.
Supports two actions:
  - index: embed and upsert documents into Qdrant
  - query: embed a query and return top-k results
"""
import json
import os
import uuid

from sentence_transformers import SentenceTransformer
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

QDRANT_HOST     = os.environ.get("QDRANT_ENDPOINT", "localhost")
COLLECTION_NAME = os.environ.get("QDRANT_COLLECTION", "ember_kitchen_policies")
MODEL_NAME      = "BAAI/bge-small-en-v1.5"
VECTOR_DIM      = 384  # bge-small-en-v1.5 output dimension

# Load model once at cold start (cached in /tmp on warm invocations)
_model  = SentenceTransformer(MODEL_NAME)
_qdrant = QdrantClient(url=f"http://{QDRANT_HOST}:6333")


def _ensure_collection():
    existing = [c.name for c in _qdrant.get_collections().collections]
    if COLLECTION_NAME not in existing:
        _qdrant.create_collection(
            collection_name=COLLECTION_NAME,
            vectors_config=VectorParams(size=VECTOR_DIM, distance=Distance.COSINE),
        )


def _index(documents: list[dict]) -> dict:
    """documents: [{"id": "...", "text": "..."}]"""
    _ensure_collection()
    points = [
        PointStruct(
            id=str(uuid.uuid5(uuid.NAMESPACE_DNS, doc["id"])),
            vector=_model.encode(doc["text"]).tolist(),
            payload={"doc_id": doc["id"], "text": doc["text"]},
        )
        for doc in documents
    ]
    _qdrant.upsert(collection_name=COLLECTION_NAME, points=points)
    return {"indexed": len(points)}


def _query(query_text: str, top_k: int = 3) -> dict:
    _ensure_collection()
    results = _qdrant.search(
        collection_name=COLLECTION_NAME,
        query_vector=_model.encode(query_text).tolist(),
        limit=top_k,
    )
    return {
        "results": [
            {
                "doc_id": r.payload.get("doc_id"),
                "score":  r.score,
                "text":   r.payload.get("text", "")[:500],
            }
            for r in results
        ]
    }


def handler(event, _context):
    action = event.get("action", "query")
    if action == "index":
        return _index(event.get("documents", []))
    if action == "query":
        return _query(event.get("query", ""), int(event.get("top_k", 3)))
    return {"error": f"Unknown action: {action}"}
