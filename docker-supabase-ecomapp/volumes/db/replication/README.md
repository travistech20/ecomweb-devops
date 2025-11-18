# PostgreSQL Replication Configuration

This directory contains initialization scripts for PostgreSQL streaming replication.

## Files

### init-primary-replication.sql

SQL script executed during primary database initialization to:
- Create the `replicator` user with replication privileges and MD5 password
- Create physical replication slots for each replica (`replica_1_slot`, `replica_2_slot`)
- Grant necessary permissions

**When it runs**: Automatically during primary database first startup (via docker-entrypoint-initdb.d)

**Location in container**: `/docker-entrypoint-initdb.d/init-scripts/97-replication.sql`

### configure-pg-hba.sh

Shell script to configure PostgreSQL client authentication for replication:
- Auto-detects the actual pg_hba.conf location (Supabase uses `/etc/postgresql/pg_hba.conf`)
- Adds `hostnossl` entries to allow non-SSL replication connections
- Uses MD5 authentication for the replicator user
- Reloads PostgreSQL configuration after changes

**When it runs**: Automatically during primary database first startup (via docker-entrypoint-initdb.d)

**Location in container**: `/docker-entrypoint-initdb.d/init-scripts/96-configure-pg-hba.sh`

**Key features:**
- Idempotent (safe to run multiple times)
- Auto-detects pg_hba.conf location using `SHOW hba_file;`
- Uses `pkill -HUP postgres` for configuration reload

### init-replica.sh

**NEW**: Shared initialization script used by all replica containers to eliminate code duplication:
- Waits for primary database to be ready
- Performs pg_basebackup if data directory is empty
- Configures replica-specific settings (listen_addresses, primary_slot_name, etc.)
- Fixes ownership and permissions
- Starts PostgreSQL as postgres user

**When it runs**: Container entrypoint for both db-replica-1 and db-replica-2

**Location in container**: `/init-replica.sh` (mounted read-only from host)

**Environment variables used:**
- `REPLICA_SLOT_NAME`: Identifies which replication slot to use (replica_1_slot or replica_2_slot)
- Standard PostgreSQL variables (POSTGRES_PASSWORD, POSTGRES_DB, etc.)

**Key benefits:**
- Single source of truth for replica initialization
- Easier maintenance and updates
- Consistent behavior across all replicas

## How Replication Works

### Primary Database Setup

1. **Initialization** (automatic on first start):
   ```
   init-primary-replication.sql → Creates replicator user and slots
   configure-pg-hba.sh → Configures authentication
   ```

2. **Runtime configuration** (built into Supabase image):
   - `wal_level = replica`
   - `max_wal_senders = 10`
   - `max_replication_slots = 10`

### Replica Database Setup

Replicas use the **shared init-replica.sh script** mounted from this directory. The script handles:

1. **Wait for primary** to be healthy
2. **pg_basebackup** to clone initial data (with `-R` flag for automatic standby setup)
3. **standby.signal** creation (automatic via pg_basebackup -R)
4. **postgresql.auto.conf** configuration with:
   - `listen_addresses = '*'` (allow external connections)
   - `primary_conninfo` (automatic via pg_basebackup -R)
   - `primary_slot_name` (replica_1_slot or replica_2_slot)
   - Replication tuning parameters
5. **Ownership fix** with `chown -R postgres:postgres`
6. **Permission fix** with `chmod 700` on data directory
7. **Start PostgreSQL** as postgres user with `gosu`

Each replica is differentiated by the `REPLICA_SLOT_NAME` environment variable in docker-compose.yml.

## Replication Slots

Physical replication slots ensure WAL segments are retained for replicas:

- **replica_1_slot** - For db-replica-1
- **replica_2_slot** - For db-replica-2

### Why Replication Slots?

Slots prevent the primary from removing WAL segments that replicas still need, even if a replica is temporarily disconnected. This prevents replication from breaking when a replica goes offline.

### Monitoring Slots

```bash
# Check replication slot status
docker exec supabase-db psql -U postgres -c "
SELECT slot_name, slot_type, active, restart_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as retained_wal
FROM pg_replication_slots;"
```

### Managing Slots

