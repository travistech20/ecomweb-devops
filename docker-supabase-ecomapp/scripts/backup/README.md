# Backup Scripts - Quick Reference

## Quick Commands

### Backup
```bash
bash scripts/backup/backup-db.sh
```

### Restore
```bash
bash scripts/backup/restore-db.sh
```

### Fix Permissions (if auth fails after restore)
```bash
bash scripts/backup/fix-permissions.sh
```

### Automated Backups
```bash
docker-compose up -d db-backup
docker-compose logs -f db-backup
```

## Full Documentation

See [../../docs/DATABASE_BACKUP.md](../../docs/DATABASE_BACKUP.md) for complete documentation.
