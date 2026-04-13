#!/usr/bin/env bash
#
# Custom run script for gps-denied-nav
# This script is automatically called by 'jetson-containers run gps-denied-nav'
#
ROOT="$(dirname "$(readlink -f "$0")")"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || readlink -f "$ROOT/../..")

# Default configurations
CONTAINER_NAME="gps-denied-nav"
IMAGE="gpsd:r36.5.tegra-aarch64-cu126-22.04"
HOST_SHARED_VOLUME="$HOME/${CONTAINER_NAME}_shared_volume"

# Create the shared volume on the host if it doesn't exist
mkdir -p "$HOST_SHARED_VOLUME"

echo "### Package-specific run: $CONTAINER_NAME"
echo "### Image:         $IMAGE"
echo "### Shared Volume: $HOST_SHARED_VOLUME"

# Call the core run.sh with the necessary flags
# --no-rm maintains the container after exit for re-entry
# --privileged is used for hardware/USB access
exec $REPO_ROOT/run.sh \
    --name "$CONTAINER_NAME" \
    --no-rm \
    --privileged \
    -v "$HOST_SHARED_VOLUME:/root/shared_volume" \
    -e RMW_IMPLEMENTATION=rmw_zenoh_cpp \
    "$IMAGE" \
    "$@"
