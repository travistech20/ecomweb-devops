#!/bin/bash
# Script to configure replication on an existing production database
# Run this once to set up replication on a database that's already running

set -e

echo "=== Configuring Production Primary Database for Replication ==="
echo ""

# Detect the actual pg_hba.conf file location
echo "1. Detecting pg_hba.conf location..."
PG_HBA_FILE=$(docker exec supabase-db psql -U postgres -t -c "SHOW hba_file;" | xargs)
echo "   Found: $PG_HBA_FILE"
echo ""

# Check if replication entries already exist
echo "2. Checking for existing replication entries..."
if docker exec supabase-db grep -q "# Replication connections (added for streaming replication)" "$PG_HBA_FILE" 2>/dev/null; then
    echo "   ℹ️  Replication entries already exist in pg_hba.conf"
else
    echo "   Adding replication entries to pg_hba.conf..."

    docker exec supabase-db bash -c "cat >> $PG_HBA_FILE <<'EOF'

# Replication connections (added for streaming replication)
hostnossl    replication     replicator      all                     md5
hostnossl    replication     all             all                     md5
EOF"

    echo "   ✓ Replication entries added"
fi
echo ""

# Create replication user
echo "3. Creating replication user..."
docker exec supabase-db psql -U postgres <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'replicator') THEN
        CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_password';
        RAISE NOTICE 'Created replication user: replicator';
    ELSE
        RAISE NOTICE 'Replication user already exists: replicator';
    END IF;
END
$$;
SQL
echo ""

# Create replication slots
echo "4. Creating replication slots..."
docker exec supabase-db psql -U postgres <<'SQL'
SELECT pg_create_physical_replication_slot('replica_1_slot')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_1_slot'
);

SELECT pg_create_physical_replication_slot('replica_2_slot')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_2_slot'
);
SQL
echo ""

# Reload PostgreSQL configuration
echo "5. Reloading PostgreSQL configuration..."
docker exec supabase-db bash -c "pkill -HUP postgres"
echo "   ✓ Configuration reloaded"
echo ""

# Verify setup
echo "6. Verifying replication setup..."
echo ""
echo "Replication user:"
docker exec supabase-db psql -U postgres -c "SELECT rolname, rolreplication FROM pg_roles WHERE rolname = 'replicator';"
echo ""
echo "Replication slots:"
docker exec supabase-db psql -U postgres -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"
echo ""
echo "pg_hba.conf replication entries:"
docker exec supabase-db grep "replication" "$PG_HBA_FILE" | grep -v "^#"
echo ""

echo "=== ✅ Primary database is ready for replication! ==="
echo ""
echo "Next steps:"
echo "  1. Add REPLICATION_PASSWORD to your .env file"
echo "  2. Start the replica: docker compose up -d db-replica-1"
echo "  3. Check status: ./scripts/replication/check-replication-status.sh"
