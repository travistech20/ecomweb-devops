#!/bin/bash

HAPROXY_CONTAINER="ecomweb_haproxy"

echo "HAProxy Server Status:"
echo "====================="

docker exec "$HAPROXY_CONTAINER" sh -c 'echo "show stat" | socat stdio /var/lib/haproxy/stats' | \
    grep -E "api_backend,(blue|green)" | \
    awk -F',' '{printf "%-10s Status: %-10s Weight: %-5s Health: %s\n", $2, $18, $19, $37}'

echo ""
echo "Current Weights:"
docker exec "$HAPROXY_CONTAINER" sh -c '
    echo "get weight api_backend/blue" | socat stdio /var/lib/haproxy/stats
    echo "get weight api_backend/green" | socat stdio /var/lib/haproxy/stats
'