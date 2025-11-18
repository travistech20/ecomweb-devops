# HAProxy Blue-Green Deployment with Graceful Shutdown

## Overview

The `deploy-haproxy.sh` script provides automated blue-green deployment with HAProxy load balancer integration and graceful shutdown of background services.

## What's New

The deployment script now includes:
- ✅ **Graceful shutdown of cron and worker services before deployment**
- ✅ **Automatic restart of background services with new version**
- ✅ **Health checks for background services**
- ✅ **Comprehensive status reporting**

## Deployment Flow

```
1. Determine active color (blue/green) from HAProxy
   ↓
2. Update .env with new image for idle slot
   ↓
3. ⭐ GRACEFULLY STOP cron (90s grace period)
   ↓
4. ⭐ GRACEFULLY STOP worker (150s grace period)
   ↓
5. Pull new API image for idle slot
   ↓
6. Deploy new API container
   ↓
7. Wait for container health check
   ↓
8. Wait for HAProxy health check
   ↓
9. Gradually shift traffic (100% → 75% → 50% → 25% → 0%)
   ↓
10. Disable old API server in HAProxy
   ↓
11. ⭐ RESTART cron with new version
   ↓
12. ⭐ RESTART worker with new version
   ↓
13. Verify background services health
   ↓
14. Display deployment summary
```

## Usage

### Basic Deployment

```bash
./deploy-haproxy.sh 1.2.3
```

This will:
1. Deploy version 1.2.3 to the idle slot
2. Gracefully stop background services
3. Switch HAProxy traffic
4. Restart background services

### Prerequisites

- HAProxy container must be running: `ecomweb_haproxy`
- Environment variables must be set in `.env`:
  ```bash
  API_IMAGE_BASE=ghcr.io/travistech20/ecomweb-api
  API_BLUE_IMAGE=ghcr.io/travistech20/ecomweb-api:current
  API_GREEN_IMAGE=ghcr.io/travistech20/ecomweb-api:current
  BLUE_ENABLED=true
  GREEN_ENABLED=false
  ```

## Graceful Shutdown Integration

### Cron Service

**Grace Period**: 90 seconds

```bash
# Stop command
docker compose stop -t 90 ecomweb_cron

# What happens:
# 1. Docker sends SIGTERM to container
# 2. startup-cron.sh trap executes graceful-shutdown.sh
# 3. PM2 sends SIGTERM to cron processes
# 4. Waits up to 60s for jobs to complete
# 5. Force kills if timeout
# 6. Container stops after max 90s
```

**Why before deployment?**
- Ensures cron jobs complete before API version changes
- Prevents jobs from breaking due to API incompatibilities
- Avoids race conditions with migrations

### Worker Service

**Grace Period**: 150 seconds

```bash
# Stop command
docker compose stop -t 150 ecomweb_worker

# What happens:
# 1. Docker sends SIGTERM to container
# 2. startup-worker.sh trap executes graceful-shutdown.sh
# 3. PM2 sends SIGTERM to worker processes
# 4. Temporal workers drain their task queues
# 5. Waits up to 120s for workflows to complete
# 6. Force kills if timeout
# 7. Container stops after max 150s
```

**Why before deployment?**
- Temporal workflows can reference old API code
- Long-running workflows need time to complete
- Prevents workflow failures during API version switch

## Example Deployment Output

