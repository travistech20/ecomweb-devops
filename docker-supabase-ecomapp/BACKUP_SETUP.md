# Database Backup Setup - Deployment Server

This document describes the database backup setup for the production deployment server.

## What Was Added

### 1. Docker Services

Two new backup services were added to `docker-compose.yml`:

#### Main Database Backup Service
- **Service Name**: `db-backup`
- **Container Name**: `supabase-db-backup`
- **Image**: `ghcr.io/travistech20/ecomweb-db-backup:production`
- **Schedule**: 2 AM daily (configurable via `BACKUP_SCHEDULE`)
- **Backup Location**: `./volumes/backups/scheduled/`

#### Store Database Backup Service
- **Service Name**: `store-db-backup`
- **Container Name**: `store-supabase-db-backup`
- **Image**: `ghcr.io/travistech20/ecomweb-db-backup:production`
- **Schedule**: 3 AM daily (configurable via `STORE_BACKUP_SCHEDULE`)
- **Backup Location**: `./volumes/backups/store-scheduled/`

### 2. Directory Structure

```
ECOMWEB_SERVER/docker-supabase-ecomapp/
├── scripts/
│   └── backup/
│       ├── backup-db.sh           # Manual backup script
│       ├── restore-db.sh          # Restore script
│       ├── fix-permissions.sh     # Fix auth permissions after restore
│       ├── scheduled-backup.sh    # Used by Docker container
│       └── README.md              # Quick reference
├── volumes/
│   └── backups/
│       ├── scheduled/             # Main DB automated backups
│       ├── store-scheduled/       # Store DB automated backups
│       ├── manual/                # Manual backups
│       ├── .gitignore            # Ignore backup files in git
│       └── README.md             # Backup documentation
└── docker-compose.yml            # Updated with backup services
```

### 3. Files Created/Copied

- ✅ `scripts/backup/` - All backup scripts
- ✅ `volumes/backups/` - Backup storage directories
- ✅ `volumes/backups/.gitignore` - Prevent committing large backup files
- ✅ `volumes/backups/README.md` - Backup documentation
- ✅ `.gitignore` - Root gitignore for deployment

## Environment Variables

Add these to your `.env` file (optional, defaults shown):

```bash
# Main Database Backup Configuration
BACKUP_SCHEDULE=0 2 * * *    # Cron format: 2 AM daily
MAX_BACKUPS=7                # Keep last 7 backups

# Store Database Backup Configuration
STORE_BACKUP_SCHEDULE=0 3 * * *  # Cron format: 3 AM daily
STORE_MAX_BACKUPS=7              # Keep last 7 backups
```

## Usage

### Start Backup Services

```bash
cd /path/to/ECOMWEB_SERVER/docker-supabase-ecomapp

# Start only backup services
docker-compose up -d db-backup store-db-backup

# Or start all services including backups
docker-compose up -d
```

### Monitor Backup Services

```bash
# View logs
docker logs -f supabase-db-backup
docker logs -f store-supabase-db-backup

# Check service status
docker ps | grep backup

# List backups
ls -lh volumes/backups/scheduled/
ls -lh volumes/backups/store-scheduled/
```

### Manual Backups

#### Backup Main Database
```bash
cd /path/to/ECOMWEB_SERVER/docker-supabase-ecomapp
BACKUP_DIR=./volumes/backups/manual ./scripts/backup/backup-db.sh
```

#### Backup Store Database
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

# Restore main database
./scripts/backup/restore-db.sh volumes/backups/scheduled/supabase_backup_YYYYMMDD_HHMMSS.sql.gz

# Restore store database
DB_CONTAINER=store-supabase-db \
POSTGRES_PASSWORD=$STORE_POSTGRES_PASSWORD \
./scripts/backup/restore-db.sh volumes/backups/store-scheduled/supabase_backup_YYYYMMDD_HHMMSS.sql.gz

# Fix permissions if needed (after restore)
./scripts/backup/fix-permissions.sh
```

## Docker Image

The backup services use a pre-built Docker image from GitHub Container Registry:

- **Repository**: `ghcr.io/travistech20/ecomweb-db-backup`
- **Tags**: `production`, `latest`, version tags (e.g., `1.0.0`)
- **Auto-built**: GitHub Actions builds and publishes on push to production branch
- **Location**: `.github/workflows/docker-build-db-backup.yml` (in main repo)

### Updating the Backup Image

The image is automatically built and pushed when you update:
- `apps/api/Dockerfile.backup`
- `scripts/backup/**`
- Push to `production` or `build` branches

## What Gets Backed Up

For self-hosted Supabase, the following PostgreSQL schemas are backed up:

1. **`public`** - Your application data (products, orders, users, etc.)
2. **`auth`** - User authentication data (auth.users, auth.sessions, etc.)
3. **`storage`** - File storage metadata

**Note**: `auth.schema_migrations` is excluded because GoTrue recreates it on startup.

## Key Features

✅ **Automated Scheduled Backups** - Daily backups at 2 AM and 3 AM
✅ **Automatic Rotation** - Keeps only the last N backups (default: 7)
✅ **Compression** - Backups are gzip compressed to save space
✅ **Docker Integration** - Uses Docker socket to backup running containers
✅ **Manual Backup Support** - Scripts for on-demand backups
✅ **Restore Scripts** - Easy restoration with permission fixes

## Important Notes

1. **Security**: Backup files contain sensitive data including authentication info
2. **Storage**: Monitor disk space - backups can grow large over time
3. **Testing**: Regularly test restore procedures
4. **External Backup**: Consider copying to external storage for disaster recovery
5. **Docker Socket**: Backup containers need access to `/var/run/docker.sock`

## Differences from Development Setup

| Aspect | Development | Production/Deployment |
|--------|-------------|----------------------|
| Image Source | Built locally | Pre-built from GHCR |
| Build Context | `apps/api/Dockerfile.backup` | Pull from registry |
| Update Process | `docker-compose build` | `docker-compose pull` |
| Network | `ecomweb-dev-network` | `ecomweb_internal_net` |

## Troubleshooting

### Backup Service Won't Start
```bash
# Check if db is healthy
docker ps --filter "name=supabase-db"

# Check logs
docker logs supabase-db-backup

# Verify Docker socket permission
ls -l /var/run/docker.sock
```

### Backups Not Running on Schedule
```bash
# Check cron logs
docker exec supabase-db-backup cat /var/log/cron.log

# Check backup logs
docker exec supabase-db-backup cat /var/log/backup.log
```

### Permission Issues After Restore
```bash
# Run the fix-permissions script
./scripts/backup/fix-permissions.sh
```

## Next Steps

1. ✅ Backup services are configured
2. ⏳ Test the automated backup (wait for scheduled time or trigger manually)
3. ⏳ Test restore procedure in a safe environment
4. ⏳ Set up external backup storage (S3, etc.)
5. ⏳ Configure monitoring/alerts for backup failures

## Related Documentation

- Main repo: `/docs/DATABASE_BACKUP.md` - Comprehensive backup documentation
- Scripts: `/scripts/backup/README.md` - Quick script reference
- Backups: `/volumes/backups/README.md` - Backup directory info
