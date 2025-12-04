#!/bin/bash

# ============================================
# Enable RLS for All Tables Script
# ============================================
# This script enables Row Level Security (RLS) for all tables
# in the public schema of your Supabase/PostgreSQL database

set -e  # Exit on any error

# Configuration
CONTAINER_NAME="${DB_CONTAINER:-supabase-db}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
DRY_RUN="${DRY_RUN:-false}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_table() {
    echo -e "${CYAN}  → ${NC}$1"
}

# Display banner
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Enable RLS for All Tables          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

log_info "Container: ${CONTAINER_NAME}"
log_info "Database: ${POSTGRES_DB}"
log_info "User: ${POSTGRES_USER}"

if [ "${DRY_RUN}" = "true" ]; then
    log_warning "DRY RUN MODE - No changes will be made"
fi

echo ""

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "Container ${CONTAINER_NAME} is not running!"
    log_info "Start your database with: docker-compose up -d"
    exit 1
fi

# Function to execute SQL query
execute_sql() {
    local query="$1"
    docker exec "${CONTAINER_NAME}" psql \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        -c "${query}" \
        2>&1
}

# Function to execute SQL query silently (suppress output)
execute_sql_quiet() {
    local query="$1"
    docker exec "${CONTAINER_NAME}" psql \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        -t \
        -A \
        -c "${query}" \
        2>/dev/null
}

# Get list of all tables in public schema
log_info "Fetching tables from public schema..."

TABLES=$(execute_sql_quiet "
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
    ORDER BY tablename;
")

if [ -z "$TABLES" ]; then
    log_warning "No tables found in public schema!"
    exit 0
fi

# Count tables
TABLE_COUNT=$(echo "$TABLES" | wc -l | tr -d ' ')
log_info "Found ${TABLE_COUNT} tables in public schema"
echo ""

# Check current RLS status
log_info "Current RLS status:"
RLS_STATUS=$(execute_sql_quiet "
    SELECT
        tablename,
        CASE
            WHEN rowsecurity THEN 'ENABLED'
            ELSE 'DISABLED'
        END as rls_status
    FROM pg_tables t
    JOIN pg_class c ON c.relname = t.tablename
    WHERE t.schemaname = 'public'
    ORDER BY tablename;
")

while IFS='|' read -r table status; do
    if [ "$status" = "ENABLED" ]; then
        echo -e "  ${GREEN}✓${NC} ${table}: ${status}"
    else
        echo -e "  ${RED}✗${NC} ${table}: ${status}"
    fi
done <<< "$RLS_STATUS"

echo ""

# Enable RLS for each table
if [ "${DRY_RUN}" = "true" ]; then
    log_info "Tables that would have RLS enabled:"
    echo "$TABLES" | while read -r table; do
        if [ -n "$table" ]; then
            log_table "$table"
        fi
    done
    echo ""
    log_info "To actually enable RLS, run: DRY_RUN=false $0"
    exit 0
fi

log_info "Enabling RLS for all tables..."
echo ""

ENABLED_COUNT=0
ALREADY_ENABLED_COUNT=0
FAILED_COUNT=0

while read -r table; do
    if [ -n "$table" ]; then
        # Check if RLS is already enabled
        IS_ENABLED=$(execute_sql_quiet "
            SELECT rowsecurity
            FROM pg_tables t
            JOIN pg_class c ON c.relname = t.tablename
            WHERE t.schemaname = 'public'
            AND t.tablename = '$table';
        ")

        if [ "$IS_ENABLED" = "t" ]; then
            log_table "${table} - ${YELLOW}Already enabled${NC}"
            ALREADY_ENABLED_COUNT=$((ALREADY_ENABLED_COUNT + 1))
        else
            # Enable RLS
            if execute_sql "ALTER TABLE public.\"$table\" ENABLE ROW LEVEL SECURITY;" > /dev/null 2>&1; then
                log_table "${table} - ${GREEN}Enabled${NC}"
                ENABLED_COUNT=$((ENABLED_COUNT + 1))
            else
                log_table "${table} - ${RED}Failed${NC}"
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
        fi
    fi
done <<< "$TABLES"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            Summary                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
log_info "Total tables: ${TABLE_COUNT}"
log_success "Newly enabled: ${ENABLED_COUNT}"
log_warning "Already enabled: ${ALREADY_ENABLED_COUNT}"
if [ $FAILED_COUNT -gt 0 ]; then
    log_error "Failed: ${FAILED_COUNT}"
fi
echo ""

# Display final RLS status
log_info "Final RLS status:"
FINAL_STATUS=$(execute_sql_quiet "
    SELECT
        COUNT(*) as total,
        SUM(CASE WHEN rowsecurity THEN 1 ELSE 0 END) as enabled
    FROM pg_tables t
    JOIN pg_class c ON c.relname = t.tablename
    WHERE t.schemaname = 'public';
")

TOTAL=$(echo "$FINAL_STATUS" | cut -d'|' -f1)
ENABLED=$(echo "$FINAL_STATUS" | cut -d'|' -f2)

if [ "$TOTAL" = "$ENABLED" ]; then
    log_success "All ${TOTAL} tables have RLS enabled! ✓"
else
    log_warning "${ENABLED}/${TOTAL} tables have RLS enabled"
fi

echo ""
log_warning "⚠️  IMPORTANT: RLS is now enabled, but NO policies are defined!"
log_warning "Tables are now LOCKED - no one can access them without policies."
log_info "Next steps:"
echo "  1. Create RLS policies for each table"
echo "  2. Test policies with different user roles"
echo "  3. Use 'FORCE ROW LEVEL SECURITY' if needed for table owners"
echo ""
log_info "Example policy creation:"
echo "  ALTER TABLE products FORCE ROW LEVEL SECURITY;"
echo "  CREATE POLICY \"Allow public read\" ON products FOR SELECT USING (true);"
echo "  CREATE POLICY \"Allow authenticated insert\" ON products FOR INSERT"
echo "    TO authenticated WITH CHECK (auth.uid() = user_id);"
echo ""

if [ $FAILED_COUNT -eq 0 ]; then
    log_success "RLS enablement completed successfully!"
    exit 0
else
    log_error "RLS enablement completed with errors"
    exit 1
fi
