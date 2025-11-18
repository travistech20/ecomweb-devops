# Quick Reference Card

## Deployment

```bash
# Automated deployment (recommended)
./deploy.sh 1.2.3

# Manual graceful deployment
docker-compose stop -t 90 ecomweb_cron
docker-compose stop -t 150 ecomweb_worker
docker-compose pull ecomweb_api_green
docker-compose up -d ecomweb_api_green
# Switch traffic in HAProxy/Kong
docker-compose up -d ecomweb_cron ecomweb_worker
```

## Service Management

```bash
# Start all services
docker-compose up -d

# Stop all services
docker-compose down

# Restart specific service (GRACEFUL)
docker-compose stop -t 90 ecomweb_cron
docker-compose up -d ecomweb_cron

# Scale workers
docker-compose up -d --scale ecomweb_worker=3

# View all services
docker-compose ps
```

## Logs & Monitoring

```bash
# View logs (follow)
docker logs -f ecomweb_api_blue
docker logs -f ecomweb_cron
docker logs -f ecomweb_worker

# View last 100 lines
docker logs --tail 100 ecomweb_cron

# Check service health
docker ps --format "table {{.Names}}\t{{.Status}}"

# PM2 process list
docker exec ecomweb_cron pm2 list
docker exec ecomweb_worker pm2 list

# PM2 logs
docker exec ecomweb_cron pm2 logs
docker exec ecomweb_worker pm2 logs --err

# PM2 monitoring
docker exec -it ecomweb_api_blue pm2 monit
```

## Health Checks

```bash
# API health
curl http://localhost:3001/health

# HAProxy stats
open http://localhost:8404

# Cron health check
docker exec ecomweb_cron bash /app/healthcheck-cron.sh

# Worker health check
docker exec ecomweb_worker bash /app/healthcheck-worker.sh

# Database connectivity
docker exec ecomweb_cron npx prisma db execute --stdin <<< "SELECT 1"
```

## Troubleshooting

```bash
# Access container shell
docker exec -it ecomweb_cron bash

# Check environment variables
docker exec ecomweb_cron env | grep -E "NODE_ENV|SERVICE_TYPE|SHUTDOWN_GRACE"

# Check running processes
docker exec ecomweb_cron ps aux

# Check PM2 status
docker exec ecomweb_cron pm2 status

# Restart unhealthy service
docker-compose stop -t 90 ecomweb_cron
docker-compose up -d ecomweb_cron

# View startup logs
docker logs ecomweb_cron | grep -A 20 "Starting"

# Check shutdown logs
docker logs ecomweb_cron | grep -A 20 "Graceful shutdown"

# Force rebuild
docker-compose up -d --force-recreate ecomweb_cron
```

## Emergency Procedures

```bash
# Force stop (NOT RECOMMENDED - jobs will be killed)
docker-compose stop -t 0 ecomweb_cron

# Restart all background services
docker-compose restart ecomweb_cron ecomweb_worker

# Rollback deployment
./deploy.sh rollback 1.2.2

# Check what's using resources
docker stats

# Prune unused resources
docker system prune -a
```

## Configuration

```bash
# Edit environment
vim .env.api

# Reload after config change
docker-compose stop -t 90 ecomweb_cron
docker-compose up -d ecomweb_cron

# Change grace period
# Edit docker-compose.yml:
#   SHUTDOWN_GRACE_PERIOD=120
#   stop_grace_period: 150s
docker-compose up -d ecomweb_cron
```

## Grace Periods Reference

| Service | Shutdown Grace | Docker Stop | Use Case |
|---------|----------------|-------------|----------|
| Cron | 60s | 90s | Short cron jobs |
| Worker | 120s | 150s | Temporal workflows |
| API | Default | 10s | HTTP requests |

## Common Issues

### Jobs Getting Killed
```bash
# Increase grace period in docker-compose.yml
environment:
  - SHUTDOWN_GRACE_PERIOD=180
stop_grace_period: 210s

# Then restart
docker-compose up -d ecomweb_cron
```

