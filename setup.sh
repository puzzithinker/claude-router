#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║                                                       ║"
echo "  ║   ██████╗██╗      █████╗ ██╗   ██╗██████╗ ███████╗    ║"
echo "  ║  ██╔════╝██║     ██╔══██╗██║   ██║██╔══██╗██╔════╝    ║"
echo "  ║  ██║     ██║     ███████║██║   ██║██║  ██║█████╗      ║"
echo "  ║  ██║     ██║     ██╔══██║██║   ██║██║  ██║██╔══╝      ║"
echo "  ║  ╚██████╗███████╗██║  ██║╚██████╔╝██████╔╝███████╗    ║"
echo "  ║   ╚═════╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝    ║"
echo "  ║                  Router for Claude Code                ║"
echo "  ║                                                       ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo ""
echo "============================================="
echo " One-time setup for Ubuntu host"
echo "============================================="
echo ""

# ─── [1/8] Prerequisites ──────────────────────────────────────────────
echo "[1/8] Checking prerequisites..."

for cmd in docker git curl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "  ERROR: $cmd is not installed."
        echo "  Install it with: sudo apt-get install -y $cmd"
        exit 1
    fi
done

if ! docker compose version &>/dev/null; then
    echo "  ERROR: docker compose v2 is not available."
    echo "  Install it with: sudo apt-get install -y docker-compose-plugin"
    exit 1
fi

if groups | grep -q docker; then
    echo "  Docker:     OK"
else
    echo "  WARNING: User is not in the 'docker' group."
    echo "  Run: sudo usermod -aG docker $USER && newgrp docker"
    echo "  Then re-run this script."
    exit 1
fi

echo "  Git:        OK"
echo "  Docker:     OK"
echo "  Compose:    OK"
echo "  curl:       OK"

# ─── Clone oc-go-cc ──────────────────────────────────────────────────
OC_GO_CC_DIR="${SCRIPT_DIR}/oc-go-cc"

if [ ! -d "$OC_GO_CC_DIR" ]; then
    echo ""
    echo "  Cloning oc-go-cc repository..."
    git clone https://github.com/samueltuyizere/oc-go-cc.git "$OC_GO_CC_DIR"
    echo "  ✅ Cloned to ${OC_GO_CC_DIR}"
else
    echo ""
    echo "  oc-go-cc repository already exists, pulling latest..."
    git -C "$OC_GO_CC_DIR" pull || true
fi

# ─── [2/8] Configuration ─────────────────────────────────────────────
echo ""
echo "[2/8] Setting up configuration..."

ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"

if [ ! -f "$ENV_FILE" ]; then
    echo "  Creating .env from .env.example..."

    # Ask for RPi4 IP
    echo ""
    echo "  You need the IP address of your Raspberry Pi 4 running opencode-smart-router."
    echo -n "  RPi4 IP address [192.168.50.150]: "
    read -r RPI4_IP
    RPI4_IP="${RPI4_IP:-192.168.50.150}"

    # Ask for Grafana password
    echo ""
    echo "  Set a Grafana admin password (leave empty for 'changeme')."
    echo -n "  Grafana password: "
    read -r GRAFANA_PASS
    GRAFANA_PASS="${GRAFANA_PASS:-changeme}"

    # Generate .env from template
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    sed -i "s|^RPI4_IP=.*|RPI4_IP=${RPI4_IP}|" "$ENV_FILE"
    sed -i "s|^OC_GO_CC_OPENCODE_URL=.*|OC_GO_CC_OPENCODE_URL=http://${RPI4_IP}:8080/v1|" "$ENV_FILE"
    sed -i "s|^GF_ADMIN_PASSWORD=.*|GF_ADMIN_PASSWORD=${GRAFANA_PASS}|" "$ENV_FILE"

    echo "  Written: .env"
else
    echo "  .env already exists, keeping current values."
fi

# Validate required vars
# shellcheck disable=SC2046
export $(grep -v '^#' "$ENV_FILE" | grep -v '^$' | xargs)

if [ -z "${RPI4_IP:-}" ]; then
    echo "  ERROR: RPI4_IP is not set in .env"
    exit 1
fi

echo "  RPi4 IP:    ${RPI4_IP}"
echo "  Upstream:   http://${RPI4_IP}:8080/v1"

