#!/bin/bash

# ============================================
# Supabase Database Restore Script
# ============================================
# This script restores a database from a backup file

set -e  # Exit on any error

# Configuration
BACKUP_DIR="${BACKUP_DIR:-./volumes/backups}"
CONTAINER_NAME="${DB_CONTAINER:-supabase-db}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show usage
show_usage() {
    echo "Usage: $0 [BACKUP_FILE]"
    echo ""
    echo "Restore database from a backup file."
    echo ""
    echo "Options:"
    echo "  BACKUP_FILE    Path to the backup file (optional, will show menu if not provided)"
    echo ""
    echo "Environment variables:"
    echo "  DB_CONTAINER   Database container name (default: supabase-db)"
    echo "  POSTGRES_DB    Database name (default: postgres)"
    echo "  POSTGRES_USER  Database user (default: postgres)"
    echo "  BACKUP_DIR     Backup directory (default: ./volumes/backups)"
    echo ""
    echo "Examples:"
    echo "  $0                                           # Interactive mode"
    echo "  $0 ./volumes/backups/backup_20241115.sql.gz  # Restore specific backup"
}

# Check for help flag
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "Container ${CONTAINER_NAME} is not running!"
    exit 1
fi

# Determine backup file
BACKUP_FILE="$1"

if [ -z "${BACKUP_FILE}" ]; then
    # Interactive mode - show available backups
    log_info "Available backups:"
    echo ""

    # Create array of backup files (macOS/Linux compatible)
    mapfile -t BACKUPS < <(find "${BACKUP_DIR}" -name "*.sql*" -type f -print0 | xargs -0 ls -t)

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        log_error "No backup files found in ${BACKUP_DIR}"
        exit 1
    fi

    # Display backups with numbers
    for i in "${!BACKUPS[@]}"; do
        backup="${BACKUPS[$i]}"
        filename=$(basename "${backup}")
        filesize=$(du -h "${backup}" | cut -f1)
        # macOS/Linux compatible timestamp
        if [[ "$OSTYPE" == "darwin"* ]]; then
            timestamp=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "${backup}" 2>/dev/null)
        else
            timestamp=$(stat -c "%y" "${backup}" 2>/dev/null | cut -d'.' -f1)
        fi
        echo "  $((i+1)). ${filename} (${filesize}) - ${timestamp}"
    done

    echo ""
    read -p "Select backup number to restore (1-${#BACKUPS[@]}), or 'q' to quit: " selection

    if [ "${selection}" = "q" ] || [ "${selection}" = "Q" ]; then
        log_info "Restore cancelled"
        exit 0
    fi

    # Validate selection
    if ! [[ "${selection}" =~ ^[0-9]+$ ]] || [ "${selection}" -lt 1 ] || [ "${selection}" -gt ${#BACKUPS[@]} ]; then
        log_error "Invalid selection"
        exit 1
    fi

    BACKUP_FILE="${BACKUPS[$((selection-1))]}"
fi

# Verify backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    log_error "Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

# Warning confirmation
log_warning "⚠️  WARNING: This will REPLACE the current database with the backup!"
log_warning "⚠️  Current data will be LOST!"
echo ""
log_info "Backup file: ${BACKUP_FILE}"
log_info "Container: ${CONTAINER_NAME}"
log_info "Database: ${POSTGRES_DB}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "${confirm}" != "yes" ]; then
    log_info "Restore cancelled"
    exit 0
fi

# Perform restore
log_info "Starting database restore..."

# Create a pre-restore backup
PRE_RESTORE_BACKUP="${BACKUP_DIR}/pre_restore_backup_$(date +%Y%m%d_%H%M%S).sql.gz"
log_info "Creating pre-restore backup: ${PRE_RESTORE_BACKUP}"

docker exec "${CONTAINER_NAME}" pg_dump \
    -U "${POSTGRES_USER}" \
    -d "${POSTGRES_DB}" \
    --format=plain \
    --no-owner \
    --no-acl \
    | gzip > "${PRE_RESTORE_BACKUP}"

log_success "Pre-restore backup created"

# Step 1: Terminate all connections to the database
log_info "Terminating active database connections..."
docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${POSTGRES_DB}'
AND pid <> pg_backend_pid();
" > /dev/null 2>&1 || true

# Step 2: Clean schemas (Self-hosted Supabase)
# Clean public, auth, and storage schemas
# Preserves system schemas (extensions, realtime, vault, etc.)
log_info "Cleaning public, auth, and storage schemas for restore..."
docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" << 'EOF'
-- Drop objects in public, auth, and storage schemas CASCADE to handle dependencies
DO $$
DECLARE
    r RECORD;
    schema_name TEXT;
BEGIN
    -- Clean public, auth, and storage schemas
    FOR schema_name IN SELECT unnest(ARRAY['public', 'auth', 'storage'])
    LOOP
        -- Drop all tables
        FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = schema_name) LOOP
            EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(schema_name) || '.' || quote_ident(r.tablename) || ' CASCADE';
        END LOOP;

        -- Drop all sequences
        FOR r IN (SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = schema_name) LOOP
            EXECUTE 'DROP SEQUENCE IF EXISTS ' || quote_ident(schema_name) || '.' || quote_ident(r.sequence_name) || ' CASCADE';
        END LOOP;

        -- Drop all views
        FOR r IN (SELECT table_name FROM information_schema.views WHERE table_schema = schema_name) LOOP
            EXECUTE 'DROP VIEW IF EXISTS ' || quote_ident(schema_name) || '.' || quote_ident(r.table_name) || ' CASCADE';
        END LOOP;

        -- Drop all functions
        FOR r IN (SELECT routine_name FROM information_schema.routines WHERE routine_schema = schema_name AND routine_type = 'FUNCTION') LOOP
            EXECUTE 'DROP FUNCTION IF EXISTS ' || quote_ident(schema_name) || '.' || quote_ident(r.routine_name) || ' CASCADE';
        END LOOP;

        -- Drop all types (enums, composite types, etc.)
        FOR r IN (SELECT t.typname
                  FROM pg_type t
                  JOIN pg_namespace n ON t.typnamespace = n.oid
                  WHERE n.nspname = schema_name AND t.typtype = 'e') LOOP
            EXECUTE 'DROP TYPE IF EXISTS ' || quote_ident(schema_name) || '.' || quote_ident(r.typname) || ' CASCADE';
        END LOOP;
    END LOOP;
END $$;
EOF

log_success "Schemas cleaned (public, auth, storage)"

# Step 3: Restore from backup
log_info "Restoring data from backup..."

# Determine if backup is compressed and restore accordingly
if [[ "${BACKUP_FILE}" == *.gz ]]; then
    log_info "Detected compressed backup, decompressing and restoring..."
    # Suppress expected Supabase errors (permissions, schema already exists, etc.)
    gunzip -c "${BACKUP_FILE}" | docker exec -i "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" 2>&1 | \
        grep -vE "^(ERROR:  must be owner|ERROR:  permission denied|ERROR:  schema .* already exists)" | \
        grep "^ERROR:" || true
else
    log_info "Restoring uncompressed backup..."
    docker exec -i "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" < "${BACKUP_FILE}" 2>&1 | \
        grep -vE "^(ERROR:  must be owner|ERROR:  permission denied|ERROR:  schema .* already exists)" | \
        grep "^ERROR:" || true
fi

# Step 4: Fix permissions for Supabase auth & storage (self-hosted)
log_info "Fixing permissions for Supabase auth and storage schemas..."

# Capture both stdout and stderr to detect any issues
PERMISSION_OUTPUT=$(docker exec -i "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" 2>&1 << 'EOF'
-- Fix ownership of auth schema objects to supabase_auth_admin
ALTER SCHEMA auth OWNER TO supabase_auth_admin;
DO $$
DECLARE
    r RECORD;
    table_count INTEGER := 0;
    sequence_count INTEGER := 0;
    view_count INTEGER := 0;
BEGIN
    -- Change ownership of all tables in auth schema
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'auth' LOOP
        EXECUTE 'ALTER TABLE auth.' || quote_ident(r.tablename) || ' OWNER TO supabase_auth_admin';
        table_count := table_count + 1;
    END LOOP;
    RAISE NOTICE 'Auth: Changed ownership of % tables', table_count;

    -- Change ownership of all sequences
    FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'auth' LOOP
        EXECUTE 'ALTER SEQUENCE auth.' || quote_ident(r.sequence_name) || ' OWNER TO supabase_auth_admin';
        sequence_count := sequence_count + 1;
    END LOOP;
    RAISE NOTICE 'Auth: Changed ownership of % sequences', sequence_count;

    -- Change ownership of all views
    FOR r IN SELECT table_name FROM information_schema.views WHERE table_schema = 'auth' LOOP
        EXECUTE 'ALTER VIEW auth.' || quote_ident(r.table_name) || ' OWNER TO supabase_auth_admin';
        view_count := view_count + 1;
    END LOOP;
    RAISE NOTICE 'Auth: Changed ownership of % views', view_count;
END $$;

-- Grant necessary permissions to supabase_auth_admin role for auth schema
GRANT USAGE ON SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA auth TO supabase_auth_admin;

-- Grant read permissions to authenticator role (used by PostgREST)
GRANT USAGE ON SCHEMA auth TO authenticator;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO authenticator;

-- Fix ownership of storage schema objects to supabase_storage_admin
ALTER SCHEMA storage OWNER TO supabase_storage_admin;
DO $$
DECLARE
    r RECORD;
    table_count INTEGER := 0;
    sequence_count INTEGER := 0;
    view_count INTEGER := 0;
BEGIN
    -- Change ownership of all tables in storage schema
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'storage' LOOP
        EXECUTE 'ALTER TABLE storage.' || quote_ident(r.tablename) || ' OWNER TO supabase_storage_admin';
        table_count := table_count + 1;
    END LOOP;
    RAISE NOTICE 'Storage: Changed ownership of % tables', table_count;

    -- Change ownership of all sequences
    FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'storage' LOOP
        EXECUTE 'ALTER SEQUENCE storage.' || quote_ident(r.sequence_name) || ' OWNER TO supabase_storage_admin';
        sequence_count := sequence_count + 1;
    END LOOP;
    RAISE NOTICE 'Storage: Changed ownership of % sequences', sequence_count;

    -- Change ownership of all views
    FOR r IN SELECT table_name FROM information_schema.views WHERE table_schema = 'storage' LOOP
        EXECUTE 'ALTER VIEW storage.' || quote_ident(r.table_name) || ' OWNER TO supabase_storage_admin';
        view_count := view_count + 1;
    END LOOP;
    RAISE NOTICE 'Storage: Changed ownership of % views', view_count;
END $$;

-- Grant permissions for storage schema to supabase_storage_admin
GRANT USAGE ON SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO supabase_storage_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA storage TO supabase_storage_admin;

-- Grant API access to storage schema for service_role (used by Storage API)
GRANT USAGE ON SCHEMA storage TO service_role;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA storage TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA storage TO service_role;

-- Grant storage access to API roles (used by PostgREST and client access)
GRANT USAGE ON SCHEMA storage TO authenticator;
GRANT SELECT ON ALL TABLES IN SCHEMA storage TO authenticator;
GRANT USAGE ON SCHEMA storage TO anon;
GRANT SELECT ON ALL TABLES IN SCHEMA storage TO anon;
GRANT USAGE ON SCHEMA storage TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA storage TO authenticated;

-- Set default privileges for future objects in auth schema
ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON FUNCTIONS TO supabase_auth_admin;

-- Set default privileges for future objects in storage schema
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON TABLES TO supabase_storage_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON SEQUENCES TO supabase_storage_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA storage GRANT ALL ON FUNCTIONS TO supabase_storage_admin;

\echo 'PERMISSION_FIX_COMPLETE'
EOF
)

# Check if the permission fix completed successfully
if echo "${PERMISSION_OUTPUT}" | grep -q "PERMISSION_FIX_COMPLETE"; then
    # Extract and show the NOTICE messages about counts
    echo "${PERMISSION_OUTPUT}" | grep "NOTICE:" | sed 's/NOTICE:  /  /'
    log_success "Permissions fixed for auth and storage schemas"
else
    log_error "Permission fix may have failed!"
    log_error "Output: ${PERMISSION_OUTPUT}"
    # Don't exit - continue with verification
fi

# Step 4.1: Verify schema ownership
log_info "Verifying schema ownership..."
OWNERSHIP_CHECK=$(docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c "
SELECT
    CASE
        WHEN (SELECT nspowner::regrole::text FROM pg_namespace WHERE nspname = 'auth') = 'supabase_auth_admin'
         AND (SELECT nspowner::regrole::text FROM pg_namespace WHERE nspname = 'storage') = 'supabase_storage_admin'
        THEN 'OK'
        ELSE 'FAILED'
    END;
" 2>/dev/null | tr -d ' ')

if [ "${OWNERSHIP_CHECK}" = "OK" ]; then
    log_success "Schema ownership verified"
else
    log_warning "Schema ownership verification failed - auth service may not work correctly"
    log_warning "You may need to run the permission fix manually"
fi

# Step 5: Verify restore
log_info "Verifying database restoration..."

# Check if database exists and has tables
TABLE_COUNT=$(docker exec "${CONTAINER_NAME}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')

if [ -n "${TABLE_COUNT}" ] && [ "${TABLE_COUNT}" -gt 0 ]; then
    log_success "Database restored successfully with ${TABLE_COUNT} tables"
    log_success "Restore completed from: ${BACKUP_FILE}"
    log_info "Pre-restore backup saved at: ${PRE_RESTORE_BACKUP}"
    log_warning "Remember to restart dependent services if needed"
else
    log_error "Database restore may have failed - no tables found"
    log_warning "You can restore the pre-restore backup if needed:"
    log_warning "  bash $0 ${PRE_RESTORE_BACKUP}"
    exit 1
fi
