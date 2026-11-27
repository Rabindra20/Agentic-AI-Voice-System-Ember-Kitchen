#!/usr/bin/env bash
# build_and_push.sh — Build and push both Docker images to ECR.
# ECR repositories are managed by Terraform (modules/ecr). Run terraform apply first.
#
# Usage:
#   ./scripts/build_and_push.sh [prefix] [env] [region]
#
# Defaults:
#   prefix  = "rabindra"     (matches var.your_name in Terraform)
#   env     = "demo"         (matches var.env in Terraform)
#   region  = auto-detected from AWS config, falls back to us-east-1
#
# Account ID is always auto-detected from active AWS credentials.
set -euo pipefail

PREFIX=${1:-rabindra}
ENV=${2:-demo}
REGION=${3:-$(aws configure get region 2>/dev/null || echo "us-east-1")}

# Auto-detect account ID from active credentials
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Repo names must be lowercase — mirrors lower() in modules/ecr/main.tf
AGENT_REPO="${ECR_BASE}/$(echo "${PREFIX}-emberkitchen-${ENV}-agent" | tr '[:upper:]' '[:lower:]')"
# Embedding uses self-hosted sentence-transformers (BAAI/bge-small-en-v1.5) in a container.
# Amazon Titan Embeddings is prohibited — model must be open-source and container-based.
EMBEDDING_REPO="${ECR_BASE}/$(echo "${PREFIX}-emberkitchen-${ENV}-embedding" | tr '[:upper:]' '[:lower:]')"

echo "Account   : ${ACCOUNT_ID}"
echo "Region    : ${REGION}"
echo "Env       : ${ENV}"
echo "Agent     : ${AGENT_REPO}"
echo "Embedding : ${EMBEDDING_REPO}"
echo ""

aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ECR_BASE}"

# ── Agent image (AgentCore Runtime) ───────────────────────────────────────────
docker build -t ember-agent:latest docker/agent/
docker tag  ember-agent:latest "${AGENT_REPO}:latest"
docker push "${AGENT_REPO}:latest"
echo "Pushed: ${AGENT_REPO}:latest"

# ── Embedding image (self-hosted sentence-transformers Lambda container) ───────
docker build -t ember-embedding:latest docker/embedding/
docker tag  ember-embedding:latest "${EMBEDDING_REPO}:latest"
docker push "${EMBEDDING_REPO}:latest"
echo "Pushed: ${EMBEDDING_REPO}:latest"
