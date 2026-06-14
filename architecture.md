oc-go-cc Docker Compose Solution (English Markdown)
generate shell scripts, Docker setups, or related automation.
Markdown# oc-go-cc + opencode-smart-router Integration (Docker Compose)

## Architecture Overview
Claude Code (Ubuntu)
↓
oc-go-cc (Docker on Ubuntu)          ← Format translator (Anthropic → OpenAI)
↓
opencode-smart-router (Docker on RPi 4)   ← Key rotation + failover
↓
OpenCode Go API
text- **oc-go-cc** runs on your Ubuntu machine (this host)
- **opencode-smart-router** runs on Raspberry Pi 4
- This setup allows Claude Code to use your rotated OpenCode Go keys

---

## Recommended Folder Structure on Ubuntu (this host)

```bash
~/claude-router/
├── docker-compose.yml
├── .env
└── README.md

1. docker-compose.yml (Recommended)
Create ~/claude-router/docker-compose.yml:
YAMLversion: '3.8'

services:
  oc-go-cc:
    image: ghcr.io/samueltuyizere/oc-go-cc:latest
    container_name: oc-go-cc
    restart: unless-stopped
    ports:
      - "8081:8080"
    env_file:
      - .env
    environment:
      # Point to your RPi 4's opencode-smart-router
      - ANTHROPIC_BASE_URL=http://${RPI4_IP}:8080/v1
      - ANTHROPIC_API_KEY=dummy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 256M
        reservations:
          cpus: '0.1'
          memory: 64M

2. .env File (Environment Variables)
Create ~/claude-router/.env:
env# Replace with your Raspberry Pi 4's IP address
RPI4_IP=192.168.50.150


opencode-smart-router running on my Raspberry Pi 4 and has multiple key stored

# Optional: Enable debug logging for oc-go-cc
# ANTHROPIC_LOG_LEVEL=debug
Note: Do not put real OpenCode Go keys in this .env if the router is already handling key rotation. The OPENCODE_KEYS here is mainly for documentation or if you want to run the router in the same compose stack later.

3. How to Run
Bashcd ~/claude-router

# Start oc-go-cc
docker compose up -d

# Check logs
docker compose logs -f oc-go-cc

# Check health
curl http://localhost:8081/health

4. Run Claude Code
After oc-go-cc is running, set the following environment variables and launch Claude Code:
Bashexport ANTHROPIC_BASE_URL="http://127.0.0.1:8081"
export ANTHROPIC_API_KEY="dummy"

# Start Claude Code
claude-code

5. Complete Recommended Workflow

On Raspberry Pi 4:
Run your opencode-smart-router on port 8080

On Ubuntu:
Create ~/claude-router/
Add the docker-compose.yml and .env above
Replace RPI4_IP with your actual Raspberry Pi IP
Run docker compose up -d
Set the two export commands above
Launch claude-code



6. Optional Enhancements (do it)
Add Prometheus + Grafana (Monitoring, suggest Dashboard)
You can extend the docker-compose.yml later with:
YAMLprometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
Use .env for All Variables (Cleaner)
Instead of hardcoding in docker-compose.yml, move everything to .env:
envRPI4_IP=192.168.50.150
ANTHROPIC_BASE_URL=http://${RPI4_IP}:8080/v1
ANTHROPIC_API_KEY=dummy
Then in docker-compose.yml use:
YAMLenvironment:
  - ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL}
  - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}

Summary

Use Docker Compose on Ubuntu to run oc-go-cc
Point ANTHROPIC_BASE_URL to your RPi 4’s opencode-smart-router
Keep the router on RPi 4 (lighter and more stable)
Use 8081 on Ubuntu so it doesn’t conflict with the router’s port 8080

This setup gives you a clean separation:

RPi 4 = Key rotation + agent runtime (Hermes)
Ubuntu = Development + Claude Code + format translation


Ready for your vibe coding tool.
You can now ask your AI coding agent to generate:

A startup shell script
An improved docker-compose.yml
Environment variable management script
Health check monitoring script
