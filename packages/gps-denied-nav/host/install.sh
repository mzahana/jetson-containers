#!/usr/bin/env bash
#
# Install the gpsdnav host services on a Jetson. Run once per board, at a desk.
#
#   sudo ./install.sh              install files only, change nothing running
#   sudo ./install.sh --enable     install, then hand the board to gpsdnav
#                                  (drone-mode gpsdnav: disables iHunter at boot)
#   sudo ./install.sh --uninstall  remove the services (leaves the container)
#
# Installing is deliberately separate from enabling: putting files on a vehicle
# and changing what that vehicle does on power-up are different decisions. On
# this board that matters twice, because enabling gpsdnav disables iHunter.
#
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

HERE="$(dirname "$(readlink -f "$0")")"
BIN=/usr/local/bin
UNITS=/etc/systemd/system

if [ "${1:-}" = "--uninstall" ]; then
    systemctl disable --now gpsdnav-router.service gpsdnav-container.service 2>/dev/null || true
    rm -f "$UNITS/gpsdnav-router.service" "$UNITS/gpsdnav-container.service"
    rm -f "$BIN/gpsdnav-container" "$BIN/gpsdnav-router" "$BIN/gpsdnav-run" "$BIN/drone-mode"
    systemctl daemon-reload
    echo "removed. The container itself was left alone."
    exit 0
fi

# Symlinks, not copies: a git pull of this repo updates the installed scripts,
# and there is never a stale second copy to wonder about.
ln -sf "$HERE/gpsdnav-container.sh" "$BIN/gpsdnav-container"
ln -sf "$HERE/gpsdnav-router.sh"    "$BIN/gpsdnav-router"
ln -sf "$HERE/gpsdnav-run.sh"       "$BIN/gpsdnav-run"
ln -sf "$HERE/drone-mode.sh"        "$BIN/drone-mode"

if [ ! -f /etc/gpsdnav.env ]; then
    cat > /etc/gpsdnav.env <<'ENV'
# gpsdnav host configuration. Per-board; not in git.
GPSDNAV_CONTAINER=gpsdnav
GPSDNAV_IMAGE=gpsdnav:r36.5.tegra-aarch64-cu126-22.04
GPSDNAV_USER=nvidia
GPSDNAV_ROS_DISTRO=humble
# Refuse to create the container or start a launch below this much free space
# on /. Higher than iHunter's 3: bags with images are about 5 GB/h.
GPSDNAV_MIN_FREE_GB=10
# ROS workspace inside the container, and how long a launch gets to shut down
# cleanly before gpsdnav-run escalates (rosbag2 needs a clean exit).
GPSDNAV_WS=/root/shared_volume/ros2_ws
GPSDNAV_STOP_GRACE=60
GPSDNAV_LOG_DAYS=30
# Containers that must not run at the same time as this one (shared board).
GPSDNAV_EXCLUSIVE_WITH=ihunter
ENV
    echo "wrote /etc/gpsdnav.env (edit for a different board or image)"
else
    echo "/etc/gpsdnav.env exists -- left as it is"
fi

install -m 0644 "$HERE/gpsdnav-container.service" "$UNITS/"
install -m 0644 "$HERE/gpsdnav-router.service"    "$UNITS/"
systemctl daemon-reload
echo "installed: gpsdnav-container, gpsdnav-router, gpsdnav-run, drone-mode"

if [ "${1:-}" = "--enable" ]; then
    "$BIN/drone-mode" gpsdnav
else
    echo "not enabled. To hand the board to gpsdnav:  sudo drone-mode gpsdnav"
    echo
    "$BIN/drone-mode" status
fi
