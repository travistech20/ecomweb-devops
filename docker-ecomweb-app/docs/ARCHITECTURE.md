# Architecture Summary

## Service Separation Strategy

### Problem Solved
Previously, all processes (API, cron, temporal worker) ran in a single container via PM2, making it difficult to:
- Scale individual components
- Manage resources efficiently
- Handle blue-green deployments for background services
- Debug and monitor specific service types

### Solution
Services are now separated into dedicated containers:

```
┌─────────────────────────────────────────────┐
│  docker-supabase-ecomapp (HAProxy)          │
│  - Load balancing                           │
│  - Blue-green traffic switching             │
└──────────────┬──────────────────────────────┘
               │
┌──────────────┴──────────────────────────────┐
│  docker-ecomweb-app                         │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ API Layer (Blue/Green)              │   │
│  │ - ecomweb_api_blue                  │   │
│  │ - ecomweb_api_green                 │   │
│  │ - PM2 cluster mode (max cores)      │   │
│  │ - Health checks                     │   │
│  │ - Runs migrations                   │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ Background Services                 │   │
│  │                                     │   │
│  │ ecomweb_cron                        │   │
│  │ - PM2 fork mode (1 instance)        │   │
│  │ - Scheduled tasks only              │   │
│  │ - Waits for DB ready                │   │
│  │                                     │   │
│  │ ecomweb_worker                      │   │
│  │ - PM2 cluster mode (2 instances)    │   │
│  │ - Temporal workflow processing      │   │
│  │ - Horizontally scalable             │   │
│  │ - Waits for DB ready                │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ Shared Services                     │   │
│  │ - ecomweb_redis (cache/sessions)    │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. No Hard Blue/Green Dependencies
**Problem**: Cron and worker services were originally set to `depends_on: ecomweb_api_blue`, but during blue-green deployment, blue might be down while green is active.

**Solution**:
- Removed hard dependencies on specific API color
- Services only depend on Redis
- Startup scripts wait for database readiness instead
- Database check happens via Prisma connection test

### 2. Database Readiness Check
**Why**: Migrations must complete before cron/worker can start, but we don't know which API instance (blue/green) will run them.

**Implementation**:
```bash
# In startup-cron.sh and startup-worker.sh
while [ $attempt -lt $max_attempts ]; do
    if npx prisma db execute --stdin <<< "SELECT 1" &>/dev/null; then
        echo "Database is ready!"
        break
    fi
    sleep 2
done
```

**Benefits**:
- Works regardless of which API instance is active
- Handles migration timing automatically
- Provides clear error messages on timeout

### 3. Separate PM2 Configs
Each service type has its own PM2 ecosystem config:

| Service | Config | Mode | Instances | Purpose |
|---------|--------|------|-----------|---------|
| API | `ecosystem.api.config.js` | cluster | max (all CPUs) | Handle HTTP requests |
| Cron | `ecosystem.cron.config.js` | fork | 1 | Prevent duplicate scheduled tasks |
| Worker | `ecosystem.worker.config.js` | cluster | 2 | Parallel task processing |

### 4. Independent Scaling
```bash
# Scale only workers without touching API or cron
docker-compose up -d --scale ecomweb_worker=5

# Or in docker-compose.yml
ecomweb_worker:
  deploy:
    replicas: 5
```

## Blue-Green Deployment Flow

### Current Setup
1. **HAProxy** (in `docker-supabase-ecomapp/`) manages traffic between blue/green
2. **Blue API** runs migrations on startup
3. **Green API** waits (initially disabled in HAProxy)
4. **Cron** and **Worker** connect to database (regardless of which API is active)

### Deployment Process
```bash
# 1. Deploy new version to green
export API_GREEN_IMAGE=ghcr.io/travistech20/ecomweb-api:v2.0.0
docker-compose up -d ecomweb_api_green

# 2. Green runs migrations automatically

# 3. Switch traffic in HAProxy (external to this compose file)
# Update haproxy.cfg in docker-supabase-ecomapp

# 4. Update cron and worker to new version
docker-compose up -d ecomweb_cron ecomweb_worker

# 5. When stable, update blue
export API_BLUE_IMAGE=ghcr.io/travistech20/ecomweb-api:v2.0.0
docker-compose up -d ecomweb_api_blue
```

## Environment Variables

### Required in `.env.api`
```bash
# Database connection (Prisma uses this)
DATABASE_URL=postgresql://user:pass@host:5432/dbname

