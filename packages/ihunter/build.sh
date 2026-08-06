#!/usr/bin/env bash
#
# Incremental build script for ihunter.
#
# 'jetson-containers build ihunter' alone is a foot-gun: with no --name it
# computes the image name from the last package ("ihunter", not
# "ihunter_container"), so every stage's BASE_IMAGE points at images that
# don't exist and it rebuilds the entire 18-stage chain from scratch. On
# this device the root filesystem does not have room for that.
#
# The existing chain was built under the name "ihunter_container". This
# script reproduces the one-line incremental build that only rebuilds the
# ihunter layer on top of the existing ihunter_container:*-gstreamer image.
# See ../../../ihunter_jetson_nx_debug/jetson-containers-incremental-build-plan.md
# for the full diagnosis if this ever needs re-deriving.
#
# Usage:
#   ./build.sh              # incremental build (only the ihunter layer)
#   ./build.sh --full       # full chain rebuild under the ihunter_container
#                            # name (only if you have disk headroom - check
#                            # `df -h /` first)
#   ./build.sh --simulate   # dry run of the incremental build; verify it
#                            # prints exactly one "docker buildx build"
#                            # before ever running for real
set -euo pipefail

ROOT="$(dirname "$(readlink -f "$0")")"
REPO_ROOT=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null || readlink -f "$ROOT/../..")

cd "$REPO_ROOT"

if [ "${1:-}" = "--full" ]; then
    shift
    exec jetson-containers build --name ihunter_container --skip-tests all ihunter "$@"
elif [ "${1:-}" = "--simulate" ]; then
    shift
    exec jetson-containers build --simulate --name ihunter_container --start-from ihunter --skip-tests all ihunter "$@"
else
    exec jetson-containers build --name ihunter_container --start-from ihunter --skip-tests all ihunter "$@"
fi
