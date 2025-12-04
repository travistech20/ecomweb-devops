#!/bin/bash

# ============================================
# Supabase Permission Fix Script
# ============================================
# This script fixes ownership and permissions for auth and storage schemas
# Run this after database restore if auth service is not working

set -e  # Exit on any error

# Configuration
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
    echo "Usage: $0"
    echo ""
    echo "Fix ownership and permissions for Supabase auth and storage schemas."
    echo ""
    echo "Environment variables:"
    echo "  DB_CONTAINER   Database container name (default: supabase-db)"
    echo "  POSTGRES_DB    Database name (default: postgres)"
    echo "  POSTGRES_USER  Database user (default: postgres)"
    echo ""
    echo "This script is automatically run during database restore, but can be"
    echo "run manually if auth service stops working after restore."
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

log_info "Fixing permissions for Supabase auth and storage schemas..."
log_info "Container: ${CONTAINER_NAME}"
log_info "Database: ${POSTGRES_DB}"
echo ""

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
    echo ""
    log_info "Permission changes:"
    # Extract and show the NOTICE messages about counts
    echo "${PERMISSION_OUTPUT}" | grep "NOTICE:" | sed 's/NOTICE:  /  /'
    echo ""
    log_success "Permissions fixed for auth and storage schemas"
else
    log_error "Permission fix may have failed!"
    log_error "Output:"
    echo "${PERMISSION_OUTPUT}"
    exit 1
fi

# Verify schema ownership
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
    echo ""
    log_success "✓ All permissions fixed successfully!"
    log_info "Auth service should now work correctly"
else
    log_error "Schema ownership verification failed"
    exit 1
fi
