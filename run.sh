#!/usr/bin/env bash
# run.sh — Terraform wrapper for Ember Kitchen
# Usage: ./run.sh <command> [env]
#
# Commands:
#   init      terraform init (with optional S3 backend)
#   validate  terraform fmt + validate
#   plan      terraform plan
#   apply     terraform apply
#   destroy   terraform destroy
#   output    terraform output
#   clean     remove .terraform dir and lock file
#
# Environments: demo (default)
#
# Examples:
#   ./run.sh init
#   ./run.sh plan demo
#   ./run.sh apply demo
#   ./run.sh output

set -euo pipefail

COMMAND=${1:-help}
ENV=${2:-demo}

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    TF="terraform"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    echo "Windows OS detected. Using Terraform from other directory. Please ensure the path is correct."
    TF=""
else
    echo "Unsupported OS: $OSTYPE"; exit 1
fi

TERRAFORM_DIR="$(cd "$(dirname "$0")/terraform" && pwd)"
TFVARS_FILE="${TERRAFORM_DIR}/${ENV}.tfvars"

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[run.sh]${NC} $*"; }
ok()   { echo -e "${GREEN}[run.sh]${NC} $*"; }
warn() { echo -e "${YELLOW}[run.sh]${NC} $*"; }
err()  { echo -e "${RED}[run.sh]${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [env]

Commands:
  init      Initialize Terraform (downloads providers)
  validate  Check formatting and validate configuration
  plan      Show execution plan
  apply     Apply changes
  destroy   Destroy all resources (asks for confirmation)
  output    Print Terraform outputs
  clean     Remove .terraform/ and .terraform.lock.hcl

Environments:
  demo      (default) — reads terraform/demo.tfvars if it exists

Environment variables (optional, override tfvars):
  TF_VAR_your_name      Resource name prefix (default: rabindra)
  TF_BACKEND_BUCKET     S3 bucket for remote state
  TF_BACKEND_KEY        State file key
  TF_BACKEND_REGION     S3 bucket region
  TF_BACKEND_TABLE      DynamoDB lock table

Examples:
  ./run.sh init
  ./run.sh plan demo
  ./run.sh apply demo
  ./run.sh output
  TF_VAR_your_name=alice ./run.sh plan
EOF
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────
check_deps() {
  for cmd in aws docker; do
    if ! command -v "$cmd" &>/dev/null; then
      err "$cmd is not installed or not on PATH."
      exit 1
    fi
  done
  if ! "$TF" version &>/dev/null; then
    err "Terraform not found at: $TF"
    exit 1
  fi
}

# ── Write backend.hcl with defaults ──────────────────────────────────────────
write_backend_hcl() {
  cat > "${TERRAFORM_DIR}/backend.hcl" <<EOF
bucket       = "${TF_BACKEND_BUCKET:-ember-kitchen-${ENV}-terraform-state}"
key          = "${ENV}/terraform.tfstate"
region       = "${TF_BACKEND_REGION:-us-east-1}"
use_lockfile = true
EOF
}

# ── Var file arg ──────────────────────────────────────────────────────────────
varfile_arg() {
  if [[ -f "$TFVARS_FILE" ]]; then
    echo "-var-file=${TFVARS_FILE}"
  else
    echo ""
  fi
}

# ── Commands ──────────────────────────────────────────────────────────────────
cmd_init() {
  log "Initialising Terraform (env: ${ENV})"
  write_backend_hcl
  "$TF" -chdir="$TERRAFORM_DIR" init \
    -backend-config="${TERRAFORM_DIR}/backend.hcl" \
    -upgrade
  ok "Init complete."
}

cmd_validate() {
  log "Checking Terraform formatting..."
  "$TF" -chdir="$TERRAFORM_DIR" fmt -check -recursive || {
    warn "Format issues found. Run: terraform -chdir=terraform fmt -recursive"
    exit 1
  }
  log "Validating configuration..."
  "$TF" -chdir="$TERRAFORM_DIR" validate
  ok "Validation passed."
}

cmd_plan() {
  log "Planning (env: ${ENV})"
  # Auto-init if .terraform directory is missing
  if [[ ! -d "${TERRAFORM_DIR}/.terraform" ]]; then
    log "No .terraform directory found — running init first."
    cmd_init
  fi
  # shellcheck disable=SC2046
  "$TF" -chdir="$TERRAFORM_DIR" plan \
    $(varfile_arg) \
    -out="${TERRAFORM_DIR}/tfplan" \
    -input=false
  ok "Plan written to terraform/tfplan"
}

cmd_apply() {
  if [[ -f "${TERRAFORM_DIR}/tfplan" ]]; then
    log "Applying saved plan..."
    "$TF" -chdir="$TERRAFORM_DIR" apply -input=false "${TERRAFORM_DIR}/tfplan"
    rm -f "${TERRAFORM_DIR}/tfplan"
  else
    warn "No saved plan found — running plan + apply."
    # shellcheck disable=SC2046
    "$TF" -chdir="$TERRAFORM_DIR" apply \
      $(varfile_arg) \
      -input=false
  fi
  ok "Apply complete."
}

cmd_destroy() {
  warn "This will DESTROY all resources in the '${ENV}' environment."
  read -r -p "Type 'yes' to confirm: " confirm
  [[ "$confirm" == "yes" ]] || { log "Aborted."; exit 0; }
  # shellcheck disable=SC2046
  "$TF" -chdir="$TERRAFORM_DIR" destroy \
    $(varfile_arg) \
    -input=false
  ok "Destroy complete."
}

cmd_output() {
  "$TF" -chdir="$TERRAFORM_DIR" output
}

cmd_clean() {
  log "Removing .terraform/ and lock file..."
  rm -rf "${TERRAFORM_DIR}/.terraform" "${TERRAFORM_DIR}/.terraform.lock.hcl" "${TERRAFORM_DIR}/backend.hcl"
  ok "Clean complete."
}

# ── Dispatch ──────────────────────────────────────────────────────────────────
case "$COMMAND" in
  init)     check_deps; cmd_init     ;;
  validate) check_deps; cmd_validate ;;
  plan)     check_deps; cmd_plan     ;;
  apply)    check_deps; cmd_apply    ;;
  destroy)  check_deps; cmd_destroy  ;;
  output)   check_deps; cmd_output   ;;
  clean)    cmd_clean                ;;
  help|--help|-h) usage              ;;
  *)
    err "Unknown command: ${COMMAND}"
    echo
    usage
    exit 1
    ;;
esac
