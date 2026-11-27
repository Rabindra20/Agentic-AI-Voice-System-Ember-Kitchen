"""
Embedding Lambda — uses Amazon Bedrock Titan Embeddings v2.
Supports two actions:
  - index: embed and upsert documents into Qdrant
  - query: embed a query and return top-k results
Model: amazon.titan-embed-text-v2:0 (1024-dim, AWS-managed, no cold-start model load)
"""
import json
import os
import uuid

import boto3
from qdrant_client import QdrantClient
from qdrant_client.models import Distance, VectorParams, PointStruct

AWS_REGION      = os.environ.get("AWS_REGION", "us-east-1")
QDRANT_HOST     = os.environ.get("QDRANT_ENDPOINT", "localhost")
COLLECTION_NAME = os.environ.get("QDRANT_COLLECTION", "ember_kitchen_policies")
EMBED_MODEL_ID  = os.environ.get("EMBED_MODEL_ID", "amazon.titan-embed-text-v2:0")
VECTOR_DIM      = 1024  # Titan Embeddings v2 default output dimension

bedrock = boto3.client("bedrock-runtime", region_name=AWS_REGION)
qdrant  = QdrantClient(url=f"http://{QDRANT_HOST}:6333")


def _embed(text: str) -> list[float]:
    resp = bedrock.invoke_model(
        modelId=EMBED_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({"inputText": text}),
    )
    return json.loads(resp["body"].read())["embedding"]


def _ensure_collection():
    existing = [c.name for c in qdrant.get_collections().collections]
    if COLLECTION_NAME not in existing:
        qdrant.create_collection(
            collection_name=COLLECTION_NAME,
            vectors_config=VectorParams(size=VECTOR_DIM, distance=Distance.COSINE),
        )


def _index(documents: list[dict]) -> dict:
    """documents: [{"id": "...", "text": "..."}]"""
    _ensure_collection()
    points = [
        PointStruct(
            id=str(uuid.uuid5(uuid.NAMESPACE_DNS, doc["id"])),
            vector=_embed(doc["text"]),
            payload={"doc_id": doc["id"], "text": doc["text"]},
        )
        for doc in documents
    ]
    qdrant.upsert(collection_name=COLLECTION_NAME, points=points)
    return {"indexed": len(points)}


def _query(query_text: str, top_k: int = 3) -> dict:
    _ensure_collection()
    results = qdrant.search(
        collection_name=COLLECTION_NAME,
        query_vector=_embed(query_text),
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