# ─── [3/8] Prometheus ────────────────────────────────────────────────
echo ""
echo "[3/8] Creating Prometheus configuration..."

mkdir -p "${SCRIPT_DIR}/prometheus"

if [ ! -f "${SCRIPT_DIR}/prometheus/prometheus.yml" ]; then
    cat > "${SCRIPT_DIR}/prometheus/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'claude-router'

rule_files:
  - "alert_rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'oc-go-cc'
    scrape_interval: 30s
    static_configs:
      - targets: ['oc-go-cc:3456']
        labels:
          service: 'oc-go-cc'
          role: 'format-translator'

  - job_name: 'node-exporter'
    scrape_interval: 15s
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          host: 'ubuntu'

  - job_name: 'cadvisor'
    scrape_interval: 15s
    static_configs:
      - targets: ['cadvisor:8080']
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: "container_fs_(reads|writes)_(bytes|completed)_total"
        action: drop
      - source_labels: [container_label_com_docker_compose_service]
        target_label: compose_service

  - job_name: 'rpi4-opencode-router'
    scrape_interval: 15s
    static_configs:
      - targets: ['${RPI4_IP}:8080']
        labels:
          host: 'rpi4'
          service: 'opencode-smart-router'
          role: 'key-router'
EOF
    echo "  Written: prometheus/prometheus.yml"
else
    echo "  prometheus/prometheus.yml already exists, keeping current values."
fi

if [ ! -f "${SCRIPT_DIR}/prometheus/alert_rules.yml" ]; then
    cat > "${SCRIPT_DIR}/prometheus/alert_rules.yml" << 'EOF'
