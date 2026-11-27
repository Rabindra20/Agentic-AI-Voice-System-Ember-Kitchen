#!/bin/bash
# create_tf_backend.sh — Create the S3 bucket for Terraform remote state.
# Run this once before the first terraform init.
# Usage: ./scripts/create_tf_backend.sh [env] [region]

set -e

ENV_NAME=${1:-demo}
REGION=${2:-us-east-1}
BUCKET="ember-kitchen-${ENV_NAME}-terraform-state"

echo "Creating Terraform state bucket: ${BUCKET} in ${REGION}"

# Create bucket (us-east-1 does not accept a LocationConstraint)
if [[ "$REGION" == "us-east-1" ]]; then
  aws s3api create-bucket \
    --bucket "${BUCKET}" \
    --region "${REGION}"
else
  aws s3api create-bucket \
    --bucket "${BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
fi

# Enable versioning (required for S3 native locking)
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

# Block all public access
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

echo ""
echo "Done. Bucket: ${BUCKET}"
echo "Run: ./run.sh init ${ENV_NAME}"