```bash
# Drop a slot if replica is permanently removed
docker exec supabase-db psql -U postgres -c "
SELECT pg_drop_replication_slot('replica_1_slot');"

# Create a new slot
docker exec supabase-db psql -U postgres -c "
SELECT pg_create_physical_replication_slot('replica_1_slot');"
```

## Authentication Configuration

### pg_hba.conf Entries

The configure-pg-hba.sh script adds these entries to `/etc/postgresql/pg_hba.conf`:

```
# Replication connections (added for streaming replication)
hostnossl    replication     replicator      all                     md5
hostnossl    replication     all             all                     md5
```

**Why `hostnossl`?**
- The Supabase image doesn't enable SSL by default (`ssl = off`)
- Using `hostnossl` explicitly allows non-encrypted replication connections
- In production, consider enabling SSL and changing to `hostssl`

### Replication User

- **Username**: `replicator`
- **Password**: Set via `REPLICATION_PASSWORD` in `.env` (default: `replicator_password`)
- **Privileges**: `REPLICATION` and `LOGIN` only (minimal access)
- **Authentication**: MD5 password hash

## Directory Structure

```
volumes/db/replication/
├── README.md                        # This file
├── init-primary-replication.sql     # Creates replicator user and slots (primary)
├── configure-pg-hba.sh              # Configures authentication (primary)
└── init-replica.sh                  # Shared replica initialization script
```

## Archive Directory

WAL archives for point-in-time recovery are stored in `volumes/db/archive/`:

```bash
# View archived WAL files
ls -lh volumes/db/archive/
```

**Important**: In production, archive WAL files to external storage (S3, etc.) for disaster recovery.

## Troubleshooting

### Replication User Issues

```bash
# Check if replicator user exists
docker exec supabase-db psql -U postgres -c "\du replicator"

# Recreate if needed
docker exec supabase-db psql -U postgres -c "
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_password';"
```

### Replication Slot Issues

```bash
# Check slot status
docker exec supabase-db psql -U postgres -c "
SELECT * FROM pg_replication_slots;"

# Create missing slot
docker exec supabase-db psql -U postgres -c "
SELECT pg_create_physical_replication_slot('replica_1_slot');"

# Drop and recreate slot if corrupted
docker exec supabase-db psql -U postgres -c "
SELECT pg_drop_replication_slot('replica_1_slot');
SELECT pg_create_physical_replication_slot('replica_1_slot');"
```

### pg_hba.conf Issues

```bash
# Check actual pg_hba.conf location
docker exec supabase-db psql -U postgres -c "SHOW hba_file;"

# View current pg_hba.conf
docker exec supabase-db cat /etc/postgresql/pg_hba.conf

# Verify replication entries exist
docker exec supabase-db grep "replication" /etc/postgresql/pg_hba.conf

# Reload configuration after manual changes
docker exec supabase-db bash -c "pkill -HUP postgres"
```

### Permission Issues

```bash
# Ensure scripts are executable
chmod +x volumes/db/replication/*.sh

# Check PostgreSQL is running as postgres user
docker exec supabase-db whoami  # Should show 'postgres' when DB is running
```

## Security Notes

### Production Recommendations

1. **Change default password**: Update `REPLICATION_PASSWORD` in `.env`
2. **Enable SSL/TLS**: Modify pg_hba.conf to use `hostssl` instead of `hostnossl`
3. **Restrict network access**: Use specific IP ranges instead of `all` in pg_hba.conf
4. **Use strong passwords**: Generate cryptographically random passwords
5. **Rotate credentials**: Periodically update replication passwords

### SSL/TLS Setup (Production)

To enable SSL for replication:

1. Generate SSL certificates for PostgreSQL
2. Mount certificates in docker-compose.yml
3. Enable SSL in postgresql.conf: `ssl = on`
4. Update pg_hba.conf to use `hostssl` instead of `hostnossl`
5. Update replica connection strings to require SSL

## See Also

- [../../scripts/replication/README.md](../../scripts/replication/README.md) - Management scripts
- [../../docker-compose.yml](../../docker-compose.yml) - Container configuration
- PostgreSQL official documentation on streaming replication
