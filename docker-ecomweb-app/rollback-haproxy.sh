#!/usr/bin/env bash
set -euo pipefail

HAPROXY_CONTAINER="ecomweb_haproxy"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# HAProxy admin command
haproxy_command() {
    echo "$1" | docker exec -i "$HAPROXY_CONTAINER" socat stdio /var/lib/haproxy/stats
}

# Get current active color
get_active_color() {
    local blue_weight=$(haproxy_command "get weight api_backend/blue" | awk '{print $2}')
    local green_weight=$(haproxy_command "get weight api_backend/green" | awk '{print $2}')
    
    if [[ "${blue_weight:-0}" -gt 0 ]] && [[ "${green_weight:-0}" -eq 0 ]]; then
        echo "blue"
    else
        echo "green"
    fi
}

echo -e "${YELLOW}🔄 Rolling back deployment...${NC}"

CURRENT=$(get_active_color)
PREVIOUS=$([[ "$CURRENT" == "blue" ]] && echo "green" || echo "blue")

echo -e "Current: $CURRENT"
echo -e "Rolling back to: ${GREEN}$PREVIOUS${NC}"

# Check if previous container is running
if ! docker ps | grep -q "ecomweb_api_${PREVIOUS}"; then
    echo -e "${RED}Error: $PREVIOUS container is not running!${NC}"
    exit 1
fi

# Enable previous
haproxy_command "enable server api_backend/$PREVIOUS"
haproxy_command "enable server api_backend_ws/$PREVIOUS"
haproxy_command "set weight api_backend/$PREVIOUS 100"
haproxy_command "set weight api_backend_ws/$PREVIOUS 100"

# Disable current
haproxy_command "set weight api_backend/$CURRENT 0"
haproxy_command "set weight api_backend_ws/$CURRENT 0"
haproxy_command "disable server api_backend/$CURRENT"
haproxy_command "disable server api_backend_ws/$CURRENT"

# Update .env
if [ "$PREVIOUS" = "green" ]; then
    sed -i "s/^BLUE_ENABLED=.*/BLUE_ENABLED=false/" .env
    sed -i "s/^GREEN_ENABLED=.*/GREEN_ENABLED=true/" .env
else
    sed -i "s/^BLUE_ENABLED=.*/BLUE_ENABLED=true/" .env
    sed -i "s/^GREEN_ENABLED=.*/GREEN_ENABLED=false/" .env
fi

echo -e "${GREEN}✓ Rollback complete${NC}"