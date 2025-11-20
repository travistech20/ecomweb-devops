#!/usr/bin/env bash
set -euo pipefail

# Configuration
NEW_VERSION="${1:-}"
HAPROXY_CONTAINER="ecomweb_haproxy"
HAPROXY_STATS_URL="http://localhost:8404/stats"
HAPROXY_STATS_AUTH="admin:haproxy123"  # Update with your password

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validation
if [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

if ! echo "$NEW_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "ERROR: version must be x.y.z format"
    exit 1
fi

# Helper functions
get_env() {
    grep -E "^${1}=" .env | cut -d= -f2-
}

# HAProxy admin socket command
haproxy_command() {
    local cmd=$1
    echo "$cmd" | docker exec -i "$HAPROXY_CONTAINER" socat stdio /var/lib/haproxy/stats
}

# Get server states from HAProxy
get_server_state() {
    local server=$1
    haproxy_command "show servers state" | grep "api_backend $server" | awk '{print $6}'
}

# Get current active color
get_active_color() {
    # Prefer state if possible
    local blue_state
    local green_state
    blue_state=$(haproxy_command "show servers state" | awk '$2=="api_backend" && $3=="blue"{print $5; exit}')
    green_state=$(haproxy_command "show servers state" | awk '$2=="api_backend" && $3=="green"{print $5; exit}')

    if [[ "$blue_state" == "2" ]]; then
        echo "blue"
        return
    elif [[ "$green_state" == "2" ]]; then
        echo "green"
        return
    fi

    # Fallback to weights (make sure they're numeric)
    local blue_weight
    local green_weight

    blue_weight=$(haproxy_command "get weight api_backend/blue"  | grep -oE '[0-9]+' | head -n1)
    green_weight=$(haproxy_command "get weight api_backend/green" | grep -oE '[0-9]+' | head -n1)

    # Default to 0 if empty or non-numeric
    [[ "$blue_weight"  =~ ^[0-9]+$ ]] || blue_weight=0
    [[ "$green_weight" =~ ^[0-9]+$ ]] || green_weight=0

    if (( blue_weight > green_weight )); then
        echo "blue"
    else
        echo "green"
    fi
}

# Wait for server to be healthy in HAProxy
wait_for_haproxy_health() {
    local server=$1
    local max_wait=60
    local count=0
    
    echo "⏳ Waiting for $server to be healthy in HAProxy..."
    
    while [ $count -lt $max_wait ]; do
        local check_status=$(haproxy_command "show stat" | grep "api_backend,$server" | cut -d',' -f18)
        
        if [[ "$check_status" == "UP" ]] || [[ "$check_status" =~ ^UP ]]; then
            echo -e "${GREEN}✓ $server is healthy in HAProxy${NC}"
            return 0
        fi
        
        echo "   Status: $check_status (attempt $((count+1))/$max_wait)"
        sleep 1
        count=$((count+1))
    done
    
    echo -e "${RED}✗ $server failed to become healthy in HAProxy${NC}"
    return 1
}

# Main deployment logic
main() {
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}   HAProxy Blue-Green Deployment v${NEW_VERSION}${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Get image base
    API_IMAGE_BASE=$(get_env API_IMAGE_BASE)
    NEW_IMAGE="${API_IMAGE_BASE}:${NEW_VERSION}"
    
    # Determine active and idle slots
    ACTIVE_COLOR=$(get_active_color)
    IDLE_COLOR=$([[ "$ACTIVE_COLOR" == "blue" ]] && echo "green" || echo "blue")
    
    echo -e "📊 Current State:"
    echo -e "   Active: ${GREEN}$ACTIVE_COLOR${NC}"
    echo -e "   Idle:   ${YELLOW}$IDLE_COLOR${NC}"
    echo -e "   Image:  $NEW_IMAGE"
    echo ""
    
    # Update .env with new image
    IDLE_VAR="API_$(echo "$IDLE_COLOR" | tr '[:lower:]' '[:upper:]')_IMAGE"
    echo "📝 Updating $IDLE_VAR in .env..."
    sed -i "s|^${IDLE_VAR}=.*|${IDLE_VAR}=${NEW_IMAGE}|" .env

    # Gracefully stop background services BEFORE deploying new API
    echo -e "\n⏸️  Gracefully stopping background services..."
    echo "   This ensures running jobs complete before switching..."
    echo ""

    # Stop cron service gracefully (90s grace period)
    echo "   → Stopping cron service (grace period: 90s)..."
    if docker ps | grep -q "ecomweb_cron"; then
        docker compose stop -t 90 ecomweb_cron || echo "      Cron already stopped"
        echo -e "      ${GREEN}✓ Cron stopped gracefully${NC}"
    else
        echo "      ⚠️  Cron not running"
    fi

    # Stop worker service gracefully (150s grace period)
    echo "   → Stopping worker service (grace period: 150s)..."
    if docker ps | grep -q "ecomweb_worker"; then
        docker compose stop -t 150 ecomweb_worker || echo "      Worker already stopped"
        echo -e "      ${GREEN}✓ Worker stopped gracefully${NC}"
    else
        echo "      ⚠️  Worker not running"
    fi

    # Stop bull worker service gracefully (150s grace period)
    echo "   → Stopping bull worker service (grace period: 150s)..."
    if docker ps | grep -q "ecomweb_bullmq_worker"; then
        docker compose stop -t 150 ecomweb_bullmq_worker || echo "      Bull worker already stopped"
        echo -e "      ${GREEN}✓ Bull worker stopped gracefully${NC}"
    else
        echo "      ⚠️  Bull worker not running"
    fi

    echo -e "\n${GREEN}✓ Background services stopped gracefully${NC}"

    # Deploy new container
    SERVICE_NAME="ecomweb_api_${IDLE_COLOR}"
    echo -e "\n🚀 Deploying $SERVICE_NAME..."

    docker compose pull "${SERVICE_NAME}"
    docker compose up -d "${SERVICE_NAME}"
    
    # Wait for container health check
    echo -e "\n🏥 Waiting for container health check..."
    MAX_RETRIES=30
    COUNT=0
    
    until docker exec "${SERVICE_NAME}" curl -fsS http://localhost:3001/health >/dev/null 2>&1; do
        COUNT=$((COUNT+1))
        if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
            echo -e "${RED}✗ Container health check failed${NC}"
            docker compose logs --tail=50 "${SERVICE_NAME}"
            exit 1
        fi
        echo -n "."
        sleep 2
    done
    echo -e " ${GREEN}✓${NC}"
    
    # Enable server in HAProxy
    echo -e "\n🔄 Switching HAProxy to $IDLE_COLOR..."
    
    # First enable the idle server
    echo "   → Enabling $IDLE_COLOR server..."
    haproxy_command "enable server api_backend/$IDLE_COLOR"
    haproxy_command "enable server api_backend_ws/$IDLE_COLOR"
    
    # Set weight to 100
    haproxy_command "set weight api_backend/$IDLE_COLOR 100"
    haproxy_command "set weight api_backend_ws/$IDLE_COLOR 100"
    
    # Wait for HAProxy health check
    if ! wait_for_haproxy_health "$IDLE_COLOR"; then
        echo -e "${RED}✗ HAProxy health check failed${NC}"
        exit 1
    fi
    
    # Gradual traffic shift (optional)
    echo -e "\n🎚️  Shifting traffic gradually..."
    
    # Reduce active server weight
    for weight in 75 50 25 0; do
        echo "   → Setting $ACTIVE_COLOR weight to $weight%"
        haproxy_command "set weight api_backend/$ACTIVE_COLOR $weight"
        haproxy_command "set weight api_backend_ws/$ACTIVE_COLOR $weight"
        sleep 2
    done
    
    # Disable old server
    echo "   → Disabling $ACTIVE_COLOR server..."
    haproxy_command "disable server api_backend/$ACTIVE_COLOR"
    haproxy_command "disable server api_backend_ws/$ACTIVE_COLOR"
    
    # Update .env state
    if [ "$IDLE_COLOR" = "green" ]; then
        sed -i "s/^BLUE_ENABLED=.*/BLUE_ENABLED=false/" .env
        sed -i "s/^GREEN_ENABLED=.*/GREEN_ENABLED=true/" .env
    else
        sed -i "s/^BLUE_ENABLED=.*/BLUE_ENABLED=true/" .env
        sed -i "s/^GREEN_ENABLED=.*/GREEN_ENABLED=false/" .env
    fi

    # Update current active image for background services
    echo "📝 Updating CURRENT_API_IMAGE to ${NEW_IMAGE}..."
    sed -i "s|^CURRENT_API_IMAGE=.*|CURRENT_API_IMAGE=${NEW_IMAGE}|" .env

    # Restart background services with new version
    echo -e "\n🔄 Restarting background services with new version..."

    # Pull latest images for background services
    echo "   → Pulling latest images..."
    docker compose pull ecomweb_cron ecomweb_worker ecomweb_bullmq_worker

    # Start cron service
    echo "   → Starting cron service..."
    docker compose up -d ecomweb_cron

    # Start worker service
    echo "   → Starting worker service..."
    docker compose up -d ecomweb_worker

    # Start worker service
    echo "   → Starting bull worker service..."
    docker compose up -d ecomweb_bullmq_worker

    # Wait for background services to be healthy
    echo "   → Waiting for services to be healthy..."
    sleep 20

    # Check cron health
    CRON_STATUS=$(docker compose ps ecomweb_cron 2>/dev/null)
    if echo "$CRON_STATUS" | grep -q "Up"; then
        if docker exec ecomweb_cron bash /app/healthcheck-cron.sh &>/dev/null; then
            echo -e "      ${GREEN}✓ Cron service healthy${NC}"
        else
            echo -e "      ${YELLOW}⚠️  Cron service up but health check pending${NC}"
        fi
    else
        echo -e "      ${RED}✗ Cron service failed to start${NC}"
        docker compose logs --tail=20 ecomweb_cron
    fi

    # Check worker health
    WORKER_STATUS=$(docker compose ps ecomweb_worker 2>/dev/null)
    if echo "$WORKER_STATUS" | grep -q "Up"; then
        if docker exec ecomweb_worker bash /app/healthcheck-worker.sh &>/dev/null; then
            echo -e "      ${GREEN}✓ Worker service healthy${NC}"
        else
            echo -e "      ${YELLOW}⚠️  Worker service up but health check pending${NC}"
        fi
    else
        echo -e "      ${RED}✗ Worker service failed to start${NC}"
        docker compose logs --tail=20 ecomweb_worker
    fi

    # Final verification
    echo -e "\n✅ Deployment Summary:"
    echo -e "   API:    ${GREEN}Active: $IDLE_COLOR (v${NEW_VERSION})${NC}"
    echo -e "           ${YELLOW}Standby: $ACTIVE_COLOR${NC}"

    # Show background services status
    CRON_STATUS=$(docker ps --format "{{.Status}}" --filter name=ecomweb_cron 2>/dev/null || echo "not running")
    WORKER_STATUS=$(docker ps --format "{{.Status}}" --filter name=ecomweb_worker 2>/dev/null || echo "not running")

    if [[ "$CRON_STATUS" =~ "Up" ]]; then
        echo -e "   Cron:   ${GREEN}Running ($CRON_STATUS)${NC}"
    else
        echo -e "   Cron:   ${RED}$CRON_STATUS${NC}"
    fi

    if [[ "$WORKER_STATUS" =~ "Up" ]]; then
        echo -e "   Worker: ${GREEN}Running ($WORKER_STATUS)${NC}"
    else
        echo -e "   Worker: ${RED}$WORKER_STATUS${NC}"
    fi

    echo ""
    echo "📊 HAProxy Stats: $HAPROXY_STATS_URL"
    echo "   Username: admin"
    echo "   Password: haproxy123"
    echo ""
    echo "📝 Verification Steps:"
    echo "   1. Check HAProxy stats to verify traffic routing"
    echo "   2. Monitor logs: docker compose logs -f ecomweb_cron ecomweb_worker"
    echo "   3. Verify health: docker ps --format \"table {{.Names}}\\t{{.Status}}\""
    echo ""
    echo "🔄 To rollback: ./rollback.sh"
    echo "🛑 To stop old: docker compose stop ecomweb_api_$ACTIVE_COLOR"
}

# Run main function
main