groups:
  - name: opencode-router
    rules:
      - alert: AllKeysDown
        expr: sum(opencode_router_key_healthy) == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "All API keys are down"
          description: "No healthy keys available on the smart-router."

      - alert: HighErrorRate
        expr: |
          sum(rate(opencode_router_requests_total{status_group=~"4xx|5xx"}[5m]))
          /
          sum(rate(opencode_router_requests_total[5m]))
          > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Error rate above 10%"
          description: "More than 10% of smart-router requests are returning errors."

      - alert: KeyDisabled
        expr: opencode_router_key_healthy == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Key {{ $labels.key }} is disabled or in cooldown"

      - alert: HighLatency
        expr: |
          histogram_quantile(0.95, sum(rate(opencode_router_request_duration_seconds_bucket[5m])) by (le))
          > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "P95 latency above 5 seconds"

  - name: oc-go-cc
    rules:
      - alert: OCGoCCDown
        expr: up{job="oc-go-cc"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "oc-go-cc is down"
          description: "The format translator proxy has been unreachable for more than 2 minutes."

      - alert: SmartRouterUnreachable
        expr: up{job="rpi4-opencode-router"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "opencode-smart-router on RPi4 is unreachable"
          description: "Prometheus cannot scrape metrics from the smart-router."
EOF
    echo "  Written: prometheus/alert_rules.yml"
else
    echo "  prometheus/alert_rules.yml already exists, keeping current values."
fi

# ─── [4/8] Grafana provisioning ───────────────────────────────────────
echo ""
echo "[4/8] Creating Grafana provisioning..."

mkdir -p "${SCRIPT_DIR}/grafana/provisioning/datasources"
mkdir -p "${SCRIPT_DIR}/grafana/provisioning/dashboards"
mkdir -p "${SCRIPT_DIR}/grafana/dashboards"

if [ ! -f "${SCRIPT_DIR}/grafana/provisioning/datasources/prometheus.yml" ]; then
    cat > "${SCRIPT_DIR}/grafana/provisioning/datasources/prometheus.yml" << 'EOF'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: "15s"
EOF
    echo "  Written: grafana/provisioning/datasources/prometheus.yml"
else
    echo "  grafana/provisioning/datasources/prometheus.yml already exists."
fi

if [ ! -f "${SCRIPT_DIR}/grafana/provisioning/dashboards/dashboards.yml" ]; then
    cat > "${SCRIPT_DIR}/grafana/provisioning/dashboards/dashboards.yml" << 'EOF'
apiVersion: 1
providers:
  - name: "default"
    orgId: 1
    folder: ""
    type: file
    disableDeletion: false
    editable: true
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
EOF
    echo "  Written: grafana/provisioning/dashboards/dashboards.yml"
else
    echo "  grafana/provisioning/dashboards/dashboards.yml already exists."
fi

# Dashboard JSON — always overwrite to keep up to date
cat > "${SCRIPT_DIR}/grafana/dashboards/opencode-router-overview.json" << 'DASHBOARD'
{
  "annotations": {"list": [{"builtIn": 1,"datasource": {"type": "grafana","uid": "-- Grafana --"},"enable": true,"hide": true,"iconColor": "rgba(0, 211, 255, 1)","name": "Annotations & Alerts","type": "dashboard"}]},
  "description": "Monitors opencode-smart-router (RPi4) and oc-go-cc format translator (Ubuntu)",
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 1,
  "id": null,
  "links": [],
  "panels": [
    {
      "title": "Request Rate",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
      "id": 1,
      "targets": [{"expr": "sum(rate(opencode_router_requests_total[5m]))","legendFormat": "requests/sec"}],
      "fieldConfig": {"defaults": {"unit": "reqps","custom": {"drawStyle": "line","lineInterpolation": "smooth"}}}
    },
    {
      "title": "Success Rate",
      "type": "stat",
      "gridPos": {"h": 8, "w": 6, "x": 12, "y": 0},
      "id": 2,
      "targets": [{"expr": "sum(rate(opencode_router_requests_total{status_group=\"2xx\"}[5m])) / sum(rate(opencode_router_requests_total[5m]))","legendFormat": "success rate"}],
      "fieldConfig": {"defaults": {"unit": "percentunit","thresholds": {"mode": "absolute","steps": [{"value": null,"color": "red"},{"value": 0.9,"color": "yellow"},{"value": 0.95,"color": "green"}]}}}
    },
    {
      "title": "Key Health",
      "type": "stat",
      "gridPos": {"h": 8, "w": 6, "x": 18, "y": 0},
      "id": 3,
      "targets": [{"expr": "opencode_router_key_healthy","legendFormat": "{{key}}"}],
      "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute","steps": [{"value": null,"color": "red"},{"value": 1,"color": "green"}]},"mappings": [{"type": "value","options": {"0": {"text": "DOWN","color": "red"},"1": {"text": "UP","color": "green"}}}]}}
    },
    {
      "title": "Latency P50 / P95 / P99",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "id": 4,
      "targets": [
        {"expr": "histogram_quantile(0.5, sum(rate(opencode_router_request_duration_seconds_bucket[5m])) by (le))","legendFormat": "p50"},
        {"expr": "histogram_quantile(0.95, sum(rate(opencode_router_request_duration_seconds_bucket[5m])) by (le))","legendFormat": "p95"},
        {"expr": "histogram_quantile(0.99, sum(rate(opencode_router_request_duration_seconds_bucket[5m])) by (le))","legendFormat": "p99"}
      ],
      "fieldConfig": {"defaults": {"unit": "s","custom": {"drawStyle": "line","lineInterpolation": "smooth"}}}
    },
    {
      "title": "Requests by Status",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "id": 5,
      "targets": [{"expr": "sum by (status_group) (rate(opencode_router_requests_total[5m]))","legendFormat": "{{status_group}}"}],
      "fieldConfig": {"defaults": {"custom": {"drawStyle": "line","fillOpacity": 30,"stacking": {"mode": "normal"}}}}
    },
    {
      "title": "Key Usage Over Time",
      "type": "timeseries",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
      "id": 6,
      "targets": [{"expr": "sum by (key) (rate(opencode_router_key_usage_total[5m]))","legendFormat": "{{key}}"}],
      "fieldConfig": {"defaults": {"unit": "reqps","custom": {"drawStyle": "line","lineInterpolation": "smooth"}}}
    },
    {
      "title": "Service Status",
      "type": "stat",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
      "id": 7,
      "targets": [
        {"expr": "up{job=\"rpi4-opencode-router\"}","legendFormat": "Smart Router (RPi4)"},
        {"expr": "up{job=\"oc-go-cc\"}","legendFormat": "oc-go-cc (Ubuntu)"}
      ],
      "fieldConfig": {"defaults": {"thresholds": {"mode": "absolute","steps": [{"value": null,"color": "red"},{"value": 1,"color": "green"}]},"mappings": [{"type": "value","options": {"0": {"text": "DOWN","color": "red"},"1": {"text": "UP","color": "green"}}}]}}
    }
  ],
  "refresh": "10s",
  "schemaVersion": 39,
  "tags": ["opencode","proxy","claude-router"],
  "templating": {"list": []},
  "time": {"from": "now-1h","to": "now"},
  "title": "Claude Router Overview",
  "uid": "claude-router-overview"
}
DASHBOARD

