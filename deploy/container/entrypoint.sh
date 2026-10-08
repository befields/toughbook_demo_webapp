#!/usr/bin/env bash
#
# Renders inventory.ini from environment variables (so no credentials are
# ever baked into the image), then starts gunicorn.
#
set -euo pipefail

# Comma-separated list of target toughbooks (TARGET_IP, singular, also works).
TARGET_IPS="${TARGET_IPS:-${TARGET_IP:-192.168.8.101,192.168.8.102}}"
TARGET_SSH_USER="${TARGET_SSH_USER:-core}"
TARGET_SSH_PASS="${TARGET_SSH_PASS:-edge}"
TARGET_BECOME_PASS="${TARGET_BECOME_PASS:-edge}"
PORT="${PORT:-80}"

{
  echo "[my_hosts]"
  IFS=','; for ip in $TARGET_IPS; do
    ip="$(echo "$ip" | xargs)"   # trim
    [ -n "$ip" ] && echo "${ip} ansible_user=${TARGET_SSH_USER} ansible_ssh_pass=${TARGET_SSH_PASS} ansible_become_pass=${TARGET_BECOME_PASS}"
  done
} > /app/inventory.ini
chmod 600 /app/inventory.ini

echo ">> Workload Selector starting"
echo "   targets=${TARGET_IPS}  registry=${REGISTRY_HOST:-192.168.8.100:5000}  port=${PORT}"
echo "   workloads=${WORKLOADS:-f22,b52,f35,f35-fixed,base}"

exec gunicorn --workers 3 --timeout 300 --bind "0.0.0.0:${PORT}" app:app