```
════════════════════════════════════════════════════
   HAProxy Blue-Green Deployment v1.2.3
════════════════════════════════════════════════════

📊 Current State:
   Active: blue
   Idle:   green
   Image:  ghcr.io/travistech20/ecomweb-api:1.2.3

📝 Updating API_GREEN_IMAGE in .env...

⏸️  Gracefully stopping background services...
   This ensures running jobs complete before switching...

   → Stopping cron service (grace period: 90s)...
      ✓ Cron stopped gracefully
   → Stopping worker service (grace period: 150s)...
      ✓ Worker stopped gracefully

✓ Background services stopped gracefully

🚀 Deploying ecomweb_api_green...
[+] Pulling 1/1
 ✔ ecomweb_api_green Pulled

🏥 Waiting for container health check...
.......... ✓

🔄 Switching HAProxy to green...
   → Enabling green server...
   → Setting weight to 100

⏳ Waiting for green to be healthy in HAProxy...
✓ green is healthy in HAProxy

🎚️  Shifting traffic gradually...
   → Setting blue weight to 75%
   → Setting blue weight to 50%
   → Setting blue weight to 25%
   → Setting blue weight to 0%
   → Disabling blue server...

🔄 Restarting background services with new version...
   → Pulling latest images...
   → Starting cron service...
   → Starting worker service...
   → Waiting for services to be healthy...
      ✓ Cron service healthy
      ✓ Worker service healthy

✅ Deployment Summary:
   API:    Active: green (v1.2.3)
           Standby: blue
   Cron:   Running (Up 10 seconds)
   Worker: Running (Up 10 seconds)

📊 HAProxy Stats: http://localhost:8404/stats
   Username: admin
   Password: haproxy123

📝 Verification Steps:
   1. Check HAProxy stats to verify traffic routing
   2. Monitor logs: docker compose logs -f ecomweb_cron ecomweb_worker
   3. Verify health: docker ps --format "table {{.Names}}\t{{.Status}}"

🔄 To rollback: ./rollback-haproxy.sh
🛑 To stop old: docker compose stop ecomweb_api_blue
```

## Monitoring Deployment

### During Deployment

```bash
# Watch deployment progress
./deploy-haproxy.sh 1.2.3

# In another terminal, monitor logs
docker compose logs -f ecomweb_cron ecomweb_worker

# Watch container status
watch -n 1 'docker ps --format "table {{.Names}}\t{{.Status}}"'
```

### After Deployment

```bash
# Check HAProxy stats
open http://localhost:8404/stats

# Verify all services
docker ps --format "table {{.Names}}\t{{.Status}}"

# Check health
docker exec ecomweb_cron bash /app/healthcheck-cron.sh
docker exec ecomweb_worker bash /app/healthcheck-worker.sh

# Monitor API logs
docker compose logs -f ecomweb_api_green

# Monitor background services
docker compose logs -f ecomweb_cron ecomweb_worker
```

## Troubleshooting

### Cron Service Fails to Start

```bash
# Check logs
docker compose logs ecomweb_cron --tail 50

# Common issues:
# 1. Database not ready - check DATABASE_URL
# 2. PM2 config missing - verify volume mount
# 3. Permission issues - check script permissions

# Test database connectivity
docker exec ecomweb_cron npx prisma db execute --stdin <<< "SELECT 1"

# Restart manually
docker compose stop -t 90 ecomweb_cron
docker compose up -d ecomweb_cron
```

### Worker Service Fails to Start

```bash
# Check logs
docker compose logs ecomweb_worker --tail 50

# Common issues:
# 1. Temporal connection - check TEMPORAL_ADDRESS
# 2. Database not ready - check DATABASE_URL
# 3. PM2 config error - verify volume mount

# Test Temporal connectivity
docker exec ecomweb_worker curl -f $TEMPORAL_ADDRESS || echo "Failed"

# Restart manually
docker compose stop -t 150 ecomweb_worker
docker compose up -d ecomweb_worker
```

### HAProxy Traffic Not Switching

```bash
# Check HAProxy stats
curl -u admin:haproxy123 http://localhost:8404/stats

# Check server states
echo "show servers state" | docker exec -i ecomweb_haproxy socat stdio /var/lib/haproxy/stats

# Manual switch to green
echo "set weight api_backend/green 100" | docker exec -i ecomweb_haproxy socat stdio /var/lib/haproxy/stats
echo "set weight api_backend/blue 0" | docker exec -i ecomweb_haproxy socat stdio /var/lib/haproxy/stats
echo "disable server api_backend/blue" | docker exec -i ecomweb_haproxy socat stdio /var/lib/haproxy/stats
```

### Background Services Health Check Pending

**This is normal during startup!**

```bash
# Health checks take time:
# - Cron: 40s start_period + checks every 30s
# - Worker: 40s start_period + checks every 30s

# Wait and check again
sleep 45
docker exec ecomweb_cron bash /app/healthcheck-cron.sh
docker exec ecomweb_worker bash /app/healthcheck-worker.sh
```

