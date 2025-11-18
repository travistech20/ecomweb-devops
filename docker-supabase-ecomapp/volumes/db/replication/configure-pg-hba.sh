#!/bin/bash
set -e

# This script configures pg_hba.conf to allow replication connections
# It runs after PostgreSQL initialization

echo "Configuring pg_hba.conf for replication..."

# Detect the actual pg_hba.conf file location
PG_HBA_CONF=$(psql -U postgres -t -c "SHOW hba_file;" 2>/dev/null | xargs || echo "/etc/postgresql/pg_hba.conf")

echo "Using pg_hba.conf at: $PG_HBA_CONF"

if [ ! -f "$PG_HBA_CONF" ]; then
    echo "Error: pg_hba.conf not found at $PG_HBA_CONF"
    exit 1
fi

# Check if replication entry already exists
if grep -q "# Replication connections (added for streaming replication)" "$PG_HBA_CONF"; then
    echo "Replication entries already exist in pg_hba.conf"
else
    echo "Adding replication entries to pg_hba.conf..."

    # Add replication entries using hostnossl for non-SSL connections
    cat >> "$PG_HBA_CONF" <<EOF

# Replication connections (added for streaming replication)
hostnossl    replication     replicator      all                     md5
hostnossl    replication     all             all                     md5
EOF

    echo "Replication entries added to pg_hba.conf"
fi

# Reload PostgreSQL configuration if server is running
if pg_isready -U postgres -h localhost &> /dev/null; then
    echo "Reloading PostgreSQL configuration..."
    # Use pkill for reload since pg_reload_conf() may not have permission
    pkill -HUP postgres || psql -U postgres -c "SELECT pg_reload_conf();" || true
fi

echo "pg_hba.conf configuration completed!"
