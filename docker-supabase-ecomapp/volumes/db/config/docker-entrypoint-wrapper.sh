#!/bin/bash
# Docker entrypoint wrapper that applies pg_hba.conf before starting PostgreSQL
# This ensures the configuration persists across container restarts

set -e

PERSISTENT_CONFIG="/config/pg_hba.conf"
TARGET_CONFIG="/etc/postgresql/pg_hba.conf"

echo "=== Applying Persistent PostgreSQL Configuration ==="

# Apply pg_hba.conf if it exists
if [ -f "$PERSISTENT_CONFIG" ]; then
    echo "Copying persistent pg_hba.conf to $TARGET_CONFIG..."
    cp "$PERSISTENT_CONFIG" "$TARGET_CONFIG"
    chmod 644 "$TARGET_CONFIG"
    chown postgres:postgres "$TARGET_CONFIG"
    echo "✓ pg_hba.conf applied successfully!"

    # Verify replication entries
    if grep -q "replicator" "$TARGET_CONFIG"; then
        echo "✓ Replication entries found in pg_hba.conf"
    else
        echo "⚠ Warning: No replication entries found!"
    fi
else
    echo "⚠ Warning: Persistent pg_hba.conf not found at $PERSISTENT_CONFIG"
    echo "   Using default configuration"
fi

echo "=== Starting PostgreSQL ==="
echo ""

# Execute the original entrypoint with all passed arguments
exec /usr/local/bin/docker-entrypoint.sh "$@"
