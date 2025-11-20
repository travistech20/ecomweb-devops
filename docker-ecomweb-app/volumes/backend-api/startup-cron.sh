#!/bin/bash

# Ensure graceful-shutdown.sh has execute permissions
chmod +x /app/graceful-shutdown.sh 2>/dev/null || true

# Trap SIGTERM and SIGINT for graceful shutdown
trap '/app/graceful-shutdown.sh' SIGTERM SIGINT

echo "Waiting for database to be ready..."

# Wait for database to be accessible by checking Prisma connection
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    echo "Checking database connection (attempt $((attempt + 1))/$max_attempts)..."

    if npx prisma db execute --url="$DATABASE_URL_NON_POOLING" --stdin <<< "SELECT 1" &>/dev/null; then
        echo "Database is ready!"
        break
    fi

    attempt=$((attempt + 1))

    if [ $attempt -eq $max_attempts ]; then
        echo "ERROR: Database not ready after $max_attempts attempts"
        exit 1
    fi

    sleep 2
done

echo "Starting Cron worker with PM2..."
pm2 start /app/ecosystem.cron.config.js --no-daemon &

# Wait for PM2 process to complete
wait $!
