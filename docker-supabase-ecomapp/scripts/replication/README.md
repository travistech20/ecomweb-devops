# PostgreSQL Replication Management

Helper scripts for monitoring and testing PostgreSQL streaming replication.

## Overview

PostgreSQL replication is configured automatically via docker-compose.yml. These utility scripts help you monitor and verify replication health.

## Available Scripts

### check-replication-status.sh

Check the status of PostgreSQL replication including lag, connection state, and replica health.

```bash
./scripts/replication/check-replication-status.sh
```

**Output includes:**
- Primary database status
- Active replication connections
- Replication slots status
- Replica recovery status
- Replication lag metrics

### test-replication.sh

Test replication by creating a test table on primary and verifying it appears on replicas.

```bash
./scripts/replication/test-replication.sh
```

**What it does:**
1. Creates a test table on primary
2. Inserts test data with timestamp
3. Waits for replication
4. Verifies data appears on both replicas
5. Cleans up test table

## Architecture

### Automatic Setup

Replication is configured automatically when you start the containers:

```bash
docker compose up -d db db-replica-1 db-replica-2
```

The setup includes:
- **Primary**: Replication user creation, pg_hba.conf configuration
- **Replicas**: Automatic pg_basebackup, standby configuration

### Configuration Files

**Primary database initialization:**
- `volumes/db/replication/init-primary-replication.sql` - Creates replicator user and replication slots
- `volumes/db/replication/configure-pg-hba.sh` - Configures authentication for replication

**Replica configuration:**
- Inline in `docker-compose.yml` for db-replica-1 and db-replica-2
- Automatic base backup using pg_basebackup
- Automatic standby.signal and connection configuration

## Usage Examples

### Daily Health Check

```bash
# Run this daily to monitor replication health
./scripts/replication/check-replication-status.sh
```

### After Primary Updates

```bash
# After updating primary, verify replicas are syncing
./scripts/replication/test-replication.sh
```

### Rebuild a Replica

If a replica needs to be rebuilt:

```bash
# Stop and remove the replica
docker compose stop db-replica-1
docker compose rm -f db-replica-1

# Clean the data directory
rm -rf ./volumes/db-replica-1/data/*

# Restart - it will automatically perform pg_basebackup
docker compose up -d db-replica-1

# Verify it's working
./scripts/replication/check-replication-status.sh
```

## Monitoring

### Quick Status Check

```bash
# Check replication from primary
docker exec supabase-db psql -U postgres -c "
SELECT application_name, client_addr, state, sync_state
FROM pg_stat_replication;"

# Check replica status
docker exec supabase-db-replica-1 psql -U postgres -c "
SELECT pg_is_in_recovery();"
```

### Replication Lag

```bash
# Check lag in bytes
docker exec supabase-db psql -U postgres -c "
SELECT
    application_name,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) as lag_bytes,
    state
FROM pg_stat_replication;"
```

### Monitoring Recommendations

Set up automated alerts for:

1. **Replication Lag**: Alert if > 10 seconds
2. **Replica Connection**: Alert if replica disconnects
3. **Replication Slot Usage**: Alert if slots are inactive
4. **Disk Space**: Monitor WAL archive directory

## Troubleshooting

### Replica Won't Start

Check logs:
```bash
docker logs supabase-db-replica-1
```

Common issues:
- **Permission denied**: Fixed automatically with `gosu postgres`
- **pg_hba.conf error**: Automatically configured at primary startup
- **Connection timeout**: Check network and primary health

### Replication Lag Issues

```bash
# Check WAL sender processes
docker exec supabase-db psql -U postgres -c "
SELECT * FROM pg_stat_replication;"

# Check for long-running queries on replica
docker exec supabase-db-replica-1 psql -U postgres -c "
SELECT pid, usename, state, query_start, query
FROM pg_stat_activity
WHERE state = 'active';"
```

### Manual Intervention

If automatic setup fails, you can manually trigger pg_basebackup:

```bash
# Inside replica container
PGPASSWORD=replicator_password pg_basebackup \
  -h db \
  -p 5432 \
  -U replicator \
  -D /var/lib/postgresql/data \
  -Fp -Xs -P -R -v
```

## Advanced Configuration

### Connection Information

- **Primary**: `localhost:54322`
- **Replica 1**: `localhost:54325`
- **Replica 2**: `localhost:54326`

### Replication User

- **Username**: `replicator`
- **Password**: Set in `.env` as `REPLICATION_PASSWORD`

### Replication Slots

```bash
# View replication slots
docker exec supabase-db psql -U postgres -c "
SELECT slot_name, slot_type, active, restart_lsn
FROM pg_replication_slots;"
```

## See Also

- [docker-compose.yml](../../docker-compose.yml) - Container configuration
- Main project documentation for database setup
