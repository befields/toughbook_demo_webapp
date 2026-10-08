#!/usr/bin/env bash
#
# PRE-TRAVEL bootstrap. Run this ON THE TABLET while it still has internet.
# It installs everything the offline booth deploy needs, so site.yml and the
# demo work with no network at the venue.
#
#   chmod +x deploy/bootstrap.sh
#   ./deploy/bootstrap.sh
#
set -euo pipefail

APP_USER="${SUDO_USER:-$USER}"

echo ">> Installing base packages (needs sudo)..."
sudo dnf -y install ansible-core nginx python3 python3-pip firewalld \
    policycoreutils-python-utils podman git

echo ">> Installing Ansible collections for BOTH the deploy (root) and runtime (${APP_USER})..."
# Needed by site.yml at deploy time (runs under sudo = root):
sudo ansible-galaxy collection install ansible.posix community.general containers.podman
# Needed by the app at demo time (gunicorn runs as ${APP_USER}; switch-image.yml
# uses community.general.bootc_manage):
ansible-galaxy collection install community.general containers.podman

echo
echo ">> Bootstrap complete. Next:"
echo "   1) Edit deploy/vars.yml for your booth IPs/user."
echo "   2) sudo ansible-playbook deploy/site.yml"
echo "   3) Have your peer push the bootc images into the registry, then:"
echo "      ./deploy/preflight.sh"
