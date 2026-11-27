#!/usr/bin/env python3
"""
index_policies.py — Invoke the embedding Lambda to index all six policy documents.
Usage: python scripts/index_policies.py --function-name <prefix>-EmberKitchen-embedding
"""
import argparse
import json
import pathlib
import boto3

POLICY_DIR = pathlib.Path(__file__).parent.parent / "docs" / "policies"

DOCUMENTS = [
    "ember_kitchen_general_info",
    "reservation_policy",
    "dietary_and_allergen_menu",
    "catering_packages_and_pricing",
    "private_dining_and_events_policy",
    "allergy_emergency_procedures",
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--function-name", required=True, help="Embedding Lambda function name")
    parser.add_argument("--region", default="us-east-1")
    args = parser.parse_args()

    client = boto3.client("lambda", region_name=args.region)

    docs = []
    for doc_id in DOCUMENTS:
        path = POLICY_DIR / f"{doc_id}.md"
        if not path.exists():
            print(f"WARNING: {path} not found, skipping")
            continue
        docs.append({"id": doc_id, "text": path.read_text(encoding="utf-8")})

    payload = {"action": "index", "documents": docs}
    print(f"Indexing {len(docs)} documents into Qdrant via {args.function_name}...")

    response = client.invoke(
        FunctionName=args.function_name,
        InvocationType="RequestResponse",
        Payload=json.dumps(payload),
    )
    result = json.loads(response["Payload"].read())
    print("Result:", json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
