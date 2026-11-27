#!/usr/bin/env bash
# deploy_qdrant.sh — Manage Qdrant vector DB via Docker.
#
# Modes:
#   local   — run Qdrant on this machine using docker-compose (dev/testing)
#   remote  — SSH into the Terraform-provisioned EC2 and manage Qdrant there
#
# Usage:
#   ./scripts/deploy_qdrant.sh local  <start|stop|restart|status|logs>
#   ./scripts/deploy_qdrant.sh remote <start|stop|restart|status|logs> [ec2-ip] [key-pair-path]
#
# Examples:
#   ./scripts/deploy_qdrant.sh local start
#   ./scripts/deploy_qdrant.sh remote start 10.0.1.55 ~/.ssh/Rabindra-keypair-demo.pem
#   ./scripts/deploy_qdrant.sh remote status   # EC2 IP auto-detected via Terraform output
set -euo pipefail

MODE=${1:-local}
ACTION=${2:-start}
QDRANT_PORT_REST=${QDRANT_PORT_REST:-6333}
QDRANT_PORT_GRPC=${QDRANT_PORT_GRPC:-6334}
COMPOSE_FILE="$(dirname "$0")/../docker/qdrant/docker-compose.yml"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { echo "[qdrant] $*"; }
ok()   { echo "[qdrant] ✓ $*"; }
fail() { echo "[qdrant] ✗ $*" >&2; exit 1; }

wait_healthy() {
  local host=$1 port=$2 retries=20
  log "Waiting for Qdrant at ${host}:${port}..."
  for i in $(seq 1 $retries); do
    if curl -sf "http://${host}:${port}/healthz" >/dev/null 2>&1; then
      ok "Qdrant is healthy at http://${host}:${port}"
      curl -s "http://${host}:${port}/collections" | python3 -m json.tool 2>/dev/null || true
      return 0
    fi
    sleep 3
  done
  fail "Qdrant did not become healthy after $((retries * 3))s"
}

# ── Local mode (docker-compose) ───────────────────────────────────────────────

local_start() {
  log "Starting Qdrant locally on ports ${QDRANT_PORT_REST} (REST) / ${QDRANT_PORT_GRPC} (gRPC)..."
  QDRANT_PORT_REST=$QDRANT_PORT_REST QDRANT_PORT_GRPC=$QDRANT_PORT_GRPC \
    docker compose -f "$COMPOSE_FILE" up -d --pull always
  wait_healthy localhost "$QDRANT_PORT_REST"
}

local_stop() {
  log "Stopping local Qdrant..."
  docker compose -f "$COMPOSE_FILE" down
  ok "Stopped."
}

local_restart() {
  local_stop
  local_start
}

local_status() {
  docker compose -f "$COMPOSE_FILE" ps
  echo ""
  curl -sf "http://localhost:${QDRANT_PORT_REST}/collections" | python3 -m json.tool 2>/dev/null \
    || log "Qdrant not reachable at localhost:${QDRANT_PORT_REST}"
}

local_logs() {
  docker compose -f "$COMPOSE_FILE" logs -f --tail=100
}

# ── Remote mode (EC2 via SSH) ─────────────────────────────────────────────────

EC2_IP=${3:-}
KEY_PATH=${4:-}

resolve_ec2_ip() {
  if [[ -z "$EC2_IP" ]]; then
    log "No EC2 IP given — looking up from Terraform output..."
    EC2_IP=$(cd "$(dirname "$0")/../terraform" && \
      terraform output -raw qdrant_private_ip 2>/dev/null || true)
    [[ -z "$EC2_IP" ]] && fail "Could not resolve EC2 IP. Pass it as the 3rd argument."
    log "Found EC2 IP: ${EC2_IP}"
  fi
}

resolve_key() {
  if [[ -z "$KEY_PATH" ]]; then
    KEY_PATH="${HOME}/.ssh/Rabindra-keypair-demo.pem"
  fi
  [[ -f "$KEY_PATH" ]] || fail "Key file not found: ${KEY_PATH}. Pass it as the 4th argument."
}

ssh_run() {
  ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    "ec2-user@${EC2_IP}" "$@"
}

remote_start() {
  resolve_ec2_ip
  resolve_key
  log "Starting Qdrant on EC2 ${EC2_IP}..."
  ssh_run "
    set -e
    sudo systemctl start docker 2>/dev/null || true
    if docker ps -a --format '{{.Names}}' | grep -q '^qdrant$'; then
      docker start qdrant
    else
      docker pull qdrant/qdrant:latest
      docker run -d \
        --name qdrant \
        --restart unless-stopped \
        -p ${QDRANT_PORT_REST}:6333 \
        -p ${QDRANT_PORT_GRPC}:6334 \
        -v /home/ec2-user/qdrant_storage:/qdrant/storage \
        qdrant/qdrant:latest
    fi
  "
  wait_healthy "$EC2_IP" "$QDRANT_PORT_REST"
}

remote_stop() {
  resolve_ec2_ip
  resolve_key
  log "Stopping Qdrant on EC2 ${EC2_IP}..."
  ssh_run "docker stop qdrant && docker rm qdrant" || true
  ok "Stopped."
}

remote_restart() {
  remote_stop
  remote_start
}

remote_status() {
  resolve_ec2_ip
  resolve_key
  log "Status on EC2 ${EC2_IP}:"
  ssh_run "docker ps -f name=qdrant --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
  echo ""
  curl -sf "http://${EC2_IP}:${QDRANT_PORT_REST}/collections" | python3 -m json.tool 2>/dev/null \
    || log "Qdrant not reachable at ${EC2_IP}:${QDRANT_PORT_REST}"
}

remote_logs() {
  resolve_ec2_ip
  resolve_key
  ssh_run "docker logs -f --tail=100 qdrant"
}

# ── Dispatcher ────────────────────────────────────────────────────────────────

case "$MODE" in
  local)
    case "$ACTION" in
      start)   local_start   ;;
      stop)    local_stop    ;;
      restart) local_restart ;;
      status)  local_status  ;;
      logs)    local_logs    ;;
      *) fail "Unknown action '$ACTION'. Use: start|stop|restart|status|logs" ;;
    esac
    ;;
  remote)
    case "$ACTION" in
      start)   remote_start   ;;
      stop)    remote_stop    ;;
      restart) remote_restart ;;
      status)  remote_status  ;;
      logs)    remote_logs    ;;
      *) fail "Unknown action '$ACTION'. Use: start|stop|restart|status|logs" ;;
    esac
    ;;
  *)
    echo "Usage: $0 <local|remote> <start|stop|restart|status|logs> [ec2-ip] [key-path]"
    exit 1
    ;;
esac
