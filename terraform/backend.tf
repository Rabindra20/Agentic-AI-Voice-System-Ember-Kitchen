terraform {
  backend "s3" {
    # Configure via -backend-config flags (run.sh generates backend.hcl) or CI secrets.
    # Required:
    #   TF_BACKEND_BUCKET  — S3 bucket name (versioning must be enabled)
    #   TF_BACKEND_KEY     — state file key (e.g. demo/terraform.tfstate)
    #   TF_BACKEND_REGION  — bucket region
    # State locking uses S3 native locking (use_lockfile = true, requires Terraform >= 1.10).
    #
    # Create the bucket once before first deploy:
    #   aws s3api create-bucket --bucket <bucket> --region us-east-1
    #   aws s3api put-bucket-versioning --bucket <bucket> \
    #     --versioning-configuration Status=Enabled
  }
}
