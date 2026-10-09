#!/usr/bin/env bash
#
# Choose which demo the tablet controller shows, and (re)start it.
# Run ON THE TABLET:
#
#   ./deploy/use-demo.sh tacedge      # TACEDGE mission apps (default, tested)
#   ./deploy/use-demo.sh flightgear   # FlightGear flight-sim images
#   ./deploy/use-demo.sh both         # a mix of both
#
# It checks the registry first and stops if the images for that choice are
# missing, so you never put a button on screen that can't work.
# Override any setting with an environment variable, e.g. FORCE=1 to skip the check.
#
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-}"
TARGET_IPS="${TARGET_IPS:-192.168.8.101,192.168.8.102}"
REGISTRY_HOST="${REGISTRY_HOST:-192.168.8.100:5000}"
IMAGE_REPO="${IMAGE_REPO:-bootc-flightgear}"
TARGET_SSH_USER="${TARGET_SSH_USER:-core}"
TARGET_SSH_PASS="${TARGET_SSH_PASS:-edge}"
TARGET_BECOME_PASS="${TARGET_BECOME_PASS:-edge}"
PORT="${PORT:-8080}"
IMAGE="${IMAGE:-localhost/workload-selector:latest}"

case "$MODE" in
  tacedge)    WORKLOADS="cop,cuas,isr,netops,sustain,cop-degraded,home" ;;
  flightgear) WORKLOADS="f22,b52,f35,f35-fixed,base" ;;
  both)       WORKLOADS="cop,cuas,isr,cop-degraded,f22,f35,f35-fixed,home" ;;
  *) echo "Usage: $0 tacedge | flightgear | both"; exit 1 ;;
esac

echo "== Demo choice: ${MODE^^}"
echo "   buttons: $WORKLOADS"

# 1. Make sure every image for this choice exists in the registry
tags="$(curl -fsS --max-time 5 "http://${REGISTRY_HOST}/v2/${IMAGE_REPO}/tags/list" 2>/dev/null || true)"
if [ -z "$tags" ]; then
  echo "!! Can't reach the registry at ${REGISTRY_HOST}. Is it running?"; [ "${FORCE:-0}" = 1 ] || exit 1
fi
missing=()
IFS=',' read -ra want <<<"$WORKLOADS"
for t in "${want[@]}"; do echo "$tags" | grep -q "\"$t\"" || missing+=("$t"); done
if [ ${#missing[@]} -gt 0 ]; then
  echo "!! These images are NOT in the registry yet: ${missing[*]}"
  echo "   Build/push them first (TACEDGE: ./missions/build-missions.sh, FlightGear: your flightgear-kiosk-demo build)."
  if [ "${FORCE:-0}" != 1 ]; then echo "   Stopping. (FORCE=1 $0 $MODE to start anyway.)"; exit 1; fi
fi
echo "   registry check: OK"

# 2. Field Docs key from the podman secret, if it exists
secret_args=()
if podman secret inspect okp_key >/dev/null 2>&1; then
  secret_args=(--secret okp_key,type=env,target=OKP_ACCESS_KEY); echo "   field docs: ENABLED (okp_key secret found)"
else
  echo "   field docs: disabled (no okp_key secret — see PEER-SETUP Step 5)"
fi

# 3. Restart the controller with the chosen buttons
podman rm -f ws >/dev/null 2>&1 || true
podman run -d --name ws --network host \
  -e TARGET_IPS="$TARGET_IPS" -e TARGET_SSH_USER="$TARGET_SSH_USER" \
  -e TARGET_SSH_PASS="$TARGET_SSH_PASS" -e TARGET_BECOME_PASS="$TARGET_BECOME_PASS" \
  -e REGISTRY_HOST="$REGISTRY_HOST" -e IMAGE_REPO="$IMAGE_REPO" \
  -e WORKLOADS="$WORKLOADS" -e PORT="$PORT" ${MOCK_MODE:+-e MOCK_MODE="$MOCK_MODE"} \
  "${secret_args[@]}" "$IMAGE" >/dev/null

# 4. Confirm it's up
for i in $(seq 1 15); do
  if curl -fsS --max-time 2 "http://localhost:${PORT}/healthz" >/dev/null 2>&1; then
    echo "== Controller is UP showing ${MODE^^}. Refresh the browser: http://localhost:${PORT}/"; exit 0
  fi; sleep 1
done
echo "!! Controller didn't come up. Check: podman logs ws"; exit 1
