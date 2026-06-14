#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ─── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }

# ─── Pre-flight checks ───────────────────────────────────────────────
info "Running pre-flight checks..."

# Check docker
if ! command -v docker &>/dev/null; then
  fail "docker is not installed"
  exit 1
fi
ok "docker found: $(docker --version)"

# Check docker compose
if ! docker compose version &>/dev/null; then
  fail "docker compose v2 is not available"
  exit 1
fi
ok "docker compose found: $(docker compose version --short)"

# Check .env file
if [ ! -f "$PROJECT_DIR/.env" ]; then
  fail ".env file not found"
  info "Creating .env from .env.example — please review and edit values"
  cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
  warn "Edit $PROJECT_DIR/.env before continuing (especially RPI4_IP and GF_ADMIN_PASSWORD)"
  exit 1
fi
ok ".env file found"

# Validate required .env variables
# shellcheck source=/dev/null
source "$PROJECT_DIR/.env"
MISSING=0
for VAR in RPI4_IP OC_GO_CC_OPENCODE_URL GF_ADMIN_PASSWORD; do
  VAL="${!VAR:-}"
  if [ -z "$VAL" ] || [ "$VAL" = "REPLACE_WITH_STRONG_PASSWORD" ]; then
    fail "$VAR is not set or still has the placeholder value"
    MISSING=1
  fi
done
if [ "$MISSING" -eq 1 ]; then
  fail "Fix .env and re-run"
  exit 1
fi
ok "required .env variables are set"

# ─── Connectivity check ──────────────────────────────────────────────
info "Checking connectivity to Raspberry Pi 4 at ${RPI4_IP}..."

if ping -c 1 -W 2 "$RPI4_IP" &>/dev/null; then
  ok "RPi4 reachable via ICMP"
else
  warn "RPi4 not responding to ICMP (this may be normal if ICMP is blocked)"
fi

if curl -sf --connect-timeout 5 "http://${RPI4_IP}:8080/health" &>/dev/null; then
  ok "opencode-smart-router /health endpoint is responding"
else
  warn "opencode-smart-router /health at http://${RPI4_IP}:8080/health is not responding"
  warn "Make sure the router is running on RPi4 with listen_addr=0.0.0.0:8080"
fi

# ─── Start services ──────────────────────────────────────────────────
info "Starting Docker Compose services..."
cd "$PROJECT_DIR"
docker compose up -d

# ─── Wait for health ─────────────────────────────────────────────────
info "Waiting for services to become healthy (max 60s)..."

check_health() {
  local name="$1" url="$2" max_wait=60 waited=0
  while [ $waited -lt $max_wait ]; do
    if curl -sf --connect-timeout 2 "$url" &>/dev/null; then
      ok "$name is healthy"
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  fail "$name did not become healthy within ${max_wait}s (url: $url)"
  return 1
}

check_health "oc-go-cc"      "http://localhost:3456/health"  || true
check_health "Prometheus"    "http://localhost:9090/-/ready" || true
check_health "Grafana"       "http://localhost:3000/api/health" || true

# ─── Summary ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  claude-router is running${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}oc-go-cc${NC}       http://localhost:3456/health"
echo -e "  ${CYAN}Prometheus${NC}     http://localhost:9090"
echo -e "  ${CYAN}Grafana${NC}        http://localhost:3000  (admin / ${GF_ADMIN_PASSWORD})"
echo ""
echo -e "  ${CYAN}Smart Router${NC}   http://${RPI4_IP}:8080/health"
echo -e "  ${CYAN}Smart Router${NC}   http://${RPI4_IP}:8080/metrics"
echo -e "  ${CYAN}Smart Router${NC}   http://${RPI4_IP}:8080/admin/stats"
echo ""
echo -e "  ${YELLOW}Claude Code config:${NC}"
echo -e "  ${YELLOW}  export ANTHROPIC_BASE_URL=\"http://127.0.0.1:3456\"${NC}"
echo -e "  ${YELLOW}  export ANTHROPIC_API_KEY=\"dummy\"${NC}"
echo -e "  ${YELLOW}  claude-code${NC}"
echo ""