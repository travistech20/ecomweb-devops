# Graceful Shutdown Guide

## Overview

This document explains how graceful shutdown is implemented for cron and worker services to prevent job interruption during deployments.

## Problem Statement

During deployment, if cron or worker containers are abruptly stopped:
- **Cron jobs** may be terminated mid-execution
- **Temporal workflows** may fail or need to be retried
- **Data processing** could be left in an inconsistent state
- **Long-running tasks** would be forcibly killed

## Solution Architecture

### Components

1. **Graceful Shutdown Script** (`graceful-shutdown.sh`)
   - Handles SIGTERM signals
   - Waits for PM2 processes to complete
   - Configurable grace period

2. **Docker Stop Configuration**
   - `stop_grace_period`: Time Docker waits before SIGKILL
   - `stop_signal`: SIGTERM for graceful shutdown
   - Health checks to verify service status

3. **PM2 Signal Handling**
   - PM2 forwards SIGTERM to child processes
   - Node.js app can handle graceful shutdown
   - Processes have time to finish current tasks

4. **Startup Script Enhancements**
   - Trap SIGTERM/SIGINT signals
   - Execute graceful-shutdown.sh on signal
   - Wait for PM2 to complete

## Configuration

### Grace Periods

| Service | Shutdown Grace Period | Docker Stop Grace Period | Reasoning |
|---------|----------------------|--------------------------|-----------|
| Cron | 60s | 90s | Most cron jobs complete in <1 minute |
| Worker | 120s | 150s | Temporal workflows can be longer |

### Environment Variables

```bash
# In docker-compose.yml
SHUTDOWN_GRACE_PERIOD=60   # For cron
SHUTDOWN_GRACE_PERIOD=120  # For worker
```

## How It Works

### Normal Shutdown Flow

```
1. docker-compose stop ecomweb_cron
   ↓
2. Docker sends SIGTERM to container
   ↓
3. Startup script trap catches SIGTERM
   ↓
4. graceful-shutdown.sh executes
   ↓
5. PM2 receives "stop all" command
   ↓
6. PM2 sends SIGTERM to worker processes
   ↓
7. Node.js processes begin graceful shutdown
   ↓
8. Script waits up to SHUTDOWN_GRACE_PERIOD
   ↓
9. If processes complete: exit 0
   If timeout: PM2 force kill
   ↓
10. Container stops cleanly
```

### Deployment Flow

```
1. New version ready
   ↓
2. Deploy script: docker-compose stop -t 90 ecomweb_cron
   ↓
3. Cron completes running jobs (up to 90s)
   ↓
4. Deploy script: docker-compose stop -t 150 ecomweb_worker
   ↓
5. Workers complete workflows (up to 150s)
   ↓
6. Switch API traffic to new version
   ↓
7. Restart cron and worker with new version
   ↓
8. Services connect to new API
```

## Usage

### Manual Graceful Restart

```bash
# Cron service
docker-compose stop -t 90 ecomweb_cron
docker-compose up -d ecomweb_cron

# Worker service
docker-compose stop -t 150 ecomweb_worker
docker-compose up -d ecomweb_worker
```

### Using Deployment Script

The `deploy.sh` script automatically handles graceful shutdown:

```bash
./deploy.sh 1.2.3
```

The script will:
1. Deploy new API version to idle slot
2. Wait for health check
3. **Gracefully stop cron (90s grace period)**
4. **Gracefully stop worker (150s grace period)**
5. Switch traffic to new API
6. Restart cron and worker

### Emergency Stop (Force)

If you need to force stop immediately (not recommended):

```bash
# Force stop without grace period
docker-compose stop -t 0 ecomweb_cron
docker-compose stop -t 0 ecomweb_worker
```

## Monitoring Graceful Shutdown

### Check Shutdown Progress

```bash
# Watch cron shutdown
docker logs -f ecomweb_cron

# Watch worker shutdown
docker logs -f ecomweb_worker
```

### Expected Log Output

```
[cron] Starting graceful shutdown (grace period: 60s)...
[cron] Sending SIGTERM to PM2 processes...
[cron] Waiting for processes to complete... (0s/60s)
[cron] Waiting for processes to complete... (2s/60s)
...
[cron] All processes completed successfully
[cron] Shutdown complete
```

### Timeout Warning

If grace period expires:

```
[worker] WARNING: Grace period expired, some processes may still be running
[worker] Force stopping remaining processes...
[worker] Shutdown complete
```

## Health Checks

### Cron Health Check

Located at: `healthcheck-cron.sh`

```bash
# Check cron health
docker exec ecomweb_cron bash /app/healthcheck-cron.sh

# Expected output if healthy: (exit code 0)
# Expected output if unhealthy: (exit code 1)
```

### Worker Health Check

Located at: `healthcheck-worker.sh`

```bash
# Check worker health
docker exec ecomweb_worker bash /app/healthcheck-worker.sh
```

### Docker Health Status

```bash
# View health status
docker ps --format "table {{.Names}}\t{{.Status}}"

# Expected output:
# ecomweb_cron      Up 2 minutes (healthy)
# ecomweb_worker    Up 2 minutes (healthy)
```

## Application-Level Considerations

### For Cron Jobs (NestJS)

Your cron jobs should handle graceful shutdown:

```typescript
// src/cron/example.cron.ts
import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';

@Injectable()
export class ExampleCron implements OnModuleDestroy {
  private isShuttingDown = false;
  private currentJobPromise: Promise<any> | null = null;

  @Cron('0 * * * *') // Every hour
  async handleCron() {
    if (this.isShuttingDown) {
      console.log('Shutdown in progress, skipping cron execution');
      return;
    }

    this.currentJobPromise = this.doWork();
    await this.currentJobPromise;
    this.currentJobPromise = null;
  }

  async onModuleDestroy() {
    this.isShuttingDown = true;
    console.log('Waiting for current cron job to complete...');

    if (this.currentJobPromise) {
      await this.currentJobPromise;
    }

    console.log('Cron job completed, safe to shutdown');
  }

  private async doWork() {
    // Your cron logic here
    console.log('Cron job running...');
    await new Promise(resolve => setTimeout(resolve, 5000));
    console.log('Cron job finished');
  }
}
```

