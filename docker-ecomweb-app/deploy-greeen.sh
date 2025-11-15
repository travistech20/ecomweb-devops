#!/usr/bin/env bash
set -euo pipefail

# Usage: ./deploy-green.sh registry.example.com/ecomweb-api:1.2.3

NEW_IMAGE="${1:-}"

if [ -z "$NEW_IMAGE" ]; then
  echo "Usage: $0 <new-green-image>"
  echo "Example: $0 registry.example.com/ecomweb-api:1.2.3"
  exit 1
fi

echo "[deploy-green] New GREEN image: $NEW_IMAGE"

# 1. Update API_GREEN_IMAGE in .env
echo "[deploy-green] Updating .env API_GREEN_IMAGE..."
# GNU sed (server is usually Linux)
sed -i "s|^API_GREEN_IMAGE=.*|API_GREEN_IMAGE=${NEW_IMAGE}|" .env

# 2. Pull new image for api_green
echo "[deploy-green] Pulling image..."
docker compose pull api_green

# 3. Start (or restart) api_green
echo "[deploy-green] Starting api_green..."
docker compose up -d api_green

# 4. Wait for container to boot
echo "[deploy-green] Waiting a few seconds for GREEN to boot..."
sleep 5

# 5. Health check GREEN directly inside the container
# Adjust /health if your endpoint path is different
echo "[deploy-green] Running health check on GREEN..."
docker exec api_green curl -fsS http://localhost:3000/health > /dev/null

echo "[deploy-green] GREEN is healthy!"

# 6. Flip routing: BLUE off, GREEN on
echo "[deploy-green] Switching traffic BLUE -> GREEN..."

sed -i "s/^BLUE_ENABLED=.*/BLUE_ENABLED=false/" .env
sed -i "s/^GREEN_ENABLED=.*/GREEN_ENABLED=true/" .env

# 7. Apply updated labels
docker compose up -d traefik api_blue api_green

echo "[deploy-green] Traefik has reloaded configuration."
echo "[deploy-green] GREEN is now LIVE. BLUE is still running but no traffic."

# 8. Optional: show container states
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | grep -E 'api_blue|api_green|traefik|kong' || true

echo "[deploy-green] Done."