#!/bin/bash
set -e

# Script to test PostgreSQL replication
# This creates a test table on primary and verifies it appears on replicas

echo "=========================================="
echo "PostgreSQL Replication Test"
echo "=========================================="
echo ""

# Create test table on primary
echo "📝 Creating test table on primary..."
docker exec supabase-db psql -U postgres -d postgres <<-EOSQL
    DROP TABLE IF EXISTS replication_test;
    CREATE TABLE replication_test (
        id SERIAL PRIMARY KEY,
        test_data TEXT,
        created_at TIMESTAMP DEFAULT NOW()
    );
    
    INSERT INTO replication_test (test_data) 
    VALUES ('Test data created at ' || NOW());
    
    SELECT * FROM replication_test;
EOSQL

echo ""
echo "⏳ Waiting 5 seconds for replication to propagate..."
sleep 5

# Check replica 1
echo ""
echo "🔍 Checking Replica 1..."
if docker ps | grep -q supabase-db-replica-1; then
    docker exec supabase-db-replica-1 psql -U postgres -d postgres -c "
    SELECT * FROM replication_test;
    " 2>/dev/null && echo "✅ Replica 1: Data replicated successfully!" || echo "❌ Replica 1: Replication failed or not ready"
else
    echo "❌ Replica 1 is not running"
fi

# Check replica 2
echo ""
echo "🔍 Checking Replica 2..."
if docker ps | grep -q supabase-db-replica-2; then
    docker exec supabase-db-replica-2 psql -U postgres -d postgres -c "
    SELECT * FROM replication_test;
    " 2>/dev/null && echo "✅ Replica 2: Data replicated successfully!" || echo "❌ Replica 2: Replication failed or not ready"
else
    echo "❌ Replica 2 is not running"
fi

# Cleanup
echo ""
echo "🧹 Cleaning up test table..."
docker exec supabase-db psql -U postgres -d postgres -c "DROP TABLE IF EXISTS replication_test;"

echo ""
echo "✅ Replication test completed!"
