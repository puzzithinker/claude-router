# claude-router

Docker Compose stack that connects Claude Code to [opencode-smart-router](https://github.com/puzzithinker/opencode-smart-router) via [oc-go-cc](https://github.com/samueltuyizere/oc-go-cc), with built-in Prometheus + Grafana monitoring.

## Architecture

```
Claude Code (Ubuntu)
  │  ANTHROPIC_BASE_URL=http://127.0.0.1:3456
  │  ANTHROPIC_API_KEY=dummy
  ▼
oc-go-cc (Docker, port 3456)
  │  Translates Anthropic API → OpenAI Chat Completions format
  │  OC_GO_CC_OPENCODE_URL=http://<RPI4_IP>:8080/v1
  ▼
opencode-smart-router (RPi 4, port 8080)
  │  Rotates API keys with round_robin / least_used strategy
  │  Transparent retry on 429, 401, 403
  │  /health /metrics /admin/stats
  ▼
OpenCode Go API
```

## Prerequisites

- Docker Compose v2 on Ubuntu
- Raspberry Pi 4 running [opencode-smart-router](https://github.com/puzzithinker/opencode-smart-router) on port 8080
- Network connectivity between Ubuntu and RPi 4 (same LAN)

## Quick Start

```bash
cd ~/claude-router

# 1. Configure environment
./scripts/env-manager.sh init

# 2. Start all services
./scripts/start.sh

# 3. Set Claude Code environment variables
export ANTHROPIC_BASE_URL="http://127.0.0.1:3456"
export ANTHROPIC_API_KEY="dummy"

# 4. Launch Claude Code
claude-code
```

## Configuration

### .env

All settings live in `.env` (never committed to git). Use `./scripts/env-manager.sh` to manage it:

| Command | Description |
|---------|-------------|
| `./scripts/env-manager.sh init` | Create `.env` from template with interactive prompts |
| `./scripts/env-manager.sh show` | Display current config (secrets masked) |
| `./scripts/env-manager.sh update KEY VALUE` | Update a single variable |
| `./scripts/env-manager.sh validate` | Check all required variables and RPi 4 connectivity |

### Key Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RPI4_IP` | `192.168.50.150` | Raspberry Pi 4 IP address |
| `OC_GO_CC_API_KEY` | `dummy` | API key for upstream (smart-router handles real keys) |
| `OC_GO_CC_OPENCODE_URL` | `http://${RPI4_IP}:8080/v1` | Smart-router upstream URL |
| `GF_ADMIN_PASSWORD` | `changeme` | Grafana admin password (change this!) |
| `PROMETHEUS_RETENTION` | `30d` | Prometheus data retention |

### oc-go-cc-config.json

Custom model routing configuration. Edit this file to change which OpenCode Go models handle different Claude Code request types:

- **default**: kimi-k2.6 (general purpose)
- **background**: qwen3.5-plus (file reads, grep, ls)
- **think**: glm-5.1 (complex reasoning, architecture)
- **long_context**: minimax-m2.7 (>80K tokens)
- **fast**: qwen3.6-plus (quick responses)

See [oc-go-cc documentation](https://github.com/samueltuyizere/oc-go-cc) for all model options.

## Services

| Service | Host Port | Description |
|---------|-----------|-------------|
| oc-go-cc | `3456` | Anthropic → OpenAI format translator |
| Prometheus | `9090` (localhost only) | Metrics collection |
| Grafana | `3000` (localhost only) | Dashboards & visualization |
| Node Exporter | `9100` (localhost only) | Ubuntu host system metrics |
| cAdvisor | `8082` (localhost only) | Docker container metrics |

## Monitoring

### Grafana

Access at `http://localhost:3000` (default: admin / changeme).

A pre-built dashboard **"Claude Router Overview"** is auto-provisioned with:

- Request rate (req/s)
- Success rate (% with thresholds)
- Key health status (UP/DOWN)
- Latency P50/P95/P99
- Requests by status group (2xx/4xx/5xx)
- Key usage distribution
- Service status (oc-go-cc + smart-router)

### Prometheus

Access at `http://localhost:9090`.

**Scrape targets:**
| Target | Endpoint |
|--------|----------|
| oc-go-cc | `oc-go-cc:3456` |
| Node Exporter (Ubuntu) | `node-exporter:9100` |
| cAdvisor | `cadvisor:8080` |
| Smart Router (RPi 4) | `${RPI4_IP}:8080/metrics` |

**Configured alerts:**
| Alert | Severity | Condition |
|-------|----------|-----------|
| AllKeysDown | Critical | No healthy keys for 1m |
| HighErrorRate | Warning | >10% errors for 5m |
| KeyDisabled | Warning | Individual key down for 5m |
| HighLatency | Warning | P95 > 5s for 5m |
| OCGoCCDown | Critical | oc-go-cc unreachable for 2m |
| SmartRouterUnreachable | Critical | RPi4 router unreachable for 2m |

### opencode-smart-router Endpoints

| Endpoint | Auth | Description |
|----------|------|-------------|
| `/health` | None | Health status + upstream connectivity |
| `/metrics` | None | Prometheus metrics (enable in config) |
| `/admin/stats` | Basic Auth | Key states, usage, rotation strategy |
| `/v1/*` | None | Proxied to upstream (key injected) |

### Smart Router Config Requirements

Ensure your `opencode-smart-router` config on RPi 4 has:

```json
{
  "listen_addr": "0.0.0.0:8080",
  "enable_prometheus": true,
  "admin_pass": "set-a-strong-password"
}
```

## Health Checks

```bash
# Check all services at once
./scripts/healthcheck.sh

# Individual endpoints
curl http://localhost:3456/health           # oc-go-cc
curl http://localhost:9090/-/ready          # Prometheus
curl http://localhost:3000/api/health       # Grafana
curl http://${RPI4_IP}:8080/health          # Smart router
curl http://${RPI4_IP}:8080/admin/stats     # Key stats (requires auth)
```

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/start.sh` | Validate config, check RPi 4 connectivity, start services, health check |
| `scripts/healthcheck.sh` | Check all services and print color-coded status |
| `scripts/env-manager.sh` | Interactive .env management (init/show/update/validate) |

## File Structure

```
~/claude-router/
├── docker-compose.yml              # Main orchestration
├── .env                            # Configuration (not in git)
├── .env.example                    # Template (committed)
├── oc-go-cc-config.json            # Model routing config
├── prometheus/
│   ├── prometheus.yml               # Scrape config
│   └── alert_rules.yml              # Alerting rules
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── prometheus.yml      # Auto-configured datasource
│   │   └── dashboards/
│   │       └── dashboards.yml       # Dashboard provider
│   └── dashboards/
│       └── opencode-router-overview.json  # Pre-built dashboard
├── scripts/
│   ├── start.sh                     # Startup with validation
│   ├── healthcheck.sh               # Service health check
│   └── env-manager.sh               # .env management
└── README.md
```

## Troubleshooting

| Issue | Check |
|-------|-------|
| oc-go-cc not starting | `docker compose logs oc-go-cc` |
| Can't reach RPi 4 | `ping ${RPI4_IP}` and `curl http://${RPI4_IP}:8080/health` |
| No metrics in Grafana | Verify Prometheus targets at `http://localhost:9090/targets` |
| Smart router /metrics 404 | Set `"enable_prometheus": true` in router config |
| Key rotation not working | Check `curl http://${RPI4_IP}:8080/admin/stats` |
| Wrong model used | Edit `oc-go-cc-config.json` model mappings |

## Security Notes

- All monitoring ports (9090, 3000, 9100, 8082) are bound to `127.0.0.1` only
- oc-go-cc port 3456 is the default (no remapping needed)
- Smart router `admin_pass` should be set to a strong password
- `.env` contains secrets — never commit it to git
- API keys never appear in logs or Grafana metrics (masked in smart-router)