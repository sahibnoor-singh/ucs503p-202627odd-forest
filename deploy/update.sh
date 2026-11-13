#!/usr/bin/env bash
# Put the newest code live, safely:  bash deploy/update.sh
#   pull -> check the settings -> rebuild -> restart -> wait until the API answers (and say so if it does not)
# A few seconds of downtime while the container restarts is expected. Videos and the database are in ./data and are not touched.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

BRANCH="${1:-main}"
echo "==> pulling $BRANCH"
git -C .. fetch origin "$BRANCH"
git -C .. checkout "$BRANCH"
git -C .. pull --ff-only origin "$BRANCH"

echo "==> checking the settings"
docker compose run --rm --no-deps api node scripts/preflight.js

echo "==> before changing anything, a database copy"
docker compose exec -T api node scripts/backup.js --dir /data/backups --keep 7 || echo "   (no running server to copy from: skipped)"

echo "==> rebuilding and restarting"
docker compose up -d --build

echo "==> waiting for the API"
for i in $(seq 1 30); do
  if docker compose exec -T api node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
    echo "   up after ${i}x2 s. Version: $(git -C .. rev-parse --short HEAD)"
    exit 0
  fi
  sleep 2
done
echo "!! the API did not answer in 60 s. Look at:  docker compose logs --tail 100 api"
exit 1
