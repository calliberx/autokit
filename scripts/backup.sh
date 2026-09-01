#!/bin/bash
################################################################################
# AutoKit backup — Docker volumes + configuration files
# Paths are derived from the script's own location, so the repo can live
# anywhere. Override the destination with BACKUP_ROOT=/path ./scripts/backup.sh
################################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-$REPO_DIR/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Compose derives volume names from the project (directory) name.
PROJECT="$(basename "$REPO_DIR")"

BACKUP_DIR="$BACKUP_ROOT/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Backing up to: $BACKUP_DIR"

echo "  configuration files..."
for f in .env .env.worker .env.evolution docker-compose.yml; do
    cp "$REPO_DIR/$f" "$BACKUP_DIR/" 2>/dev/null || echo "    (skipped $f — not found)"
done

echo "  docker volumes..."
for vol in postgres-data redis-data n8n-data evolution-instances; do
    full="${PROJECT}_${vol}"
    if ! docker volume inspect "$full" >/dev/null 2>&1; then
        echo "    (skipped $full — no such volume)"
        continue
    fi
    docker run --rm \
        -v "$full":/source:ro \
        -v "$BACKUP_DIR":/backup \
        alpine tar czf "/backup/${vol}.tar.gz" -C /source .
    echo "    $full"
done

echo "  pruning backups older than ${RETENTION_DAYS} days..."
find "$BACKUP_ROOT" -maxdepth 1 -name 'backup-*' -type d -mtime "+$RETENTION_DAYS" \
    -exec rm -rf {} + 2>/dev/null || true

echo "Done: $BACKUP_DIR ($(du -sh "$BACKUP_DIR" | cut -f1))"
