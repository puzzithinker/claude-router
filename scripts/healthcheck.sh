#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ─── Colors ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

check() {
  local name="$1" url="$2" expected_status="${3:-200}"
  local status result

  status=$(curl -sf -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null) && result=0 || result=1

  if [ $result -eq 0 ] && [ "$status" = "$expected_status" ]; then
    echo -e "  ${GREEN}✓${NC} ${name} ${CYAN}${url}${NC} — HTTP ${status}"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} ${name} ${CYAN}${url}${NC} — HTTP ${status:-unreachable}"
    FAIL=$((FAIL + 1))
  fi
}

# ─── Load config ─────────────────────────────────────────────────────
if [ -f "$PROJECT_DIR/.env" ]; then
  # shellcheck disable=SC2046
  export $(grep -v '^#' "$PROJECT_DIR/.env" | grep -v '^$' | xargs)
fi

RPI4_IP="${RPI4_IP:-192.168.50.150}"
ADMIN_USER="${OC_GO_CC_ADMIN_USER:-admin}"
ADMIN_PASS="${OC_GO_CC_ADMIN_PASS:-}"

echo ""
echo "  claude-router health check"
echo "  ════════════════════════════"
echo ""

echo "  Ubuntu (local docker services):"
echo ""
check "oc-go-cc       " "http://localhost:3456/health"
check "Prometheus     " "http://localhost:9090/-/ready"
check "Grafana        " "http://localhost:3000/api/health"
check "Node Exporter  " "http://localhost:9100/metrics"
check "cAdvisor       " "http://localhost:8082/healthz"

echo ""
echo "  Raspberry Pi 4 (remote):"
echo ""
check "Smart Router /health" "http://${RPI4_IP}:8080/health"
check "Smart Router /metrics" "http://${RPI4_IP}:8080/metrics"

# Check admin stats if password is set
if [ -n "$ADMIN_PASS" ]; then
  check "Smart Router /admin/stats" "http://${ADMIN_USER}:${ADMIN_PASS}@${RPI4_IP}:8080/admin/stats"
fi

echo ""
echo "  ════════════════════════════"
echo -e "  ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}"
echo ""

if [ $FAIL -gt 0 ]; then
  exit 1
fi
exit 0