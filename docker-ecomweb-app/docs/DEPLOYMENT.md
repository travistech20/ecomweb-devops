# Ecommerce API Deployment Guide

## Architecture Overview

The application is now separated into specialized services for better scalability and resource management:

### Services Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         HAProxy                              │
│                   (Load Balancer)                           │
│              docker-supabase-ecomapp                         │
└─────────────┬───────────────────────────────────────────────┘
              │
              ├──────────────┬──────────────┐
              ▼              ▼              ▼
      ┌──────────┐   ┌──────────┐   ┌──────────┐
      │ API Blue │   │API Green │   │  Redis   │
      │  :3001   │   │  :3001   │   │  :6379   │
      └──────────┘   └──────────┘   └──────────┘
              │
              ├──────────────┬──────────────┐
              ▼              ▼              ▼
      ┌──────────┐   ┌──────────┐   ┌──────────┐
      │   Cron   │   │  Worker  │   │  Worker  │
      │ (PM2x1)  │   │ (PM2x2)  │   │ (Scale)  │
      └──────────┘   └──────────┘   └──────────┘
```

### Service Breakdown

1. **API Services** (`ecomweb_api_blue`, `ecomweb_api_green`)
   - Handles HTTP requests
   - Runs in cluster mode with PM2 (`instances: 'max'`)
   - Blue-Green deployment ready
   - Health checks enabled
   - Located in: `docker-ecomweb-app/`

2. **Cron Service** (`ecomweb_cron`)
   - Runs scheduled tasks
   - Single instance (fork mode)
   - Independent of blue/green API instances
   - Waits for database readiness before starting
   - No external ports exposed

3. **Worker Service** (`ecomweb_worker`)
   - Processes Temporal workflow tasks
   - Runs 2 instances for better throughput
   - Can be scaled independently
   - Independent of blue/green API instances
   - Waits for database readiness before starting

4. **Redis** (`ecomweb_redis`)
   - Shared cache and session store
   - Persistent volume for data

5. **HAProxy** (in `docker-supabase-ecomapp/`)
   - Load balances between API instances
   - Health checks and monitoring
   - Blue-Green deployment support

## Configuration Files

### PM2 Ecosystem Configs

1. **API Config** (`ecosystem.api.config.js`)
   - Cluster mode with all CPU cores
   - API-only processes

2. **Cron Config** (`ecosystem.cron.config.js`)
   - Single instance for scheduled tasks
   - Fork mode to prevent duplicate executions

3. **Worker Config** (`ecosystem.worker.config.js`)
   - 2 instances for parallel task processing
   - Cluster mode for better throughput

### Startup Scripts

1. **startup-api.sh**
   - Runs Prisma migrations
   - Starts API service

2. **startup-cron.sh**
   - Waits for database to be ready (up to 60s)
   - Checks database connectivity via Prisma
   - Starts cron worker

3. **startup-worker.sh**
   - Waits for database to be ready (up to 60s)
   - Checks database connectivity via Prisma
   - Traps SIGTERM for graceful shutdown
   - Starts temporal worker

### Graceful Shutdown Scripts

1. **graceful-shutdown.sh**
   - Handles SIGTERM/SIGINT signals
   - Waits for PM2 processes to complete (configurable grace period)
   - Force kills if grace period expires

2. **healthcheck-cron.sh** & **healthcheck-worker.sh**
   - Verify service health
   - Check PM2 process status

## Deployment Instructions

### Initial Setup

1. **Set Environment Variables**
   ```bash
   cd /path/to/docker-ecomweb-app
   # Edit .env.api with your configuration
   export API_BLUE_IMAGE=ghcr.io/travistech20/ecomweb-api:latest
   export API_GREEN_IMAGE=ghcr.io/travistech20/ecomweb-api:latest
   ```

2. **Start All Services**
   ```bash
   docker-compose up -d
   ```

3. **Verify Services**
   ```bash
   # Check all services are running
   docker-compose ps

   # Check API logs
   docker logs ecomweb_api_blue
   docker logs ecomweb_api_green

   # Check cron logs
   docker logs ecomweb_cron

   # Check worker logs
   docker logs ecomweb_worker
   ```

### Blue-Green Deployment with Graceful Shutdown

**Recommended**: Use the provided `deploy.sh` script for automated graceful deployment:

```bash
./deploy.sh 1.2.3
```

The script automatically:
1. Deploys new API version to idle slot
2. Waits for health check
3. **Gracefully stops cron (90s grace period) - ensures jobs complete**
4. **Gracefully stops worker (150s grace period) - ensures workflows complete**
5. Switches traffic to new API
6. Restarts cron and worker with new version

**Manual Blue-Green Deployment:**

1. **Deploy to inactive color (e.g., Green)**
   ```bash
   export API_GREEN_IMAGE=ghcr.io/travistech20/ecomweb-api:v2.0.0
   docker-compose pull ecomweb_api_green
   docker-compose up -d ecomweb_api_green
   ```

2. **Wait for health check**
   ```bash
   # Wait for green to be healthy
   until docker exec ecomweb_api_green curl -fsS http://localhost:3001/health; do
       echo "Waiting for API health..."
       sleep 2
   done
   ```

3. **Gracefully stop background services**
   ```bash
   # Stop cron with 90s grace period (allows jobs to complete)
   docker-compose stop -t 90 ecomweb_cron

   # Stop worker with 150s grace period (allows workflows to complete)
   docker-compose stop -t 150 ecomweb_worker
   ```

4. **Switch traffic via HAProxy/Kong**
   - Update routing to point to new API version
   - See deploy.sh for Kong integration example

5. **Restart background services with new version**
   ```bash
   # Restart cron and worker with new version
   docker-compose up -d ecomweb_cron ecomweb_worker

   # Verify health
   docker ps --format "table {{.Names}}\t{{.Status}}"
   ```

**⚠️ Important**: Never use `docker-compose restart` for cron/worker services during deployment. Always use `stop` (with grace period) followed by `up -d` to ensure proper shutdown.

### Scaling Workers

Scale the worker service for higher throughput:

```bash
# Scale to 3 worker instances
docker-compose up -d --scale ecomweb_worker=3
```

Or modify `docker-compose.yml`:
```yaml
deploy:
  replicas: 3
