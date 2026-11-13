#!/usr/bin/env bash
# One-time setup of a fresh Ubuntu 22.04 or 24.04 machine (AWS EC2 or Lightsail, or Oracle Cloud), x86 or ARM.
# Run it as your normal user (it asks for sudo):   bash deploy/setup_server.sh
#
# What it does, in order, and nothing else:
#   1. installs Docker (with the compose plugin) from Docker's own repository, and git
#   2. adds 2 GB of swap (a 2 GB machine running ffmpeg needs the cushion; harmless on a bigger one)
#   3. turns on the firewall: only SSH, HTTP and HTTPS are open
#   4. turns on automatic security updates
#   5. makes the data folder (owned by the container's user)
#   6. installs the nightly backup job (only if deploy/backup.env exists, see backup_to_s3.sh)
# It does NOT touch your .env files, start the server or open any other port.
# (Oracle Cloud: also open ports 80 and 443 in the VCN's security list; the firewall inside the machine is not the only one.)

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Docker"
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg git
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  echo "   (log out and in once so 'docker' works without sudo)"
else
  echo "   already installed"
fi

echo "==> Swap"
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile >/dev/null
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
else
  echo "   already there"
fi

echo "==> Firewall (SSH, HTTP, HTTPS)"
sudo apt-get install -y ufw >/dev/null
sudo ufw allow OpenSSH >/dev/null
sudo ufw allow 80/tcp >/dev/null
sudo ufw allow 443/tcp >/dev/null
sudo ufw --force enable >/dev/null
sudo ufw status | sed 's/^/   /'

echo "==> Automatic security updates"
sudo apt-get install -y unattended-upgrades >/dev/null
echo 'APT::Periodic::Update-Package-Lists "1"; APT::Periodic::Unattended-Upgrade "1";' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null

echo "==> Data folder"
mkdir -p "$HERE/data"
sudo chown -R 1000:1000 "$HERE/data"   # 1000 is the "node" user inside the container

echo "==> Nightly backup"
if [ -f "$HERE/backup.env" ]; then
  CRON="30 2 * * * cd $HERE && bash backup_to_s3.sh >> $HERE/data/backup.log 2>&1"
  ( crontab -l 2>/dev/null | grep -v backup_to_s3.sh; echo "$CRON" ) | crontab -
  echo "   installed: 02:30 every night"
else
  echo "   skipped: create deploy/backup.env first (see deploy/backup_to_s3.sh), then run this script again"
fi

echo
echo "Done. Next: fill in deploy/api.env and deploy/.env, then  docker compose up -d --build  (docs/DEPLOY.md, step 5)."
