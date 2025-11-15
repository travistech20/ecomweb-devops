#!/bin/bash

# ============================================
# Supabase Database Backup Script
# ============================================
# This script creates timestamped backups of the Supabase database
# and implements automatic rotation to manage storage

set -e  # Exit on any error

# Configuration
BACKUP_DIR="${BACKUP_DIR:-./volumes/backups}"
CONTAINER_NAME="${DB_CONTAINER:-supabase-db}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
MAX_BACKUPS="${MAX_BACKUPS:-7}"  # Keep last 7 backups by default
COMPRESSION="${COMPRESSION:-true}"
BACKUP_PREFIX="${BACKUP_PREFIX:-supabase}"

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

# Timestamp for backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILENAME="${BACKUP_PREFIX}_backup_${TIMESTAMP}"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"

log_info "Starting database backup..."
log_info "Container: ${CONTAINER_NAME}"
log_info "Database: ${POSTGRES_DB}"
log_info "Backup directory: ${BACKUP_DIR}"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_error "Container ${CONTAINER_NAME} is not running!"
    exit 1
fi

# Perform backup
log_info "Creating backup: ${BACKUP_FILENAME}"

if [ "${COMPRESSION}" = "true" ]; then
    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILENAME}.sql.gz"

    # Self-hosted Supabase: Backup public + auth + storage schemas
    # public: Your application data (products, orders, etc.)
    # auth: User authentication data (users, sessions, etc.) - IMPORTANT!
    # storage: File storage metadata
    # NOTE: Auth schema is backed up but migrations are NOT - GoTrue will recreate them on startup
    docker exec "${CONTAINER_NAME}" pg_dump \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --schema=public \
        --schema=auth \
        --schema=storage \
        --format=plain \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists \
        --exclude-table=auth.schema_migrations \
        2>/dev/null | gzip > "${BACKUP_FILE}"
else
    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILENAME}.sql"

    docker exec "${CONTAINER_NAME}" pg_dump \
        -U "${POSTGRES_USER}" \
        -d "${POSTGRES_DB}" \
        --schema=public \
        --schema=auth \
        --schema=storage \
        --format=plain \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists \
        --exclude-table=auth.schema_migrations \
        > "${BACKUP_FILE}"
fi

# Check if backup was created successfully
if [ ! -f "${BACKUP_FILE}" ]; then
    log_error "Backup file was not created!"
    exit 1
fi

# Get backup size
BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
log_success "Backup created successfully: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Backup rotation - keep only MAX_BACKUPS most recent backups
log_info "Managing backup rotation (keeping ${MAX_BACKUPS} most recent backups)..."

# Count current backups
BACKUP_COUNT=$(find "${BACKUP_DIR}" -name "${BACKUP_PREFIX}_backup_*.sql*" -type f | wc -l | tr -d ' ')

if [ "${BACKUP_COUNT}" -gt "${MAX_BACKUPS}" ]; then
    # Calculate how many to delete
    DELETE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))

    log_info "Found ${BACKUP_COUNT} backups, removing ${DELETE_COUNT} oldest..."

    # Delete oldest backups (macOS/Linux compatible)
    find "${BACKUP_DIR}" -name "${BACKUP_PREFIX}_backup_*.sql*" -type f -print0 \
        | xargs -0 ls -t \
        | tail -n "${DELETE_COUNT}" \
        | while read -r old_backup; do
            log_warning "Removing old backup: $(basename "${old_backup}")"
            rm -f "${old_backup}"
        done
fi

# List remaining backups
log_info "Current backups:"
find "${BACKUP_DIR}" -name "${BACKUP_PREFIX}_backup_*.sql*" -type f -exec ls -lh {} \; \
    | awk '{print $9, "(" $5 ")"}' \
    | while read -r line; do
        echo "  - $(basename ${line})"
    done

log_success "Backup completed successfully!"

# Export backup file path for CI/CD
echo "BACKUP_FILE=${BACKUP_FILE}" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "BACKUP_SIZE=${BACKUP_SIZE}" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "BACKUP_TIMESTAMP=${TIMESTAMP}" >> "${GITHUB_OUTPUT:-/dev/null}"