```

## Monitoring

### Health Checks

- **API Health**: `http://your-domain/health`
- **HAProxy Stats**: `http://your-domain:8404` (admin/admin123)
- **HAProxy Health**: `http://your-domain/haproxy-health`

### Logs

```bash
# API logs
docker logs -f ecomweb_api_blue
docker logs -f ecomweb_api_green

# Cron logs
docker logs -f ecomweb_cron

# Worker logs
docker logs -f ecomweb_worker

# Redis logs
docker logs -f ecomweb-redis
```

### PM2 Monitoring (Inside Container)

```bash
# Access container
docker exec -it ecomweb_api_blue bash

# Check PM2 processes
pm2 list
pm2 monit
pm2 logs
```

## Troubleshooting

### Issue: Cron/Worker fail to start with "Database not ready"

**Solution**: The services check database connectivity for up to 60 seconds. If still failing:

1. Check database is accessible:
   ```bash
   docker exec ecomweb_cron npx prisma db execute --stdin <<< "SELECT 1"
   ```

2. Increase max_attempts in startup scripts:
   ```bash
   # In startup-cron.sh and startup-worker.sh
   max_attempts=60  # Increase from 30 to 60
   ```

3. Check database connection string in .env.api

### Issue: Worker not processing tasks

**Solution**: Check Temporal connection and worker registration:

```bash
docker logs ecomweb_worker
# Verify IS_TEMPORAL_WORKER=true in environment
```

### Issue: Cron jobs running multiple times

**Solution**: Ensure only one cron instance is running:

```bash
docker ps | grep ecomweb_cron
# Should show only one container
```

## Resource Management

### Recommended Resource Allocation

```yaml
# In docker-compose.yml, add resource limits:
services:
  ecomweb_api_blue:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 1G

  ecomweb_cron:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  ecomweb_worker:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 1G
```

## Migration from Old Setup

If migrating from the old single-container setup:

1. **Backup data**
   ```bash
   docker exec ecomweb-redis redis-cli BGSAVE
   ```

2. **Update configuration files**
   - Replace old `ecosystem.config.js` usage with new separate configs

3. **Deploy new setup**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

4. **Verify all services**
   - Check each service is running with correct configuration
   - Verify cron jobs are executing
   - Test worker task processing

## Performance Tuning

### API Service
- Adjust PM2 instances: `instances: 2` instead of `'max'`
- Tune memory limits based on usage

### Worker Service
- Scale replicas based on task queue depth
- Monitor memory usage and adjust limits

### Redis
- Configure maxmemory policy in redis.conf
- Monitor connection pool usage

## Security Considerations

1. **Network Isolation**
   - Services communicate via `ecomweb_internal_net`
   - Only HAProxy exposes public ports

2. **Health Check Endpoints**
   - Ensure `/health` doesn't expose sensitive data
   - Add authentication for admin endpoints

3. **Environment Variables**
   - Keep `.env.api` secure
   - Rotate credentials regularly

## Backup and Recovery

### Database Backups
- Handled by Prisma migrations
- Regular backups via your database provider

### Redis Backups
```bash
# Create backup
docker exec ecomweb-redis redis-cli BGSAVE

# Restore from backup
docker cp backup.rdb ecomweb-redis:/data/dump.rdb
docker restart ecomweb-redis
```

## Next Steps

1. **Configure monitoring**: Set up Prometheus/Grafana for metrics
2. **Add alerting**: Configure alerts for service failures
3. **Optimize caching**: Tune Redis configuration
4. **Review logs**: Set up centralized logging (ELK/Loki)
5. **Load testing**: Verify performance under load
