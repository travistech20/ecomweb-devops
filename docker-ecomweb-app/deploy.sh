#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./deploy.sh 1.2.3

NEW_VERSION="${1:-}"

if [ -z "$NEW_VERSION" ]; then
  echo "Usage: $0 <version>"
  exit 1
fi

if ! echo "$NEW_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: version must be x.y.z"
  exit 1
fi

# Configuration
KONG_ADMIN_URL="http://localhost:8000"
KONG_CONTAINER="supabase-kong"  # Adjust to your Kong container name
API_SERVICE_NAME="ecomweb-api-v1"
WS_SERVICE_NAME="ecomweb-ws-v1"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

get_env() {
  grep -E "^${1}=" .env | cut -d= -f2-
}

# Get current deployment color from Kong
get_current_color() {
  local current_url=$(curl -s "$KONG_ADMIN_URL/services/$API_SERVICE_NAME" | jq -r '.url' 2>/dev/null || echo "")
  if [[ "$current_url" == *"blue"* ]]; then
    echo "blue"
  elif [[ "$current_url" == *"green"* ]]; then
    echo "green"
  else
    # Fallback to env file
    local blue_enabled=$(get_env BLUE_ENABLED)
    if [[ "$blue_enabled" == "true" ]]; then
      echo "blue"
    else
      echo "green"
    fi
  fi
}

API_IMAGE_BASE=$(get_env API_IMAGE_BASE)
NEW_IMAGE="${API_IMAGE_BASE}:${NEW_VERSION}"

echo "Deploying version ${NEW_VERSION} → ${NEW_IMAGE}"

# Determine live & idle slots
LIVE_SLOT=$(get_current_color)
IDLE_SLOT=$([[ "$LIVE_SLOT" == "blue" ]] && echo "green" || echo "blue")

echo -e "${BLUE}Live slot: ${LIVE_SLOT}${NC}"
echo -e "${GREEN}Idle slot: ${IDLE_SLOT}${NC}"

# Update .env with new image
IDLE_VAR="API_$(echo "$IDLE_SLOT" | tr '[:lower:]' '[:upper:]')_IMAGE"
echo "Updating .env → ${IDLE_VAR}=${NEW_IMAGE}"
sed -i "s|^${IDLE_VAR}=.*|${IDLE_VAR}=${NEW_IMAGE}|" .env

# Deploy new version
SERVICE_NAME="ecomweb_api_${IDLE_SLOT}"
echo "Pulling ${SERVICE_NAME}..."
docker compose pull "${SERVICE_NAME}"

echo "Starting ${SERVICE_NAME}..."
docker compose up -d "${SERVICE_NAME}"

# Wait for health check
echo "Waiting for ${SERVICE_NAME} to become healthy..."
MAX_RETRIES=30
COUNT=0

until docker exec "${SERVICE_NAME}" curl -fsS http://localhost:3001/health >/dev/null 2>&1; do
  COUNT=$((COUNT+1))
  if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
    echo -e "${RED}ERROR: ${SERVICE_NAME} did not become healthy.${NC}"
    docker compose logs --tail=50 "${SERVICE_NAME}"
    exit 1
  fi
  echo "Retrying health check (${COUNT}/${MAX_RETRIES})..."
  sleep 2
done

echo -e "${GREEN}✓ ${SERVICE_NAME} is healthy${NC}"

# Test the new deployment through Kong (optional test route)
echo "Testing new deployment..."
TEST_URL="http://localhost:8000/api/v1/health"
if ! curl -f -s -H "Host: test-${IDLE_SLOT}.local" "$TEST_URL" > /dev/null; then
  echo -e "${RED}Warning: Test request failed${NC}"
fi

# Switch Kong routing
echo "Switching Kong routes to ${IDLE_SLOT}..."
IDLE_CONTAINER="${SERVICE_NAME}"

# Update API service
curl -X PATCH "$KONG_ADMIN_URL/services/$API_SERVICE_NAME" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"http://${IDLE_CONTAINER}:3001/\"}" \
  || { echo -e "${RED}Failed to update API service${NC}"; exit 1; }

# Update WebSocket service
curl -X PATCH "$KONG_ADMIN_URL/services/$WS_SERVICE_NAME" \
  -H "Content-Type: application/json" \
  -d "{\"url\": \"http://${IDLE_CONTAINER}:3001/\"}" \
  || { echo -e "${RED}Failed to update WebSocket service${NC}"; exit 1; }

# Verify the switch
echo "Verifying deployment..."
sleep 2
CURRENT_URL=$(curl -s "$KONG_ADMIN_URL/services/$API_SERVICE_NAME" | jq -r '.url')
if [[ "$CURRENT_URL" == *"${IDLE_SLOT}"* ]]; then
  echo -e "${GREEN}✓ Kong successfully switched to ${IDLE_SLOT}${NC}"
else
  echo -e "${RED}✗ Kong switch verification failed${NC}"
  exit 1
fi

# Update .env state
if [ "$IDLE_SLOT" = "green" ]; then
  sed -i "s/^BLUE_ENABLED=.*/BLUE_ENABLED=false/" .env
  sed -i "s/^GREEN_ENABLED=.*/GREEN_ENABLED=true/" .env
else
  sed -i "s/^BLUE_ENABLED=.*/BLUE_ENABLED=true/" .env
  sed -i "s/^GREEN_ENABLED=.*/GREEN_ENABLED=false/" .env
fi

echo -e "${GREEN}✓ Deployment complete. Live version is now: ${IDLE_SLOT} (${NEW_VERSION})${NC}"
echo ""
echo "Old deployment (${LIVE_SLOT}) is still running."
echo "To stop it: docker compose stop ecomweb_api_${LIVE_SLOT}"
echo "To rollback: ./rollback.sh"