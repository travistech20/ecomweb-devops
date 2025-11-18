-- Initialize Primary Database for Replication
-- This script is executed on the primary database during initialization

-- Create replication user
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

-- Create replication slot for each replica (optional but recommended)
SELECT pg_create_physical_replication_slot('replica_1_slot')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_1_slot'
);

SELECT pg_create_physical_replication_slot('replica_2_slot')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_replication_slots WHERE slot_name = 'replica_2_slot'
);

-- Grant necessary permissions
GRANT CONNECT ON DATABASE postgres TO replicator;

-- Show replication status
SELECT * FROM pg_stat_replication;
SELECT * FROM pg_replication_slots;
