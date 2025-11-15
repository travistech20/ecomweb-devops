# Database Backups

This directory contains automated and manual database backups.

## Directory Structure

- `scheduled/` - Automated daily backups for main Supabase DB (2 AM daily)
- `store-scheduled/` - Automated daily backups for Store DB (3 AM daily)
- `manual/` - Manual backups created on-demand

## Automated Backups

Automated backups are managed by the `db-backup` and `store-db-backup` services.

### Configuration

Set these environment variables in `.env`:

```bash
# Main DB Backup
BACKUP_SCHEDULE=0 2 * * *  # 2 AM daily (cron format)
MAX_BACKUPS=7              # Keep last 7 backups

# Store DB Backup
STORE_BACKUP_SCHEDULE=0 3 * * *  # 3 AM daily
STORE_MAX_BACKUPS=7              # Keep last 7 backups
```

### Check Backup Status

```bash
# View backup logs
docker logs supabase-db-backup
docker logs store-supabase-db-backup

# List backups
ls -lh volumes/backups/scheduled/
ls -lh volumes/backups/store-scheduled/
```

## Manual Backups

### Backup Main Database

```bash
cd /path/to/ECOMWEB_SERVER/docker-supabase-ecomapp
BACKUP_DIR=./volumes/backups/manual ./scripts/backup/backup-db.sh
```

### Backup Store Database

```bash
cd /path/to/ECOMWEB_SERVER/docker-supabase-ecomapp
DB_CONTAINER=store-supabase-db \
POSTGRES_PASSWORD=$STORE_POSTGRES_PASSWORD \
BACKUP_DIR=./volumes/backups/manual \
BACKUP_PREFIX=store \
./scripts/backup/backup-db.sh
```

### Restore Database

```bash
cd /path/to/ECOMWEB_SERVER/docker-supabase-ecomapp
./scripts/backup/restore-db.sh volumes/backups/scheduled/supabase_backup_YYYYMMDD_HHMMSS.sql.gz
```

## Backup Retention

- Automated backups are rotated automatically based on `MAX_BACKUPS`
- Manual backups are NOT automatically deleted
- Consider archiving old manual backups to external storage

## Important Notes

1. **Security**: Backup files contain sensitive data including user authentication information
2. **Storage**: Monitor disk space usage as backups can grow large
3. **Testing**: Regularly test restore procedures to ensure backup integrity
4. **External Backup**: Consider copying backups to external storage for disaster recovery

## Schemas Backed Up

For self-hosted Supabase, the following schemas are backed up:

- `public` - Your application data (products, orders, etc.)
- `auth` - User authentication data (users, sessions, etc.)
- `storage` - File storage metadata

Note: `auth.schema_migrations` is excluded as GoTrue recreates it on startup.
