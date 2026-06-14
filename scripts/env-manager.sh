#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
EXAMPLE_FILE="$PROJECT_DIR/.env.example"

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

usage() {
  echo ""
  echo -e "${BOLD}Usage:${NC} $(basename "$0") <command>"
  echo ""
  echo "Commands:"
  echo "  init      Create .env from .env.example with interactive prompts"
  echo "  show      Display current configuration (secrets masked)"
  echo "  update    Update an individual variable"
  echo "  validate  Check required variables are set and non-empty"
  echo ""
}

# ─── init ─────────────────────────────────────────────────────────────
cmd_init() {
  if [ -f "$ENV_FILE" ]; then
    warn ".env already exists. Back up and re-init? [y/N]"
    read -r answer
    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
      info "Aborted."
      exit 0
    fi
    mv "$ENV_FILE" "${ENV_FILE}.bak.$(date +%s)"
    ok "Backed up existing .env"
  fi

  cp "$EXAMPLE_FILE" "$ENV_FILE"
  ok "Created .env from .env.example"

  echo ""
  info "Configure the following values:"
  echo ""

  # RPI4_IP
  read -rp "RPI4 IP address [192.168.50.150]: " rpi_ip
  rpi_ip="${rpi_ip:-192.168.50.150}"
  sed -i "s/^RPI4_IP=.*/RPI4_IP=${rpi_ip}/" "$ENV_FILE"

  # Automatically derive OC_GO_CC_OPENCODE_URL
  sed -i "s|^OC_GO_CC_OPENCODE_URL=.*|OC_GO_CC_OPENCODE_URL=http://${rpi_ip}:8080/v1|" "$ENV_FILE"

  # Grafana password
  read -rp "Grafana admin password [changeme]: " gf_pass
  gf_pass="${gf_pass:-changeme}"
  sed -i "s/^GF_ADMIN_PASSWORD=.*/GF_ADMIN_PASSWORD=${gf_pass}/" "$ENV_FILE"

  echo ""
  ok "Configuration written to .env"
  info "Edit $ENV_FILE manually for advanced options (model overrides, log level, etc.)"
}

# ─── show ──────────────────────────────────────────────────────────────
cmd_show() {
  if [ ! -f "$ENV_FILE" ]; then
    fail ".env not found. Run '$(basename "$0") init' first."
    exit 1
  fi

  echo ""
  echo -e "  ${BOLD}Current .env configuration${NC}"
  echo "  ════════════════════════════"
  echo ""

  while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ ]] && continue
    [[ -z "$key" ]] && continue
    # Mask secrets
    case "$key" in
      GF_ADMIN_PASSWORD)
        if [ ${#value} -gt 4 ]; then
          masked="${value:0:2}***${value: -2}"
        else
          masked="****"
        fi
        echo -e "  ${CYAN}${key}${NC}=${masked}"
        ;;
      OC_GO_CC_API_KEY)
        echo -e "  ${CYAN}${key}${NC}=${value}"
        ;;
      *)
        echo -e "  ${CYAN}${key}${NC}=${value}"
        ;;
    esac
  done < <(grep -v '^#' "$ENV_FILE" | grep -v '^$')

  echo ""
}

# ─── update ────────────────────────────────────────────────────────────
cmd_update() {
  if [ ! -f "$ENV_FILE" ]; then
    fail ".env not found. Run '$(basename "$0") init' first."
    exit 1
  fi

  local key="${1:-}"
  local value="${2:-}"

  if [ -z "$key" ]; then
    echo -e "  ${BOLD}Available keys:${NC}"
    grep -v '^#' "$ENV_FILE" | grep -v '^$' | cut -d= -f1 | sed 's/^/  /'
    echo ""
    read -rp "Key to update: " key
  fi

  if [ -z "$value" ]; then
    read -rp "New value for ${key}: " value
  fi

  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
    ok "Updated ${key}"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
    ok "Added ${key}"
  fi

  # If RPI4_IP changed, also update OC_GO_CC_OPENCODE_URL
  if [ "$key" = "RPI4_IP" ]; then
    sed -i "s|^OC_GO_CC_OPENCODE_URL=.*|OC_GO_CC_OPENCODE_URL=http://${value}:8080/v1|" "$ENV_FILE"
    ok "Also updated OC_GO_CC_OPENCODE_URL"
  fi
}

# ─── validate ──────────────────────────────────────────────────────────
cmd_validate() {
  if [ ! -f "$ENV_FILE" ]; then
    fail ".env not found. Run '$(basename "$0") init' first."
    exit 1
  fi

  # shellcheck disable=SC2046
  export $(grep -v '^#' "$ENV_FILE" | grep -v '^$' | xargs)

  ERRORS=0

  : "${RPI4_IP:?RPI4_IP is not set}" || { fail "RPI4_IP is not set"; ERRORS=$((ERRORS+1)); }
  : "${OC_GO_CC_OPENCODE_URL:?OC_GO_CC_OPENCODE_URL is not set}" || { fail "OC_GO_CC_OPENCODE_URL is not set"; ERRORS=$((ERRORS+1)); }
  : "${GF_ADMIN_PASSWORD:?GF_ADMIN_PASSWORD is not set}" || { fail "GF_ADMIN_PASSWORD is not set"; ERRORS=$((ERRORS+1)); }

  if [ "${GF_ADMIN_PASSWORD:-}" = "changeme" ]; then
    warn "GF_ADMIN_PASSWORD is still set to the default 'changeme'"
  fi

  if [ "${GF_ADMIN_PASSWORD:-}" = "REPLACE_WITH_STRONG_PASSWORD" ]; then
    fail "GF_ADMIN_PASSWORD still has the placeholder value"
    ERRORS=$((ERRORS+1))
  fi

  if [ "${OC_GO_CC_API_KEY:-}" != "dummy" ]; then
    warn "OC_GO_CC_API_KEY is set to a real key — the smart-router should handle key rotation"
  fi

  # Check RPi4 connectivity
  if ping -c 1 -W 2 "${RPI4_IP}" &>/dev/null; then
    ok "RPi4 at ${RPI4_IP} is reachable"
    if curl -sf --connect-timeout 5 "http://${RPI4_IP}:8080/health" &>/dev/null; then
      ok "opencode-smart-router /health is responding"
    else
      warn "opencode-smart-router at http://${RPI4_IP}:8080/health is not responding"
    fi
  else
    warn "RPi4 at ${RPI4_IP} is not reachable via ICMP"
  fi

  echo ""
  if [ $ERRORS -eq 0 ]; then
    ok "Validation passed"
    exit 0
  else
    fail "Validation failed with ${ERRORS} error(s)"
    exit 1
  fi
}

# ─── Main ──────────────────────────────────────────────────────────────
COMMAND="${1:-}"

case "$COMMAND" in
  init)     cmd_init ;;
  show)     cmd_show ;;
  update)   cmd_update "${2:-}" "${3:-}" ;;
  validate) cmd_validate ;;
  *)        usage; exit 1 ;;
esac