#!/usr/bin/env bash
#
# Booth-day GO / NO-GO check. Run this ON THE TABLET before a customer is
# standing there. It checks the whole chain: web app up, registry reachable
# and holding images, target pingable, and Ansible can actually log in.
#
#   ./deploy/preflight.sh
#
# Override any of these for your booth:
TARGET_IPS="${TARGET_IPS:-${TARGET_IP:-192.168.8.101,192.168.8.102}}"
REGISTRY_HOST="${REGISTRY_HOST:-192.168.8.100:5000}"
IMAGE_REPO="${IMAGE_REPO:-bootc-flightgear}"
WEB_URL="${WEB_URL:-http://localhost/healthz}"
TARGET_SSH_USER="${TARGET_SSH_USER:-core}"
TARGET_SSH_PASS="${TARGET_SSH_PASS:-edge}"

pass=0; fail=0
ok()   { echo "  [ OK ]  $1"; pass=$((pass+1)); }
bad()  { echo "  [FAIL]  $1"; fail=$((fail+1)); }

echo "== Workload Selector preflight =="

# 1. Web app
if curl -fsS --max-time 5 "$WEB_URL" >/dev/null 2>&1; then
    ok "Web app answering at $WEB_URL"
else
    bad "Web app NOT answering at $WEB_URL (is the container/service running?)"
fi

# 2. Registry reachable + lists images
if curl -fsS --max-time 5 "http://${REGISTRY_HOST}/v2/_catalog" >/dev/null 2>&1; then
    tags=$(curl -fsS --max-time 5 "http://${REGISTRY_HOST}/v2/${IMAGE_REPO}/tags/list" 2>/dev/null || true)
    if echo "$tags" | grep -q '"tags"'; then
        ok "Registry up and has ${IMAGE_REPO}: ${tags}"
    else
        bad "Registry up but no tags for ${IMAGE_REPO} (peer needs to push images)"
    fi
else
    bad "Registry NOT reachable at ${REGISTRY_HOST}"
fi

# 3 + 4. Each target: reachable on the LAN, and Ansible can log in and run
IFS=',' read -ra TARGETS <<< "$TARGET_IPS"
for ip in "${TARGETS[@]}"; do
    ip="$(echo "$ip" | xargs)"
    [ -z "$ip" ] && continue
    if ping -c1 -W2 "$ip" >/dev/null 2>&1; then
        ok "Target $ip responds to ping"
    else
        bad "Target $ip not pinging (check travel-router LAN / static IPs)"
    fi
    if command -v ansible >/dev/null 2>&1; then
        if ANSIBLE_HOST_KEY_CHECKING=False ansible all -i "${ip}," -m ping \
             -e ansible_user="$TARGET_SSH_USER" \
             -e ansible_password="$TARGET_SSH_PASS" \
             -e ansible_connection=ssh >/dev/null 2>&1; then
            ok "Ansible reached $ip (ssh + login good)"
        else
            bad "Ansible could NOT log in to $ip (creds / ssh)"
        fi
    else
        echo "  [SKIP]  ansible not on this host for $ip"
    fi
done

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] && echo ">> GO" || { echo ">> NO-GO — fix the FAIL lines above"; exit 1; }
