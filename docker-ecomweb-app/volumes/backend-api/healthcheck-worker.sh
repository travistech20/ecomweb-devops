#!/bin/bash

# Health check for temporal worker service
# Returns 0 if healthy, 1 if unhealthy

# Check if PM2 is running
if ! pm2 list &>/dev/null; then
    echo "PM2 is not running"
    exit 1
fi

# Check if worker processes are online
if pm2 list | grep -q "temporal_worker.*online"; then
    exit 0
else
    echo "Temporal worker is not online"
    exit 1
fi