### Service Won't Start
```bash
# Check logs
docker logs ecomweb_cron --tail 100

# Check database connectivity
docker exec ecomweb_cron npx prisma db execute --stdin <<< "SELECT 1"

# Increase max_attempts in startup script
# Edit startup-cron.sh: max_attempts=60
```

### Health Check Failing
```bash
# Test health check manually
docker exec ecomweb_cron bash /app/healthcheck-cron.sh
echo $?  # Should be 0

# Check PM2 status
docker exec ecomweb_cron pm2 list

# Check script permissions
docker exec ecomweb_cron ls -la /app/*.sh
```

## Environment Variables

### Required in .env.api
```bash
DATABASE_URL=postgresql://user:pass@host:5432/dbname
REDIS_URL=redis://ecomweb-redis:6379
TEMPORAL_ADDRESS=temporal.example.com:7233
NODE_ENV=production
```

### Required for deployment
```bash
export API_BLUE_IMAGE=ghcr.io/travistech20/ecomweb-api:1.2.3
export API_GREEN_IMAGE=ghcr.io/travistech20/ecomweb-api:1.2.3
```

### Optional overrides
```bash
export SHUTDOWN_GRACE_PERIOD=180
```

## Service Status Indicators

```bash
# Healthy states
Up 5 minutes (healthy)
Up 5 minutes

# Unhealthy states
Up 5 minutes (unhealthy)
Restarting
Exit 1

# Starting states
Up 5 seconds (health: starting)
```

## PM2 Process States

```bash
# Healthy
online    # Process running normally

# Unhealthy
stopped   # Process stopped
errored   # Process crashed
stopping  # Graceful shutdown in progress
```

## File Locations

```bash
# PM2 configs
/app/ecosystem.api.config.js
/app/ecosystem.cron.config.js
/app/ecosystem.worker.config.js

# Startup scripts
/app/startup-api.sh
/app/startup-cron.sh
/app/startup-worker.sh

# Shutdown scripts
/app/graceful-shutdown.sh

# Health checks
/app/healthcheck-cron.sh
/app/healthcheck-worker.sh

# Application
/app/dist/main.js
```

## Useful Docker Commands

```bash
# List all containers
docker ps -a

# Remove stopped containers
docker container prune

# View resource usage
docker stats

# Inspect container
docker inspect ecomweb_cron

# Copy file from container
docker cp ecomweb_cron:/app/logs/error.log ./

# Copy file to container
docker cp ./new-config.js ecomweb_cron:/app/config.js

# Network troubleshooting
docker network ls
docker network inspect ecomweb_internal_net
```

## Deployment Checklist

- [ ] Pull new image version
- [ ] Stop cron gracefully (90s)
- [ ] Stop worker gracefully (150s)
- [ ] Deploy new API version
- [ ] Wait for health check
- [ ] Switch traffic (HAProxy/Kong)
- [ ] Restart cron with new version
- [ ] Restart worker with new version
- [ ] Verify health checks
- [ ] Monitor logs for errors
- [ ] Test critical endpoints

## Rollback Checklist

- [ ] Identify last working version
- [ ] Stop current services gracefully
- [ ] Deploy previous image version
- [ ] Wait for health checks
- [ ] Switch traffic back
- [ ] Verify functionality
- [ ] Document incident
- [ ] Plan hotfix

## Monitoring URLs

```bash
# Local development
API Health:      http://localhost:3001/health
HAProxy Stats:   http://localhost:8404 (admin/admin123)

# Production (replace with your domain)
API Health:      https://api.yourdomain.com/health
HAProxy Stats:   https://haproxy.yourdomain.com:8404
```

## Documentation Links

- [README.md](README.md) - Overview and quick start
- [DEPLOYMENT.md](DEPLOYMENT.md) - Detailed deployment guide
- [ARCHITECTURE.md](ARCHITECTURE.md) - Architecture documentation
- [GRACEFUL_SHUTDOWN.md](GRACEFUL_SHUTDOWN.md) - Shutdown procedures

---

**💡 Tip**: Bookmark this file for quick access during deployments and troubleshooting!
