#!/bin/bash

echo "Running Prisma migrations..."
npx prisma migrate deploy

echo "Starting application with PM2..."
pm2 start /app/ecosystem.config.js --no-daemon