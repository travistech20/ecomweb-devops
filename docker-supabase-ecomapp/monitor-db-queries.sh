#!/bin/bash

echo "=== Real-time Database Query Monitor ==="
echo "This script monitors queries on both Primary and Replica databases"
echo "Press Ctrl+C to stop"
echo ""

# Function to monitor database
monitor_db() {
    local db_name=$1
    local container=$2
    local color=$3

    echo -e "${color}=== Monitoring $db_name ===${NC}"
    docker exec $container psql -U postgres -d postgres -c "
    SELECT
        now() as check_time,
        count(*) as active_queries,
        count(*) FILTER (WHERE query LIKE 'SELECT%') as select_queries,
        count(*) FILTER (WHERE query LIKE 'INSERT%' OR query LIKE 'UPDATE%' OR query LIKE 'DELETE%') as write_queries
    FROM pg_stat_activity
    WHERE datname = 'postgres'
    AND state = 'active'
    AND pid != pg_backend_pid();"
}

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

while true; do
    clear
    echo "=== Database Query Monitor ==="
    echo "Timestamp: $(date)"
    echo ""

    echo -e "${GREEN}PRIMARY DATABASE (supabase-db)${NC}"
    docker exec supabase-db psql -U postgres -d postgres -t -c "
    SELECT
        'Active Queries: ' || count(*) as stats
    FROM pg_stat_activity
    WHERE datname = 'postgres'
    AND state = 'active'
    AND pid != pg_backend_pid();"

    echo "Recent Queries (last 10 seconds):"
    docker exec supabase-db psql -U postgres -d postgres -c "
    SELECT
        usename,
        application_name,
        client_addr,
        LEFT(query, 100) as query_preview,
        state,
        query_start
    FROM pg_stat_activity
    WHERE datname = 'postgres'
    AND query_start > now() - interval '10 seconds'
    AND pid != pg_backend_pid()
    ORDER BY query_start DESC
    LIMIT 5;" 2>/dev/null

    echo ""
    echo -e "${BLUE}REPLICA DATABASE (supabase-db-replica-1)${NC}"
    docker exec supabase-db-replica-1 psql -U postgres -d postgres -t -c "
    SELECT
        'Active Queries: ' || count(*) as stats
    FROM pg_stat_activity
    WHERE datname = 'postgres'
    AND state = 'active'
    AND pid != pg_backend_pid();"

    echo "Recent Queries (last 10 seconds):"
    docker exec supabase-db-replica-1 psql -U postgres -d postgres -c "
    SELECT
        usename,
        application_name,
        client_addr,
        LEFT(query, 100) as query_preview,
        state,
        query_start
    FROM pg_stat_activity
    WHERE datname = 'postgres'
    AND query_start > now() - interval '10 seconds'
    AND pid != pg_backend_pid()
    ORDER BY query_start DESC
    LIMIT 5;" 2>/dev/null

    echo ""
    echo "Replication Status:"
    docker exec supabase-db psql -U postgres -d postgres -t -c "
    SELECT
        'Lag: ' || COALESCE(pg_wal_lsn_diff(sent_lsn, replay_lsn), 0) || ' bytes, ' ||
        'State: ' || state
    FROM pg_stat_replication
    WHERE application_name = 'walreceiver';" 2>/dev/null

    echo ""
    echo "Refreshing in 2 seconds... (Press Ctrl+C to stop)"
    sleep 2
done
