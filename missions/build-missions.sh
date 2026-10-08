#!/usr/bin/env bash
#
# Build every TACEDGE mission image and push it to the tablet registry.
# Run on the machine that builds images (the tablet or a RHEL build host).
#
#   ./missions/build-missions.sh                 # build + push all
#   ./missions/build-missions.sh cop isr         # build + push only these
#
# Env overrides:
#   REGISTRY=192.168.8.100:5000   REPO=bootc-flightgear
#   BASE_IMAGE=<registry>/<repo>:base   PUSH=false (build only)
#
set -euo pipefail
cd "$(dirname "$0")"

REGISTRY="${REGISTRY:-192.168.8.100:5000}"
REPO="${REPO:-bootc-flightgear}"
BASE_IMAGE="${BASE_IMAGE:-$REGISTRY/$REPO:base}"
PUSH="${PUSH:-true}"

# tag | mission dir | mode | version
ALL=(
  "cop|cop|nominal|COP v1.3"
  "cuas|cuas|nominal|C-UAS v2.4"
  "isr|isr|nominal|ISR v1.8"
  "netops|netops|nominal|NETOPS v3.1"
  "sustain|sustain|nominal|LOG v2.2"
  "cop-degraded|cop|degraded|COP v1.2"
  "home|home|nominal|BASE v1.0"
)

want=("$@")
for row in "${ALL[@]}"; do
  IFS='|' read -r tag dir mode ver <<<"$row"
  if [ ${#want[@]} -gt 0 ] && [[ ! " ${want[*]} " =~ " $tag " ]]; then continue; fi
  img="$REGISTRY/$REPO:$tag"
  echo ">> building $img  (mission=$dir mode=$mode)"
  podman build -f Containerfile \
    --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg REGISTRY="$REGISTRY" --build-arg MISSION="$dir" \
    --build-arg MODE="$mode" --build-arg TAG="$tag" --build-arg VERSION="$ver" \
    -t "$img" .
  if [ "$PUSH" = "true" ]; then
    echo ">> pushing $img"
    podman push --tls-verify=false "$img"
  fi
done
echo ">> done"