## Configuration

### Grace Period Tuning

Edit `deploy-haproxy.sh`:

```bash
# For longer-running jobs
docker compose stop -t 120 ecomweb_cron    # Increase from 90s
docker compose stop -t 180 ecomweb_worker  # Increase from 150s
```

Or adjust in `docker-compose.yml`:

```yaml
ecomweb_cron:
  environment:
    - SHUTDOWN_GRACE_PERIOD=90  # Increase this
  stop_grace_period: 120s       # Must be > SHUTDOWN_GRACE_PERIOD

ecomweb_worker:
  environment:
    - SHUTDOWN_GRACE_PERIOD=150  # Increase this
  stop_grace_period: 180s        # Must be > SHUTDOWN_GRACE_PERIOD
```

### HAProxy Configuration

Located in: `docker-supabase-ecomapp/volumes/haproxy/haproxy.cfg`

```cfg
backend api_backend
    balance roundrobin
    option httpchk GET /health

    server blue ecomweb_api_blue:3001 check
    server green ecomweb_api_green:3001 check
```

## Rollback

If deployment fails or issues are detected:

```bash
./rollback-haproxy.sh
```

This will:
1. Switch HAProxy back to previous color
2. Gracefully stop background services
3. Restart background services with previous version
4. Verify health

## Best Practices

### 1. Pre-Deployment Checks

```bash
# Verify HAProxy is running
docker ps | grep ecomweb_haproxy

# Check current traffic distribution
curl -u admin:haproxy123 http://localhost:8404/stats | grep api_backend

# Verify .env is correct
cat .env | grep -E "API_.*_IMAGE|ENABLED"

# Check disk space
df -h
```

### 2. Deploy During Low Traffic

- Schedule deployments during maintenance windows
- Monitor traffic patterns
- Use gradual traffic shift (already built-in)

### 3. Monitor After Deployment

```bash
# Watch for errors
docker compose logs -f | grep -i error

# Monitor HAProxy stats
watch -n 5 'curl -u admin:haproxy123 http://localhost:8404/stats | grep api_backend'

# Check application metrics
curl http://localhost:3001/health
```

### 4. Document Deployment

```bash
# Log deployment
echo "$(date): Deployed v1.2.3 to green" >> deployment.log

# Save HAProxy state
curl -u admin:haproxy123 http://localhost:8404/stats > haproxy-state-before.txt
```

## Comparison: HAProxy vs Kong Deployment

| Feature | HAProxy (`deploy-haproxy.sh`) | Kong (`deploy.sh`) |
|---------|-------------------------------|-------------------|
| Load Balancer | HAProxy | Kong API Gateway |
| Traffic Switch | HAProxy admin socket | Kong Admin API |
| Gradual Shift | ✅ Built-in (75% → 50% → 25% → 0%) | ⚠️ Manual |
| Background Services | ✅ Graceful shutdown/restart | ✅ Graceful shutdown/restart |
| Health Checks | ✅ Container + HAProxy | ✅ Container + Kong |
| Stats UI | HAProxy Stats (port 8404) | Kong Admin API |
| Complexity | Simpler (direct socket commands) | More features (API gateway) |

## Related Documentation

- [DEPLOYMENT.md](DEPLOYMENT.md) - General deployment guide
- [GRACEFUL_SHUTDOWN.md](GRACEFUL_SHUTDOWN.md) - Graceful shutdown details
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture
- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Quick command reference

## Summary

The updated `deploy-haproxy.sh` script now provides:

✅ **Zero Job Loss** - Background services stop gracefully before deployment
✅ **Automated Restart** - Background services restart with new version automatically
✅ **Health Verification** - Checks ensure services are healthy before completion
✅ **Clear Status** - Comprehensive deployment summary with service status
✅ **Safe Rollback** - Can revert to previous version if needed
✅ **Production Ready** - Handles edge cases and provides clear error messages

Your HAProxy deployment now has enterprise-grade graceful shutdown for all services! 🚀
