#!/bin/bash

# ============================================
# Check RLS Status Script
# ============================================
# This script displays the current RLS status for all tables
# and helps identify tables without policies

set -e

# Configuration
CONTAINER_NAME="${DB_CONTAINER:-supabase-db}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Display banner
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     RLS Status Report                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "Container ${CONTAINER_NAME} is not running!"
    exit 1
fi

# Function to execute SQL query
execute_sql() {
    local query="$1"
    docker exec "${CONTAINER_NAME}" psql \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        -t \
        -A \
        -c "${query}" \
        2>/dev/null
}

# Get overall statistics
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Overall Statistics${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"

STATS=$(execute_sql "
    SELECT
        COUNT(*) as total,
        SUM(CASE WHEN c.relrowsecurity THEN 1 ELSE 0 END) as enabled,
        SUM(CASE WHEN NOT c.relrowsecurity THEN 1 ELSE 0 END) as disabled,
        (SELECT COUNT(DISTINCT tablename) FROM pg_policies WHERE schemaname = 'public') as with_policies
    FROM pg_tables t
    JOIN pg_class c ON c.relname = t.tablename
    WHERE t.schemaname = 'public';
")

TOTAL=$(echo "$STATS" | cut -d'|' -f1)
ENABLED=$(echo "$STATS" | cut -d'|' -f2)
DISABLED=$(echo "$STATS" | cut -d'|' -f3)
WITH_POLICIES=$(echo "$STATS" | cut -d'|' -f4)

echo ""
echo "  Total Tables:       ${TOTAL}"
echo "  RLS Enabled:        ${GREEN}${ENABLED}${NC}"
echo "  RLS Disabled:       ${RED}${DISABLED}${NC}"
echo "  Tables w/ Policies: ${GREEN}${WITH_POLICIES}${NC}"
echo ""

# Detailed table status
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Table Status${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

TABLE_STATUS=$(execute_sql "
    SELECT
        t.tablename,
        CASE WHEN c.relrowsecurity THEN 'ENABLED' ELSE 'DISABLED' END as rls,
        CASE WHEN c.relforcerowsecurity THEN 'YES' ELSE 'NO' END as forced,
        COALESCE((
            SELECT COUNT(*)::text
            FROM pg_policies
            WHERE schemaname = 'public'
            AND tablename = t.tablename
        ), '0') as policies
    FROM pg_tables t
    JOIN pg_class c ON c.relname = t.tablename
    WHERE t.schemaname = 'public'
    ORDER BY t.tablename;
")

printf "  %-35s %-12s %-10s %-10s\n" "TABLE" "RLS" "FORCED" "POLICIES"
printf "  %-35s %-12s %-10s %-10s\n" "─────────────────────────────────" "──────────" "────────" "────────"

while IFS='|' read -r table rls forced policies; do
    if [ -n "$table" ]; then
        # Color code based on status
        if [ "$rls" = "ENABLED" ]; then
            rls_display="${GREEN}${rls}${NC}"
        else
            rls_display="${RED}${rls}${NC}"
        fi

        if [ "$forced" = "YES" ]; then
            forced_display="${GREEN}${forced}${NC}"
        else
            forced_display="${YELLOW}${forced}${NC}"
        fi

        if [ "$policies" = "0" ] && [ "$rls" = "ENABLED" ]; then
            policies_display="${RED}${policies}${NC}"
        elif [ "$policies" != "0" ]; then
            policies_display="${GREEN}${policies}${NC}"
        else
            policies_display="${YELLOW}${policies}${NC}"
        fi

        printf "  %-45s %-22s %-20s %-10s\n" "$table" "$rls_display" "$forced_display" "$policies_display"
    fi
done <<< "$TABLE_STATUS"

echo ""

# Warning for tables with RLS but no policies
LOCKED_TABLES=$(execute_sql "
    SELECT t.tablename
    FROM pg_tables t
    JOIN pg_class c ON c.relname = t.tablename
    WHERE t.schemaname = 'public'
    AND c.relrowsecurity = true
    AND NOT EXISTS (
        SELECT 1 FROM pg_policies p
        WHERE p.schemaname = 'public'
        AND p.tablename = t.tablename
    )
    ORDER BY t.tablename;
")

if [ -n "$LOCKED_TABLES" ]; then
    echo -e "${RED}╔════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ⚠️  WARNING: LOCKED TABLES           ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════╝${NC}"
    echo ""
    log_warning "The following tables have RLS ENABLED but NO POLICIES:"
    log_warning "These tables are LOCKED - no one can access them!"
    echo ""
    echo "$LOCKED_TABLES" | while read -r table; do
        if [ -n "$table" ]; then
            echo "  ${RED}✗${NC} $table"
        fi
    done
    echo ""
    log_info "Create policies for these tables or disable RLS"
    echo ""
fi

# Policy details
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}Policy Details${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

POLICY_COUNT=$(execute_sql "SELECT COUNT(*) FROM pg_policies WHERE schemaname = 'public';")

if [ "$POLICY_COUNT" = "0" ]; then
    log_warning "No RLS policies defined yet"
else
    log_info "Total policies: ${POLICY_COUNT}"
    echo ""

    POLICIES=$(execute_sql "
        SELECT
            tablename,
            policyname,
            cmd,
            CASE WHEN permissive = 'PERMISSIVE' THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END as type,
            roles
        FROM pg_policies
        WHERE schemaname = 'public'
        ORDER BY tablename, policyname;
    ")

    CURRENT_TABLE=""
    while IFS='|' read -r table policy cmd type roles; do
        if [ -n "$table" ]; then
            if [ "$table" != "$CURRENT_TABLE" ]; then
                echo ""
                echo -e "  ${MAGENTA}${table}${NC}"
                CURRENT_TABLE="$table"
            fi
            echo "    ├─ ${CYAN}${policy}${NC}"
            echo "    │  └─ Command: ${cmd} | Type: ${type} | Roles: ${roles}"
        fi
    done <<< "$POLICIES"
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"

# Recommendations
echo ""
log_info "Recommendations:"
echo ""

if [ "$DISABLED" -gt 0 ]; then
    echo "  • ${YELLOW}${DISABLED}${NC} tables don't have RLS enabled"
    echo "    Run: ./scripts/enable-rls.sh"
    echo ""
fi

if [ -n "$LOCKED_TABLES" ]; then
    echo "  • Some tables are LOCKED (RLS enabled without policies)"
    echo "    Create policies or disable RLS for these tables"
    echo ""
fi

UNFORCED=$(execute_sql "
    SELECT COUNT(*)
    FROM pg_tables t
    JOIN pg_class c ON c.relname = t.tablename
    WHERE t.schemaname = 'public'
    AND c.relrowsecurity = true
    AND c.relforcerowsecurity = false;
")

if [ "$UNFORCED" -gt 0 ]; then
    echo "  • ${YELLOW}${UNFORCED}${NC} tables have RLS but not FORCED"
    echo "    Consider: ALTER TABLE table_name FORCE ROW LEVEL SECURITY;"
    echo ""
fi

echo ""
log_success "RLS status check completed!"
