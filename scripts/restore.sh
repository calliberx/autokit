#!/bin/bash
################################################################################
# AutoKit restore — rebuilds volumes and config from a backup directory
# Usage: ./scripts/restore.sh /path/to/backup-20250101-120000
################################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-$REPO_DIR/backups}"
PROJECT="$(basename "$REPO_DIR")"

BACKUP_DIR="${1:-}"
if [ -z "$BACKUP_DIR" ]; then
    echo "Usage: $0 <backup-directory>"
    echo ""
    echo "Available backups:"
    ls -1d "$BACKUP_ROOT"/backup-* 2>/dev/null || echo "  none found in $BACKUP_ROOT"
    exit 1
fi

if [ ! -d "$BACKUP_DIR" ]; then
    echo "ERROR: no such directory: $BACKUP_DIR"
    exit 1
fi

echo "This OVERWRITES the current n8n and Evolution data with the contents of:"
echo "  $BACKUP_DIR"
read -r -p "Type 'yes' to continue: " confirm
[ "$confirm" = "yes" ] || { echo "Cancelled."; exit 0; }

cd "$REPO_DIR"

echo "Stopping stack..."
docker compose down

echo "Restoring volumes..."
for vol in postgres-data redis-data n8n-data evolution-instances; do
    archive="$BACKUP_DIR/${vol}.tar.gz"
    [ -f "$archive" ] || { echo "  (skipped $vol — not in backup)"; continue; }
    full="${PROJECT}_${vol}"
    docker volume create "$full" >/dev/null
    docker run --rm \
        -v "$full":/target \
        -v "$BACKUP_DIR":/backup:ro \
        alpine sh -c "rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null; \
                      tar xzf /backup/${vol}.tar.gz -C /target"
    echo "  $full"
done

echo "Restoring configuration..."
for f in .env .env.worker .env.evolution; do
    [ -f "$BACKUP_DIR/$f" ] && cp "$BACKUP_DIR/$f" "$REPO_DIR/$f" && echo "  $f"
done

echo "Starting stack..."
docker compose up -d

echo "Done. Check logs with: docker compose logs -f"
