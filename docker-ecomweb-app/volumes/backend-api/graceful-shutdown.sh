#!/bin/bash

# Graceful shutdown script for PM2 processes
# This script ensures running jobs complete before shutdown

SERVICE_TYPE=${SERVICE_TYPE:-"unknown"}
GRACE_PERIOD=${SHUTDOWN_GRACE_PERIOD:-30}

echo "[$SERVICE_TYPE] Starting graceful shutdown (grace period: ${GRACE_PERIOD}s)..."

# Function to check if PM2 processes are running
check_pm2_running() {
    pm2 list | grep -q "online"
    return $?
}

# Function to wait for processes to finish gracefully
wait_for_processes() {
    local wait_time=0
    local check_interval=2

    while check_pm2_running && [ $wait_time -lt $GRACE_PERIOD ]; do
        echo "[$SERVICE_TYPE] Waiting for processes to complete... (${wait_time}s/${GRACE_PERIOD}s)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done

    if check_pm2_running; then
        echo "[$SERVICE_TYPE] WARNING: Grace period expired, some processes may still be running"
        return 1
    else
        echo "[$SERVICE_TYPE] All processes completed successfully"
        return 0
    fi
}

# Send SIGTERM to PM2 processes (graceful shutdown)
echo "[$SERVICE_TYPE] Sending SIGTERM to PM2 processes..."
pm2 stop all

# Wait for processes to finish
wait_for_processes

# If processes are still running, force kill
if check_pm2_running; then
    echo "[$SERVICE_TYPE] Force stopping remaining processes..."
    pm2 kill
fi

echo "[$SERVICE_TYPE] Shutdown complete"
exit 0
