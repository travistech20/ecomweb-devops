#!/bin/bash

echo "Running Prisma migrations..."
echo "Using DATABASE_URL_NON_POOLING for migrations"
DATABASE_URL="${DATABASE_URL_NON_POOLING}" npx prisma migrate deploy

echo "Starting API service with PM2..."
pm2 start /app/ecosystem.api.config.js --no-daemon