# Redis connection
REDIS_URL=redis://ecomweb-redis:6379

# Temporal settings (for worker)
TEMPORAL_ADDRESS=temporal.example.com:7233
TEMPORAL_NAMESPACE=default

# API settings
PORT=3001
NODE_ENV=production
```

### Required in shell
```bash
# Set before running docker-compose
export API_BLUE_IMAGE=ghcr.io/travistech20/ecomweb-api:latest
export API_GREEN_IMAGE=ghcr.io/travistech20/ecomweb-api:latest
```

## File Structure
```
docker-ecomweb-app/
├── docker-compose.yml                    # Main orchestration
├── .env.api                              # Shared environment config
├── volumes/
│   └── backend-api/
│       ├── ecosystem.api.config.js       # API PM2 config
│       ├── ecosystem.cron.config.js      # Cron PM2 config
│       ├── ecosystem.worker.config.js    # Worker PM2 config
│       ├── startup-api.sh                # API startup script
│       ├── startup-cron.sh               # Cron startup script
│       └── startup-worker.sh             # Worker startup script
├── DEPLOYMENT.md                         # Detailed deployment guide
└── ARCHITECTURE.md                       # This file
```

## Resource Recommendations

### Production
```yaml
ecomweb_api_blue/green:
  cpus: '2.0'
  memory: 2G

ecomweb_cron:
  cpus: '0.5'
  memory: 512M

ecomweb_worker:
  cpus: '1.0'
  memory: 1G
```

### Development
```yaml
# Use defaults, or reduce for local testing
ecomweb_api_blue/green:
  cpus: '1.0'
  memory: 1G

ecomweb_cron:
  cpus: '0.25'
  memory: 256M

ecomweb_worker:
  cpus: '0.5'
  memory: 512M
```

## Monitoring Checklist

- [ ] API health checks responding: `curl http://localhost:3001/health`
- [ ] HAProxy stats accessible: `http://localhost:8404`
- [ ] Blue and Green API both listed in HAProxy backend
- [ ] Cron logs show successful startup
- [ ] Worker logs show Temporal connection
- [ ] Redis connections stable
- [ ] PM2 processes running in each container
- [ ] Database migrations completed successfully

## Common Commands

```bash
# Start everything
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker logs -f ecomweb_api_blue
docker logs -f ecomweb_cron
docker logs -f ecomweb_worker

# Scale workers
docker-compose up -d --scale ecomweb_worker=3

# Restart specific service
docker-compose restart ecomweb_cron

# Access container shell
docker exec -it ecomweb_api_blue bash

# Check PM2 inside container
docker exec ecomweb_api_blue pm2 list
docker exec ecomweb_cron pm2 list
docker exec ecomweb_worker pm2 list

# Test database connectivity
docker exec ecomweb_cron npx prisma db execute --stdin <<< "SELECT 1"
```

## Migration from Old Setup

If you had the old single-container setup:

### Before (Old)
```yaml
ecomweb_api:
  volumes:
    - ./ecosystem.config.js  # Single config with all 3 processes
```

### After (New)
```yaml
ecomweb_api_blue:
  volumes:
    - ./ecosystem.api.config.js  # API only

ecomweb_cron:
  volumes:
    - ./ecosystem.cron.config.js  # Cron only

ecomweb_worker:
  volumes:
    - ./ecosystem.worker.config.js  # Worker only
```

### Migration Steps
1. Stop old containers: `docker-compose down`
2. Update docker-compose.yml with new service definitions
3. Add new PM2 configs and startup scripts
4. Start new setup: `docker-compose up -d`
5. Verify all services: `docker-compose ps && docker-compose logs`

## Benefits Summary

✅ **Scalability**: Scale workers independently of API
✅ **Reliability**: Cron/worker survive API restarts
✅ **Blue-Green Compatible**: No hard dependencies on API color
✅ **Resource Efficiency**: Dedicated resources per service type
✅ **Debuggability**: Clear separation makes issues easier to isolate
✅ **Flexibility**: Deploy updates to specific service types
✅ **Fault Isolation**: Cron crash doesn't affect API or workers
