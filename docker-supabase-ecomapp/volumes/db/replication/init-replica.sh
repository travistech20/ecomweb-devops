#!/bin/bash
set -e

# This script initializes a PostgreSQL streaming replica
# It's designed to be used in docker-compose with the following environment variables:
# - POSTGRES_PASSWORD: Primary database password
# - POSTGRES_DB: Database name
# - POSTGRES_PORT: PostgreSQL port
# - REPLICATION_PASSWORD: Replication user password
# - REPLICA_SLOT_NAME: Name of the replication slot (e.g., replica_1_slot)

echo "=== PostgreSQL Replica Initialization ==="

# Wait for primary to be ready
echo "Waiting for primary database..."
until PGPASSWORD="${POSTGRES_PASSWORD}" psql -h db -U postgres -d "${POSTGRES_DB}" -c '\q' 2>/dev/null; do
  sleep 5
done
echo "✓ Primary database is ready"

# Check if data directory needs initialization
if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
  echo "Initializing replica from primary..."

  # Ensure directory is completely empty
  rm -rf /var/lib/postgresql/data/*
  rm -rf /var/lib/postgresql/data/.[!.]*

  # Perform base backup
  echo "Starting pg_basebackup..."
  PGPASSWORD="${REPLICATION_PASSWORD}" pg_basebackup \
    -h db \
    -p "${POSTGRES_PORT}" \
    -U replicator \
    -D /var/lib/postgresql/data \
    -Fp \
    -Xs \
    -P \
    -R \
    -v

  echo "✓ Base backup completed"

  # Configure replication (pg_basebackup -R already created standby.signal and primary_conninfo)
  cat >> /var/lib/postgresql/data/postgresql.auto.conf <<EOF
listen_addresses = '*'
primary_slot_name = '${REPLICA_SLOT_NAME}'
hot_standby_feedback = on
max_standby_streaming_delay = 30s
wal_receiver_status_interval = 10s
EOF

  # Fix ownership and permissions of data directory (needed because pg_basebackup runs as root)
  chown -R postgres:postgres /var/lib/postgresql/data
  chmod 700 /var/lib/postgresql/data

  echo "✓ Replica configuration completed"
else
  echo "Data directory already initialized, starting replica..."
fi

# Start PostgreSQL as postgres user
echo "Starting PostgreSQL..."
exec gosu postgres postgres -c log_min_messages=fatal
