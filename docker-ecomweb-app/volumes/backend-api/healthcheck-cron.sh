#!/bin/bash

# Health check for cron service
# Returns 0 if healthy, 1 if unhealthy

# Check if PM2 is running
if ! pm2 list &>/dev/null; then
    echo "PM2 is not running"
    exit 1
fi

# Check if cron process is online
if pm2 list | grep -q "cron_worker.*online"; then
    exit 0
else
    echo "Cron worker is not online"
    exit 1
fi
