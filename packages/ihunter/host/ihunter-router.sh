#!/usr/bin/env bash
#
# The zenoh router, in the foreground, so systemd can supervise and restart it.
#
# rmw_zenoh_cpp discovery fails *silently* without a router: nodes run, topics
# exist, and the ground station simply sees nothing. That failure mode is the
# reason this is a supervised service and not a line someone remembers to type.
#
set -euo pipefail
[ -r /etc/ihunter.env ] && . /etc/ihunter.env

CONTAINER_NAME="${IHUNTER_CONTAINER:-ihunter}"
ROS_DISTRO_NAME="${IHUNTER_ROS_DISTRO:-humble}"

# Fail rather than spin if the container is not up; systemd's BindsTo already
# ties this unit's life to the container's.
docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | grep -qx true \
    || { echo "ihunter-router: container $CONTAINER_NAME is not running" >&2; exit 1; }

# Already running (started by hand, or a leftover): attach to its lifetime
# instead of starting a second one, which would fight over the port.
#
# Liveness is matched on the process NAME and excludes zombies. `pgrep -f` would
# match this very watch loop (its command line contains the string), and any
# pgrep at all counts a <defunct> router as running -- either way the loop never
# exits and a dead router reports healthy. Both observed 2026-09-09.
alive='ps -eo stat,comm | awk "\$2 == \"rmw_zenohd\" && \$1 !~ /Z/ { a = 1 } END { exit !a }"'

if docker exec "$CONTAINER_NAME" bash -c "$alive"; then
    echo "ihunter-router: router already running in $CONTAINER_NAME; supervising it"
    exec docker exec "$CONTAINER_NAME" bash -c "while $alive; do sleep 5; done"
fi

exec docker exec "$CONTAINER_NAME" bash -lc \
    "source /opt/ros/${ROS_DISTRO_NAME}/setup.bash && exec ros2 run rmw_zenoh_cpp rmw_zenohd"
