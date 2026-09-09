#!/usr/bin/env bash
#
# Install the iHunter host services on a Jetson. Run once per board, at a desk.
#
#   sudo ./install.sh              install files only, change nothing running
#   sudo ./install.sh --enable     install, enable at boot, and start now
#   sudo ./install.sh --uninstall  remove the services (leaves the container)
#
# Installing is deliberately separate from enabling: putting files on a vehicle
# and changing what that vehicle does on power-up are different decisions.
#
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }

HERE="$(dirname "$(readlink -f "$0")")"
BIN=/usr/local/bin
UNITS=/etc/systemd/system

if [ "${1:-}" = "--uninstall" ]; then
    systemctl disable --now ihunter-router.service ihunter-container.service 2>/dev/null || true
    rm -f "$UNITS/ihunter-router.service" "$UNITS/ihunter-container.service"
    rm -f "$BIN/ihunter-container" "$BIN/ihunter-router" "$BIN/ihunter-run"
    systemctl daemon-reload
    echo "removed. The container itself was left alone."
    exit 0
fi

# Symlinks, not copies: a git pull of this repo updates the installed scripts,
# and there is never a stale second copy to wonder about.
ln -sf "$HERE/ihunter-container.sh" "$BIN/ihunter-container"
ln -sf "$HERE/ihunter-router.sh"    "$BIN/ihunter-router"
ln -sf "$HERE/ihunter-run.sh"       "$BIN/ihunter-run"

if [ ! -f /etc/ihunter.env ]; then
    cat > /etc/ihunter.env <<'ENV'
# iHunter host configuration. Per-board; not in git.
IHUNTER_CONTAINER=ihunter
IHUNTER_IMAGE=ihunter_container:r36.5.tegra-aarch64-cu126-22.04-ihunter
IHUNTER_USER=nvidia
IHUNTER_ROS_DISTRO=humble
# Refuse to create the container below this much free space on /.
IHUNTER_MIN_FREE_GB=3
# ROS workspace inside the container, and how long a launch gets to shut down
# cleanly before ihunter-run escalates (rosbag2 needs a clean exit).
IHUNTER_WS=/root/shared_volume/ros2_ws
IHUNTER_STOP_GRACE=45
IHUNTER_LOG_DAYS=30
ENV
    echo "wrote /etc/ihunter.env (edit for a different board or image)"
else
    echo "/etc/ihunter.env exists -- left as it is"
fi

install -m 0644 "$HERE/ihunter-container.service" "$UNITS/"
install -m 0644 "$HERE/ihunter-router.service"    "$UNITS/"
systemctl daemon-reload
echo "installed: ihunter-container, ihunter-router, ihunter-run"

if [ "${1:-}" = "--enable" ]; then
    systemctl enable --now ihunter-container.service
    systemctl enable --now ihunter-router.service
    echo
    ihunter-container status
else
    echo "not enabled. To turn on boot start:  sudo systemctl enable --now ihunter-container ihunter-router"
fi