### For Temporal Workers (NestJS)

Temporal workers handle graceful shutdown automatically, but you can enhance it:

```typescript
// src/temporal/worker.service.ts
import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Worker } from '@temporalio/worker';

@Injectable()
export class TemporalWorkerService implements OnModuleDestroy {
  private worker: Worker;

  async onModuleDestroy() {
    console.log('Shutting down Temporal worker gracefully...');

    // Temporal Worker.shutdown() waits for:
    // - Current workflows to complete
    // - Activities to finish
    // - Graceful task queue drain
    await this.worker.shutdown();

    console.log('Temporal worker shutdown complete');
  }
}
```

### Main Application

Ensure your main.ts handles SIGTERM:

```typescript
// src/main.ts
async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Enable graceful shutdown
  app.enableShutdownHooks();

  // Handle SIGTERM
  process.on('SIGTERM', async () => {
    console.log('SIGTERM received, starting graceful shutdown...');
    await app.close();
    console.log('Application closed gracefully');
    process.exit(0);
  });

  await app.listen(3001);
}
```

## Troubleshooting

### Issue: Jobs Still Getting Killed

**Symptoms**: Jobs terminate mid-execution despite graceful shutdown

**Solutions**:
1. Increase grace period:
   ```yaml
   # In docker-compose.yml
   environment:
     - SHUTDOWN_GRACE_PERIOD=180  # 3 minutes
   stop_grace_period: 210s
   ```

2. Check if app handles SIGTERM:
   ```bash
   docker exec ecomweb_cron ps aux
   # Verify Node.js process is receiving signals
   ```

3. Review application shutdown logic:
   ```bash
   docker logs ecomweb_cron | grep -i "shutdown\|sigterm"
   ```

### Issue: Shutdown Takes Too Long

**Symptoms**: Containers take full grace period to stop

**Solutions**:
1. Reduce grace period if jobs are short:
   ```yaml
   environment:
     - SHUTDOWN_GRACE_PERIOD=30
   ```

2. Check for stuck processes:
   ```bash
   docker exec ecomweb_cron pm2 list
   docker exec ecomweb_cron pm2 logs --err
   ```

3. Verify no infinite loops or blocking operations

### Issue: Health Check Failures

**Symptoms**: Container marked as unhealthy during operation

**Solutions**:
1. Check health script permissions:
   ```bash
   docker exec ecomweb_cron ls -la /app/healthcheck-cron.sh
   chmod +x healthcheck-cron.sh
   ```

2. Test health check manually:
   ```bash
   docker exec ecomweb_cron bash /app/healthcheck-cron.sh
   echo $?  # Should be 0
   ```

3. Review PM2 process status:
   ```bash
   docker exec ecomweb_cron pm2 list
   ```

## Best Practices

### 1. Set Appropriate Grace Periods
- Short jobs (< 30s): `SHUTDOWN_GRACE_PERIOD=60`
- Medium jobs (30s - 2min): `SHUTDOWN_GRACE_PERIOD=120`
- Long jobs (> 2min): `SHUTDOWN_GRACE_PERIOD=300`

### 2. Implement Idempotent Jobs
- Jobs should be safe to retry
- Use database locks to prevent duplicates
- Track job execution state

### 3. Monitor Shutdown Times
```bash
# Add to monitoring
docker events --filter event=stop --filter container=ecomweb_cron
```

### 4. Test Graceful Shutdown
```bash
# In development/staging
docker-compose stop -t 90 ecomweb_cron
docker logs ecomweb_cron --tail 100

# Verify:
# - No error logs
# - Jobs completed
# - Clean PM2 shutdown
```

### 5. Use Deployment Maintenance Windows
For critical jobs, schedule deployments during low-activity periods

### 6. Implement Job Queues
For very long jobs, consider:
- BullMQ with Redis
- Temporal workflows (already implemented)
- These handle interruptions better than cron

## Grace Period Calculation

```
Recommended Grace Period = (Max Job Duration × 1.5) + 30s buffer

Examples:
- Job takes 60s max → Grace Period = (60 × 1.5) + 30 = 120s
- Job takes 30s max → Grace Period = (30 × 1.5) + 30 = 75s
- Job takes 120s max → Grace Period = (120 × 1.5) + 30 = 210s
```

## Related Files

- [docker-compose.yml](docker-compose.yml) - Service definitions with grace periods
- [graceful-shutdown.sh](volumes/backend-api/graceful-shutdown.sh) - Shutdown logic
- [startup-cron.sh](volumes/backend-api/startup-cron.sh) - Cron startup with signal handling
- [startup-worker.sh](volumes/backend-api/startup-worker.sh) - Worker startup with signal handling
- [healthcheck-cron.sh](volumes/backend-api/healthcheck-cron.sh) - Cron health check
- [healthcheck-worker.sh](volumes/backend-api/healthcheck-worker.sh) - Worker health check
- [deploy.sh](deploy.sh) - Deployment script with graceful shutdown
- [DEPLOYMENT.md](DEPLOYMENT.md) - General deployment guide

## Summary

✅ **Graceful shutdown prevents job interruption**
✅ **Configurable grace periods per service type**
✅ **Automatic integration with deployment script**
✅ **Health checks verify service status**
✅ **Application-level shutdown hooks supported**
✅ **Production-ready with proper error handling**
