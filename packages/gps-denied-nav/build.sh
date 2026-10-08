#!/usr/bin/env bash
#
# Incremental build script for gps-denied-nav.
#
# Same foot-gun as packages/ihunter/build.sh: a bare
# 'jetson-containers build gps-denied-nav' names the chain after the last
# package, finds none of the existing stages and rebuilds all 18 of them,
# which does not fit on this device's disk.
#
# The existing chain was built under the name "ihunter_container". This
# script builds only the gps-denied-nav layer on top of the existing
# ihunter_container:*-gstreamer image, then re-tags the result as
# gpsdnav:<L4T tag> (the tag /etc/gpsdnav.env references).
#
# Usage:
#   ./build.sh              # incremental build (only the gps-denied-nav layer) + re-tag
#   ./build.sh --full       # full chain rebuild under the ihunter_container
#                            # name (only if you have disk headroom - check
#                            # `df -h /` first) + re-tag
#   ./build.sh --simulate   # dry run of the incremental build; verify it
#                            # prints exactly one "docker buildx build" whose
#                            # BASE_IMAGE is ihunter_container:*-gstreamer
set -euo pipefail

ROOT="$(dirname "$(readlink -f "$0")")"
REPO_ROOT=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || readlink -f "$ROOT/../..")

CHAIN_NAME=ihunter_container
PACKAGE=gps-denied-nav
RETAG_REPO=gpsdnav

cd "$REPO_ROOT"

# Re-tag ihunter_container:<tag>-gps-denied-nav as gpsdnav:<tag>.
retag() {
    local src
    src=$(docker images --format '{{.Repository}}:{{.Tag}}' \
        | grep -E "^${CHAIN_NAME}:.*-${PACKAGE}\$" | head -n1 || true)
    if [ -z "$src" ]; then
        echo "build.sh: no ${CHAIN_NAME}:*-${PACKAGE} image found to re-tag" >&2
        exit 1
    fi
    local tag=${src#${CHAIN_NAME}:}
    tag=${tag%-${PACKAGE}}
    docker tag "$src" "${RETAG_REPO}:${tag}"
    echo "build.sh: tagged $src -> ${RETAG_REPO}:${tag}"
}

if [ "${1:-}" = "--full" ]; then
    shift
    jetson-containers build --name "$CHAIN_NAME" --skip-tests all "$PACKAGE" "$@"
    retag
elif [ "${1:-}" = "--simulate" ]; then
    shift
    exec jetson-containers build --simulate --name "$CHAIN_NAME" --start-from "$PACKAGE" --skip-tests all "$PACKAGE" "$@"
else
    jetson-containers build --name "$CHAIN_NAME" --start-from "$PACKAGE" --skip-tests all "$PACKAGE" "$@"
    retag
fi
