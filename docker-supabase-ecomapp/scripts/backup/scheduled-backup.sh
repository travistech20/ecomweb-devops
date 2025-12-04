#!/bin/bash

# ============================================
# Scheduled Database Backup Script
# ============================================
# This script runs inside a container to perform scheduled backups
# It uses cron to run backups at specified intervals

set -e

# Configuration
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"  # Default: 2 AM daily
DB_CONTAINER="${DB_CONTAINER:-supabase-db}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
BACKUP_DIR="/backups"
MAX_BACKUPS="${MAX_BACKUPS:-7}"

echo "================================================"
echo "Scheduled Backup Container Started"
echo "================================================"
echo "Schedule: ${BACKUP_SCHEDULE}"
echo "Target Container: ${DB_CONTAINER}"
echo "Backup Directory: ${BACKUP_DIR}"
echo "Max Backups: ${MAX_BACKUPS}"
echo "================================================"

# Create backup script
cat > /usr/local/bin/perform-backup.sh << 'EOF'
#!/bin/bash
set -e

# Source environment variables (needed when run directly, not just from cron)
if [ -f /etc/environment ]; then
    . /etc/environment
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/supabase_backup_${TIMESTAMP}.sql.gz"

echo "[$(date)] Starting backup..."

# Perform backup
# Self-hosted Supabase: Backup public + auth + storage schemas
# public: Your application data (products, orders, etc.)
# auth: User authentication data (users, sessions, etc.) - IMPORTANT!
# storage: File storage metadata
# NOTE: Auth schema is backed up but migrations are NOT - GoTrue will recreate them on startup
docker exec "${DB_CONTAINER}" pg_dump \
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

if [ -f "${BACKUP_FILE}" ]; then
    BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
    echo "[$(date)] Backup created successfully: ${BACKUP_FILE} (${BACKUP_SIZE})"

    # Rotation
    BACKUP_COUNT=$(find "${BACKUP_DIR}" -name "supabase_backup_*.sql.gz" -type f | wc -l)

    if [ "${BACKUP_COUNT}" -gt "${MAX_BACKUPS}" ]; then
        DELETE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
        echo "[$(date)] Removing ${DELETE_COUNT} old backups..."

        # Alpine-compatible: Use ls -t for sorting by time (most recent first)
        # Then tail to get oldest files
        find "${BACKUP_DIR}" -name "supabase_backup_*.sql.gz" -type f -print0 \
            | xargs -0 ls -t \
            | tail -n "${DELETE_COUNT}" \
            | while read -r old_backup; do
                echo "[$(date)] Removing: $(basename "${old_backup}")"
                rm -f "${old_backup}"
            done
    fi
else
    echo "[$(date)] ERROR: Backup failed!"
    exit 1
fi

echo "[$(date)] Backup completed successfully"
EOF

chmod +x /usr/local/bin/perform-backup.sh

# Export environment variables for cron
cat > /etc/environment << EOF
DB_CONTAINER=${DB_CONTAINER}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
BACKUP_DIR=${BACKUP_DIR}
MAX_BACKUPS=${MAX_BACKUPS}
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF

# Create log files
touch /var/log/backup.log
touch /var/log/cron.log

# Create cron job file
# Note: Alpine crond uses /etc/crontabs/ directory, not /etc/cron.d/
mkdir -p /etc/crontabs
echo "${BACKUP_SCHEDULE} . /etc/environment; /usr/local/bin/perform-backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root
chmod 0600 /etc/crontabs/root

# Run initial backup
echo "Running initial backup..."
/usr/local/bin/perform-backup.sh

# Start crond in foreground (Alpine Linux uses crond, not cron)
echo "Starting crond daemon..."
crond -f -l 2 -L /var/log/cron.log &

# Tail both logs
tail -f /var/log/backup.log /var/log/cron.log
