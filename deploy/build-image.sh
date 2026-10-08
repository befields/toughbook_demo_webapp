#!/usr/bin/env bash
#
# Build the control-plane image and save it as a tarball for the shared drive.
# Run this ON YOUR FEDORA LAPTOP (online).
#
#   ./deploy/build-image.sh
#
# Output: ./workload-selector.tar  (drop this on the shared drive)
#
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE="${IMAGE:-workload-selector:latest}"
OUT="${OUT:-workload-selector.tar}"

echo ">> Building ${IMAGE} ..."
podman build -t "${IMAGE}" -f Containerfile .

echo ">> Saving to ${OUT} ..."
podman save -o "${OUT}" "${IMAGE}"

echo
echo ">> Done: ${OUT} ($(du -h "${OUT}" | cut -f1))"
echo "   1) Copy ${OUT} to your shared drive."
echo "   2) Your peer runs, on the tablet:"
echo "        podman load -i ${OUT}"
echo "        (then the run command in DEPLOY.md / the quadlet)"
