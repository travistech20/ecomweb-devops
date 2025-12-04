#!/bin/bash

echo "=== Testing Prisma Read Replica Routing ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "1. Checking Primary Database Connection Status..."
PRIMARY_STATS=$(docker exec supabase-db psql -U postgres -d postgres -t -c "SELECT count(*) FROM pg_stat_activity WHERE datname='postgres';")
echo -e "${GREEN}✓ Primary DB has $PRIMARY_STATS active connections${NC}"
echo ""

echo "2. Checking Replica Database Status..."
REPLICA_RECOVERY=$(docker exec supabase-db-replica-1 psql -U postgres -d postgres -t -c "SELECT pg_is_in_recovery();")
if [[ "$REPLICA_RECOVERY" == *"t"* ]]; then
    echo -e "${GREEN}✓ Replica is in recovery mode (read-only)${NC}"
else
    echo -e "${RED}✗ Replica is NOT in recovery mode${NC}"
fi
echo ""

echo "3. Checking Replication Lag..."
docker exec supabase-db psql -U postgres -d postgres -c "
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    replay_lsn,
    pg_wal_lsn_diff(sent_lsn, replay_lsn) as lag_bytes,
    EXTRACT(EPOCH FROM (now() - reply_time)) as seconds_since_reply
FROM pg_stat_replication
WHERE application_name = 'walreceiver';"
echo ""

echo "4. Testing Direct Connection to Replica..."
docker exec supabase-db-replica-1 psql -U postgres -d postgres -c "SELECT 'Connected to replica!' as status, now() as current_time;"
echo ""

echo "5. Checking if tables exist on replica..."
TABLES=$(docker exec supabase-db-replica-1 psql -U postgres -d postgres -t -c "\dt" | wc -l)
echo -e "${YELLOW}Replica has $TABLES table entries${NC}"
echo ""

echo "6. Monitoring queries on Primary (run a read query from your app now)..."
echo -e "${YELLOW}Watching for new connections on Primary DB for 10 seconds...${NC}"
docker exec supabase-db psql -U postgres -d postgres -c "
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    LEFT(query, 80) as query_preview
FROM pg_stat_activity
WHERE datname = 'postgres'
AND state != 'idle'
AND pid != pg_backend_pid()
ORDER BY query_start DESC
LIMIT 10;"
echo ""

echo "7. Monitoring queries on Replica (run a read query from your app now)..."
echo -e "${YELLOW}Watching for connections on Replica DB...${NC}"
docker exec supabase-db-replica-1 psql -U postgres -d postgres -c "
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    query_start,
    LEFT(query, 80) as query_preview
FROM pg_stat_activity
WHERE datname = 'postgres'
AND state != 'idle'
AND pid != pg_backend_pid()
ORDER BY query_start DESC
LIMIT 10;"
echo ""

echo "=== Connection Details ==="
echo "Primary Database: supabase-db:5432"
echo "Replica Database: supabase-db-replica-1:5432 (accessible on host port 54325)"
echo ""
echo "To verify Prisma is using the replica:"
echo "1. Check if your Prisma schema has readReplicas configured"
echo "2. Enable query logging in Prisma"
echo "3. Check the database logs to see which DB receives read queries"
echo ""
echo -e "${YELLOW}Note: If Prisma is routing queries correctly, you should see:"
echo "  - Write queries (INSERT, UPDATE, DELETE) on Primary"
echo "  - Read queries (SELECT) on Replica${NC}"