echo "  Written: grafana dashboards"

# ─── [5/8] Connectivity ───────────────────────────────────────────────
echo ""
echo "[5/8] Checking RPi4 connectivity..."

if ping -c 1 -W 2 "$RPI4_IP" &>/dev/null; then
    echo "  ✅ RPi4 at ${RPI4_IP} is reachable via ICMP"
else
    echo "  ⚠️  RPi4 not responding to ICMP (may be normal if ICMP is blocked)"
fi

if curl -sf --connect-timeout 5 "http://${RPI4_IP}:8080/health" &>/dev/null; then
    echo "  ✅ opencode-smart-router at http://${RPI4_IP}:8080/health is responding"
else
    echo "  ⚠️  opencode-smart-router at http://${RPI4_IP}:8080/health is not responding"
    echo "     Make sure the router is running on RPi4 with:"
    echo "       listen_addr: \"0.0.0.0:8080\""
    echo "       enable_prometheus: true"
    echo ""
    echo -n "  Continue anyway? [y/N]: "
    read -r CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        echo "  Aborted."
        exit 1
    fi
fi

# ─── [6/8] Build & start ──────────────────────────────────────────────
echo ""
echo "[6/8] Building oc-go-cc and pulling images..."

docker compose build oc-go-cc 2>&1 | tail -5
docker compose pull 2>&1 | tail -5

echo ""
echo "[7/8] Starting services..."

docker compose down 2>/dev/null || true
docker compose up -d

# ─── [8/8] Verify ────────────────────────────────────────────────────
echo ""
echo "[8/8] Waiting for services to start..."
echo ""

MAX_WAIT=60

check_service() {
    local name="$1" url="$2"
    local waited=0
    while [ $waited -lt $MAX_WAIT ]; do
        if curl -sf --connect-timeout 2 "$url" &>/dev/null; then
            echo "  ✅ $name is healthy"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    echo "  ❌ $name did not become healthy within ${MAX_WAIT}s"
    return 1
}

check_service "oc-go-cc"    "http://localhost:3456/health"
check_service "Prometheus"  "http://localhost:9090/-/ready"
check_service "Grafana"     "http://localhost:3000/api/health"

echo ""
echo "============================================="
echo " Setup Complete!"
echo "============================================="
echo ""
echo " Endpoints:"
echo ""
echo "   oc-go-cc:      http://localhost:3456/health"
echo "   Smart Router:  http://${RPI4_IP}:8080/health"
echo "   Smart Router:  http://${RPI4_IP}:8080/metrics"
echo "   Smart Router:  http://${RPI4_IP}:8080/admin/stats"
echo "   Prometheus:    http://localhost:9090"
echo "   Grafana:       http://localhost:3000"
echo ""
echo " Grafana login:"
echo "   Username: ${GF_ADMIN_USER:-admin}"
echo "   Password: ${GF_ADMIN_PASSWORD:-changeme}"
echo ""
echo " The 'Claude Router Overview' dashboard is auto-provisioned."
echo " Find it in Grafana → Dashboards."
echo ""
echo " Claude Code config:"
echo "   export ANTHROPIC_BASE_URL=\"http://127.0.0.1:3456\""
echo "   export ANTHROPIC_API_KEY=\"dummy\""
echo "   claude-code"
echo ""
echo " Useful commands:"
echo "   docker compose logs -f                  Follow all logs"
echo "   docker compose logs oc-go-cc            oc-go-cc logs only"
echo "   docker compose restart                  Restart all services"
echo "   docker compose down                     Stop all services"
echo "   docker compose up -d                    Start all services"
echo "   ./scripts/healthcheck.sh               Check all service health"
echo ""