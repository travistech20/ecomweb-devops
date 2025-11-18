# Ecommerce API Deployment

High-availability deployment setup with separated services and graceful shutdown support.

## Quick Start

```bash
# Set environment variables
export API_BLUE_IMAGE=ghcr.io/travistech20/ecomweb-api:latest
export API_GREEN_IMAGE=ghcr.io/travistech20/ecomweb-api:latest

# Start all services
docker-compose up -d

# Check status
docker-compose ps
```

## Architecture

Services are separated for better scalability and reliability:

- **API Services** (blue/green): Handle HTTP requests, run in PM2 cluster mode
- **Cron Service**: Runs scheduled tasks, single instance
- **Worker Service**: Processes Temporal workflows, horizontally scalable
- **Redis**: Shared cache and session store

Load balancing is handled by HAProxy in `docker-supabase-ecomapp/`.

## Deployment

### Automated Deployment (Recommended)

```bash
./deploy.sh 1.2.3
```

This handles:
- Blue-green deployment with HAProxy traffic switching
- Graceful shutdown of cron/worker (before deployment)
- Health checks (container + HAProxy)
- Gradual traffic shift (100% → 0%)
- Automatic restart of background services

See [docs/HAPROXY_DEPLOYMENT.md](docs/HAPROXY_DEPLOYMENT.md) for details.

### Manual Deployment

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for step-by-step instructions.

## Graceful Shutdown

Cron and worker services implement graceful shutdown to prevent job interruption:

- **Cron**: 90s grace period for jobs to complete
- **Worker**: 150s grace period for workflows to complete

```bash
# Graceful restart
docker-compose stop -t 90 ecomweb_cron
docker-compose up -d ecomweb_cron
```

See [docs/GRACEFUL_SHUTDOWN.md](docs/GRACEFUL_SHUTDOWN.md) for details.

## Key Features

✅ **High Availability**: Multiple API instances with load balancing
✅ **Blue-Green Deployment**: Zero-downtime deployments
✅ **Graceful Shutdown**: Jobs complete before container stops
✅ **Service Separation**: Dedicated containers for API, cron, and workers
✅ **Independent Scaling**: Scale workers without affecting API
✅ **Health Checks**: Automated health monitoring
✅ **Database Safety**: Services wait for migrations before starting

## Documentation

- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) - Detailed deployment guide with troubleshooting
- [docs/HAPROXY_DEPLOYMENT.md](docs/HAPROXY_DEPLOYMENT.md) - HAProxy blue-green deployment guide
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - Architecture decisions and design patterns
- [docs/GRACEFUL_SHUTDOWN.md](docs/GRACEFUL_SHUTDOWN.md) - Graceful shutdown implementation details
- [docs/QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md) - Quick command reference

## Common Commands

```bash
# View logs
docker logs -f ecomweb_api_blue
docker logs -f ecomweb_cron
docker logs -f ecomweb_worker

# Scale workers
docker-compose up -d --scale ecomweb_worker=3

# Check health
docker ps --format "table {{.Names}}\t{{.Status}}"

# Access container
docker exec -it ecomweb_api_blue bash

# Check PM2 processes
docker exec ecomweb_cron pm2 list
```

## Grace Periods

| Service | Shutdown Grace | Docker Stop Grace | Purpose |
|---------|---------------|-------------------|---------|
| Cron | 60s | 90s | Allow cron jobs to complete |
| Worker | 120s | 150s | Allow workflows to finish |

Adjust via `SHUTDOWN_GRACE_PERIOD` environment variable.

## Monitoring

- **API Health**: `curl http://localhost/health`
- **HAProxy Stats**: `http://localhost:8404` (admin/admin123)
- **Service Status**: `docker-compose ps`
- **PM2 Status**: `docker exec <container> pm2 list`

## Files Overview

```
docker-ecomweb-app/
├── docker-compose.yml              # Service orchestration
├── .env.api                        # Shared configuration
├── deploy.sh                       # Automated deployment script
├── rollback.sh                     # Rollback script
├── docs/                           # Documentation
│   ├── DEPLOYMENT.md               # Deployment guide
│   ├── HAPROXY_DEPLOYMENT.md       # HAProxy deployment guide
│   ├── ARCHITECTURE.md             # Architecture documentation
│   ├── GRACEFUL_SHUTDOWN.md        # Graceful shutdown guide
│   └── QUICK_REFERENCE.md          # Quick command reference
├── volumes/backend-api/
│   ├── ecosystem.api.config.js     # PM2 config for API
│   ├── ecosystem.cron.config.js    # PM2 config for cron
│   ├── ecosystem.worker.config.js  # PM2 config for worker
│   ├── startup-api.sh              # API startup + migrations
│   ├── startup-cron.sh             # Cron startup + signal handling
│   ├── startup-worker.sh           # Worker startup + signal handling
│   ├── graceful-shutdown.sh        # Graceful shutdown logic
│   ├── healthcheck-cron.sh         # Cron health check
│   └── healthcheck-worker.sh       # Worker health check
└── README.md                       # This file
```

## Environment Variables

Required in `.env.api`:

```bash
DATABASE_URL=postgresql://...
REDIS_URL=redis://ecomweb-redis:6379
TEMPORAL_ADDRESS=temporal.example.com:7233
NODE_ENV=production
```

Required for deployment:

```bash
export API_BLUE_IMAGE=ghcr.io/travistech20/ecomweb-api:latest
export API_GREEN_IMAGE=ghcr.io/travistech20/ecomweb-api:latest
```

## Support

For issues or questions:
1. Check [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) troubleshooting section
2. Review logs: `docker-compose logs`
3. Verify health checks: `docker ps`
4. Check application logs in PM2: `docker exec <container> pm2 logs`

## License

Internal use only - Ecommerce API deployment
