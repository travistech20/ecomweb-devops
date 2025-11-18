#!/bin/bash

echo "Running Prisma migrations..."
npx prisma migrate deploy

echo "Starting API service with PM2..."
pm2 start /app/ecosystem.api.config.js --no-daemon
