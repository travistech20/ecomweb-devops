#!/bin/bash
set -e

# Script to check PostgreSQL replication status
# Usage: ./check-replication-status.sh

echo "=========================================="
echo "PostgreSQL Replication Status Check"
echo "=========================================="
echo ""

# Check if primary database is running
if ! docker ps | grep -q supabase-db; then
    echo "❌ Primary database (supabase-db) is not running!"
    exit 1
fi

echo "✅ Primary database is running"
echo ""

# Check replication status on primary
echo "📊 Replication Status on Primary:"
echo "-----------------------------------"
docker exec supabase-db psql -U postgres -d postgres -c "
SELECT 
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_priority,
    replay_lag
FROM pg_stat_replication;
" 2>/dev/null || echo "No active replicas connected"

echo ""
echo "📊 Replication Slots on Primary:"
echo "-----------------------------------"
docker exec supabase-db psql -U postgres -d postgres -c "
SELECT 
    slot_name,
    slot_type,
    database,
    active,
    restart_lsn,
    confirmed_flush_lsn
FROM pg_replication_slots;
" 2>/dev/null

echo ""

# Check replica 1
if docker ps | grep -q supabase-db-replica-1; then
    echo "✅ Replica 1 is running"
    echo "📊 Replica 1 Status:"
    echo "-----------------------------------"
    docker exec supabase-db-replica-1 psql -U postgres -d postgres -c "
    SELECT 
        pg_is_in_recovery() as is_replica,
        pg_last_wal_receive_lsn() as receive_lsn,
        pg_last_wal_replay_lsn() as replay_lsn,
        pg_last_xact_replay_timestamp() as last_replay_time;
    " 2>/dev/null || echo "Replica 1 not ready yet"
    echo ""
else
    echo "❌ Replica 1 (supabase-db-replica-1) is not running"
    echo ""
fi

# Check replica 2
if docker ps | grep -q supabase-db-replica-2; then
    echo "✅ Replica 2 is running"
    echo "📊 Replica 2 Status:"
    echo "-----------------------------------"
    docker exec supabase-db-replica-2 psql -U postgres -d postgres -c "
    SELECT 
        pg_is_in_recovery() as is_replica,
        pg_last_wal_receive_lsn() as receive_lsn,
        pg_last_wal_replay_lsn() as replay_lsn,
        pg_last_xact_replay_timestamp() as last_replay_time;
    " 2>/dev/null || echo "Replica 2 not ready yet"
    echo ""
else
    echo "❌ Replica 2 (supabase-db-replica-2) is not running"
    echo ""
fi

echo "=========================================="
echo "Replication Lag Summary:"
echo "=========================================="
docker exec supabase-db psql -U postgres -d postgres -c "
SELECT 
    application_name,
    CASE 
        WHEN replay_lag IS NULL THEN 'N/A'
        ELSE replay_lag::text
    END as replication_lag,
    state
FROM pg_stat_replication;
" 2>/dev/null || echo "No replicas connected"

echo ""
echo "✅ Replication status check completed!"
