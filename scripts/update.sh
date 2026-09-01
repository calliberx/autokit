#!/usr/bin/env bash
################################################################################
# AutoKit update — rolling restart of n8n main + workers
#
# This pulls the tags currently written in docker-compose.yml. It does NOT
# bump versions for you. Changing the Evolution tag is the single most common
# cause of a broken WhatsApp connection — see docs/VERSIONS.md before editing.
################################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

MAIN="n8n-main"
WORKER="n8n-worker"
TIMEOUT="${TIMEOUT:-120}"
DESIRED_WORKERS="${DESIRED_WORKERS:-2}"

if [ "${SKIP_BACKUP:-0}" != "1" ]; then
    echo "==> Backing up first (SKIP_BACKUP=1 to skip) ..."
    "$REPO_DIR/scripts/backup.sh"
fi

echo "==> Pulling pinned images ..."
docker compose pull "$MAIN" "$WORKER"

echo "==> Ensuring at least $DESIRED_WORKERS workers running ..."
docker compose up -d --scale "$WORKER"="$DESIRED_WORKERS" "$WORKER"

echo "==> Recreating workers first (queued jobs keep draining) ..."
docker compose up -d --no-deps "$WORKER"

echo "==> Recreating main ..."
docker compose up -d --no-deps "$MAIN"

echo "==> Waiting for main to become healthy (timeout: ${TIMEOUT}s) ..."
start=$(date +%s)
while true; do
    status=$(docker inspect --format='{{json .State.Health.Status}}' \
        "$(docker compose ps -q "$MAIN")" 2>/dev/null || echo '"starting"')
    [[ "$status" == "\"healthy\"" ]] && break
    now=$(date +%s)
    (( now - start > TIMEOUT )) && { echo "ERROR: main not healthy in time"; exit 1; }
    sleep 3
done

echo "==> Update complete."
