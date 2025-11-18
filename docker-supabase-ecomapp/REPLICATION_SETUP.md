# PostgreSQL Replication Setup - Production

This document describes the PostgreSQL read replica setup for the production environment.

## Overview

- **Primary Database** (`db` / `supabase-db`): Handles all write operations
  - Internal port: 5432
  - External port: Not exposed (internal only)

- **Replica 1** (`db-replica-1` / `supabase-db-replica-1`): Read-only replica
  - Internal port: 5432
  - External port: 54325
  - Replication slot: `replica_1_slot`

## Quick Start

### 1. Configure Environment Variables

Add to your `.env` file (if not already present):

```bash
# Replication configuration
REPLICATION_PASSWORD=<strong-random-password>
```

**Important**: Use a strong password and keep it secure!

### 2. Start Services

```bash
# If this is a fresh installation, start all services
docker compose up -d

# If upgrading existing installation, restart database to initialize replication
docker compose restart db

# Then start the replica
docker compose up -d db-replica-1
```

### 3. Verify Replication

```bash
# Check replica status
./scripts/replication/check-replication-status.sh

# Test replication with sample data
./scripts/replication/test-replication.sh
```

## Connection Information

**Production Environment:**
- Primary (write operations): `db:5432` (internal network only)
- Replica 1 (read operations): `db-replica-1:5432` (internal) or `localhost:54325` (external)

**Connection Strings:**
```bash
# Primary (internal)
postgresql://postgres:${POSTGRES_PASSWORD}@db:5432/postgres

# Replica 1 (internal)
postgresql://postgres:${POSTGRES_PASSWORD}@db-replica-1:5432/postgres

# Replica 1 (external - for monitoring/debugging)
postgresql://postgres:${POSTGRES_PASSWORD}@localhost:54325/postgres
```

## Architecture

### Automatic Setup

The replication setup is fully automated:

1. **Primary Database Initialization** (first start):
   - `configure-pg-hba.sh` configures authentication
   - `init-primary-replication.sql` creates replicator user and replication slot

2. **Replica Initialization** (automatic):
   - `init-replica.sh` waits for primary to be ready
   - Performs pg_basebackup to clone data
   - Configures standby mode
   - Starts streaming replication

### Configuration Files

```
volumes/db/replication/
├── README.md                    # Detailed documentation
├── init-primary-replication.sql # Primary setup
├── configure-pg-hba.sh          # Authentication config
└── init-replica.sh              # Shared replica init script
```

## Monitoring

### Quick Health Check

```bash
# Check all services
docker compose ps | grep db

# Check replication status
docker exec supabase-db psql -U postgres -c "\
SELECT application_name, client_addr, state, sync_state \
FROM pg_stat_replication;"
```

### Replication Lag

```bash
# Check lag in bytes
docker exec supabase-db psql -U postgres -c "\
SELECT \
    application_name, \
    pg_wal_lsn_diff(sent_lsn, replay_lsn) as lag_bytes, \
    state \
FROM pg_stat_replication;"
```

### Automated Monitoring Scripts

```bash
# Daily health check
./scripts/replication/check-replication-status.sh

# After primary updates
./scripts/replication/test-replication.sh
```

## Scaling to Multiple Replicas

To add more replicas in the future:

1. Update `init-primary-replication.sql` to add more slots:
   ```sql
   SELECT pg_create_physical_replication_slot('replica_2_slot')
   WHERE NOT EXISTS (
       SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_2_slot'
   );
   ```

2. Add replica service in `docker-compose.yml`:
   ```yaml
   db-replica-2:
     # Same configuration as db-replica-1
     # Update: ports, REPLICA_SLOT_NAME, volume names
   ```

3. Add volumes:
   ```yaml
   volumes:
     db-replica-2-data:
     db-replica-2-config:
   ```

## Troubleshooting

### Replica Won't Start

```bash
# Check logs
docker logs supabase-db-replica-1

# Common issues:
# 1. Primary not ready - wait for primary to be healthy
# 2. Permission errors - automatically fixed by init script
# 3. Connection errors - check REPLICATION_PASSWORD in .env
```

### Replication Lag

```bash
# Check for long-running queries on replica
docker exec supabase-db-replica-1 psql -U postgres -c "\
SELECT pid, usename, state, query_start, query \
FROM pg_stat_activity \
WHERE state = 'active';"
```

### Rebuild Replica

If replica gets out of sync:

```bash
# Stop replica
docker compose stop db-replica-1

# Remove volumes
docker volume rm supabase_db-replica-1-data supabase_db-replica-1-config

# Restart (will perform fresh pg_basebackup)
docker compose up -d db-replica-1
```

## Production Recommendations

### Security

1. **Change default password**: Update `REPLICATION_PASSWORD` in `.env`
2. **Enable SSL/TLS**: For production, enable SSL encryption for replication
3. **Network isolation**: Use Docker networks to isolate database traffic
4. **Firewall rules**: Only expose necessary ports

### Performance

1. **Monitor lag**: Set up alerts for replication lag > 10 seconds
2. **Resource allocation**: Ensure replicas have adequate CPU/memory
3. **Connection pooling**: Use pgBouncer or similar for connection management
4. **Read distribution**: Load balance read queries across replicas

### Backup Strategy

1. **Primary backups**: Continue existing backup schedule (2 AM daily)
2. **Replica verification**: Use replica for backup verification
3. **Point-in-time recovery**: WAL archiving enabled on primary
4. **Disaster recovery**: Keep backups in multiple locations

## See Also

- [volumes/db/replication/README.md](volumes/db/replication/README.md) - Complete replication guide
- [scripts/replication/README.md](scripts/replication/README.md) - Monitoring scripts documentation
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html) - Official documentation
