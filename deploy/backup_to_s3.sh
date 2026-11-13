#!/usr/bin/env bash
# Nightly backup, copied OFF the machine (a backup on the same disk does not survive losing the disk).
#
#   1. a consistent copy of the database (kept 7 days in data/backups on this machine)
#   2. that copy, and any new videos, uploaded to an S3 bucket (Oracle or AWS: S3 is the safe place either way)
#
# Videos never change once uploaded, so `s3 sync` only sends the new ones. Cost: S3 is about $0.025 per GB-month.
#
# Setup (once):
#   - make a private S3 bucket, e.g. forest-backups-yourname (block all public access, keep versioning on)
#   - make an IAM user whose only permission is s3:PutObject, s3:ListBucket, s3:GetObject on that bucket; run `aws configure` as this
#     machine's user with its keys (or give an EC2 instance a role with the same permissions and skip the keys)
#   - write deploy/backup.env with one line:   BUCKET=forest-backups-yourname
# Restore test (do it once, for real, before anyone relies on it): docs/DEPLOY.md, "Restoring".
#
# Needs the AWS CLI on the host:  sudo apt-get install -y awscli   (or: snap install aws-cli --classic)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck disable=SC1091
source ./backup.env
: "${BUCKET:?write BUCKET=... in deploy/backup.env}"

echo "[$(date -u +%FT%TZ)] backup start"
docker compose exec -T api node scripts/backup.js --dir /data/backups --keep 7
aws s3 sync ./data/backups "s3://$BUCKET/db" --only-show-errors
aws s3 sync ./data/uploads "s3://$BUCKET/uploads" --size-only --only-show-errors
echo "[$(date -u +%FT%TZ)] backup done"
