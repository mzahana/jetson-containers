#!/usr/bin/env bash
#
# ihunter-container -- the ihunter container as a long-lived service.
#
# Field operations plan, phase F0. The point of this script is that no
# long-running flight process is ever parented by an SSH session: the container
# runs detached, owned by the Docker daemon, and everything else is a
# `docker exec` into it. Losing the laptop, the wifi or the SSH connection then
# has no effect on what is running on the aircraft.
#
# It deliberately reuses jetson-containers' own run.sh rather than
# reimplementing the Jetson hardware mounts (tegra libs, multimedia API, V4L2,
# I2C, ACM, argus socket). Those are easy to get subtly wrong and the failure
# shows up as a camera or CUDA fault in the field. The only things added here
# are --detach, --no-rm, a restart policy, and a main process that stays up.
#
# Offline-safe: the image is named explicitly, so nothing contacts a registry.
# `jetson-containers run ihunter` cannot be used in the field for exactly that
# reason -- its autotag step needs the network.
#
#   ihunter-container up         create if missing, start if stopped (idempotent)
#   ihunter-container status     what is running, and what state it is in
#   ihunter-container stop       stop the container (does not delete it)
#   ihunter-container recreate   delete and re-create from the pinned flags
#   ihunter-container shell      interactive shell inside it
#
set -euo pipefail

# --- configuration -----------------------------------------------------------
# Overridable from /etc/ihunter.env so a second airframe needs no edit here.
[ -r /etc/ihunter.env ] && . /etc/ihunter.env

CONTAINER_NAME="${IHUNTER_CONTAINER:-ihunter}"
IMAGE="${IHUNTER_IMAGE:-ihunter_container:r36.5.tegra-aarch64-cu126-22.04-ihunter}"
# systemd runs this as root, so $HOME is /root -- the owning user is explicit.
OWNER="${IHUNTER_USER:-nvidia}"
SHARED_VOLUME="${IHUNTER_SHARED_VOLUME:-/home/$OWNER/${CONTAINER_NAME}_shared_volume}"
RESTART_POLICY="${IHUNTER_RESTART_POLICY:-unless-stopped}"
# Free space below this refuses container creation: a full disk on this board
# has ended a session before (~9 GB free of 116 GB is the standing state).
MIN_FREE_GB="${IHUNTER_MIN_FREE_GB:-3}"

HERE="$(dirname "$(readlink -f "$0")")"
# host/ -> ihunter/ -> packages/ -> repo root
JC_ROOT="${IHUNTER_JC_ROOT:-$(readlink -f "$HERE/../../..")}"

die() { echo "ihunter-container: $*" >&2; exit 1; }
say() { echo "### $*"; }

exists()  { [ -n "$(docker ps -aq -f "name=^/${CONTAINER_NAME}$")" ]; }
running() { [ -n "$(docker ps  -q -f "name=^/${CONTAINER_NAME}$")" ]; }

# A live router, not a zombie one. Matching on the process NAME (not the command
# line, which also matches the supervisor) and excluding state Z (a reaped-by-
# nobody corpse still answers pgrep, but routes nothing).
router_alive() {
    docker exec "$CONTAINER_NAME" ps -eo stat,comm 2>/dev/null \
        | awk '$2 == "rmw_zenohd" && $1 !~ /Z/ { alive = 1 } END { exit !alive }'
}

# --- reboot-wiped bind-mount targets -----------------------------------------
# A reboot clears /tmp, and Docker then recreates these mount targets as
# *directories* when it starts a container that binds them. The bind then fails
# with "not a directory", and the container will not start until they are files
# again. jetson-containers' run.sh writes them on create; nothing writes them
# before a `docker start`, which is why a container that worked yesterday
# refuses to start after a power cycle. Observed on the lab board, 2026-09-09.
prepare_mount_targets() {
    # Docker created these as root-owned directories, so repairing them needs
    # root. Under systemd we already are; run by hand, sudo will ask.
    local SUDO=""
    [ "$(id -u)" -eq 0 ] || SUDO="sudo"
    if [ ! -f /tmp/nv_jetson_model ]; then
        say "repairing /tmp/nv_jetson_model (wiped by reboot)"
        $SUDO rm -rf /tmp/nv_jetson_model
        $SUDO sh -c 'cat /proc/device-tree/model > /tmp/nv_jetson_model'
        $SUDO chmod 644 /tmp/nv_jetson_model
    fi
    if [ ! -f /tmp/.docker.xauth ]; then
        say "repairing /tmp/.docker.xauth (wiped by reboot)"
        $SUDO rm -rf /tmp/.docker.xauth
        $SUDO touch /tmp/.docker.xauth
        $SUDO chmod 777 /tmp/.docker.xauth
    fi

    # /run/jtop.sock belongs to jtop.service, which starts AFTER
    # multi-user.target -- i.e. after this unit. Docker's own restart policy
    # will already have tried and failed to start the container by then, and a
    # failed bind leaves the path behind as a DIRECTORY, which would also break
    # jtop when it finally starts. Clear it; never wait for it (waiting here
    # deadlocks: jtop cannot start until multi-user.target completes, and this
    # unit is part of multi-user.target). The container is created without the
    # jtop mount when the socket is absent, which costs only jtop-inside-the-
    # container -- nothing flight-related. Found by the reboot test 2026-09-09.
    if [ -d /run/jtop.sock ]; then
        say "clearing /run/jtop.sock (left as a directory by a failed bind)"
        $SUDO rm -rf /run/jtop.sock
    fi
}

# --- create ------------------------------------------------------------------
# Checked before anything is destroyed, so a missing image can never leave the
# board with no container at all.
preflight() {
    [ -x "$JC_ROOT/run.sh" ] || die "jetson-containers run.sh not found at $JC_ROOT"
    docker image inspect "$IMAGE" >/dev/null 2>&1 \
        || die "image $IMAGE is not present locally. Build it at a desk with
       packages/ihunter/build.sh -- there is no registry pull in this path."
}

create() {
    prepare_mount_targets
    preflight

    local free_gb
    free_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
    [ "$free_gb" -ge "$MIN_FREE_GB" ] \
        || die "only ${free_gb}G free on / (need ${MIN_FREE_GB}G). Sweep bags before flying."

    mkdir -p "$SHARED_VOLUME"/{logs,bags,reports}
    chown -R "$OWNER:$OWNER" "$SHARED_VOLUME"/{logs,bags,reports} 2>/dev/null || true

    # Same hardware mounts packages/ihunter/run.sh applies, and for the same
    # reason: mount only what this board actually has.
    local hw=()
    local p
    for p in /usr/bin/tegrastats /usr/lib/aarch64-linux-gnu/tegra \
             /usr/src/jetson_multimedia_api /opt/nvidia/nsight-systems-cli \
             /opt/nvidia/vpi2 /usr/share/vpi2; do
        [ -e "$p" ] && hw+=(-v "$p:$p")
    done

    say "Creating $CONTAINER_NAME from $IMAGE"
    # --no-rm because a restart policy and --rm are mutually exclusive.
    # `sleep infinity` as PID 1 is the whole trick: the container's life is not
    # tied to any one job, so a launch can be started, stopped and restarted
    # inside it without the container going away underneath.
    # --init puts tini at PID 1. Without it, `sleep infinity` is PID 1 and never
    # reaps: a router that dies is reparented to it and stays as a <defunct>
    # zombie forever. pgrep counts zombies, so the supervisor and `status` both
    # report a healthy router over a dead one -- a silent-failure mode on top of
    # the silent-failure mode this router exists to prevent. Observed 2026-09-09.
    "$JC_ROOT/run.sh" \
        --name "$CONTAINER_NAME" \
        --no-rm \
        --detach \
        --init \
        --restart "$RESTART_POLICY" \
        --privileged \
        --ipc=host \
        -v "$SHARED_VOLUME:/root/shared_volume" \
        -e RMW_IMPLEMENTATION=rmw_zenoh_cpp \
        "${hw[@]}" \
        "$IMAGE" \
        sleep infinity
}

# --- verbs -------------------------------------------------------------------
up() {
    if running; then
        say "$CONTAINER_NAME already running"
    else
        # Recreate rather than start. A stopped container still holds the bind
        # mounts it was created with, and at boot some of those paths do not
        # exist yet in the shape they had at create time -- /run/jtop.sock is
        # created late, and /tmp is wiped. Re-creating from the pinned flags is
        # deterministic and costs nothing: every output of a flight goes to the
        # bind-mounted shared volume by design, so the container's writable
        # layer holds nothing worth keeping. Cattle, not a pet.
        preflight
        if exists; then
            say "Recreating $CONTAINER_NAME from the pinned flags"
            docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        fi
        create
    fi
    # Applies the policy to a container created before this script existed, and
    # is a no-op on one it created. Cheap, and it is what survives a reboot.
    docker update --restart "$RESTART_POLICY" "$CONTAINER_NAME" >/dev/null 2>&1 || true
    running || die "$CONTAINER_NAME failed to start -- docker logs $CONTAINER_NAME"
    say "$CONTAINER_NAME up"
}

status() {
    if ! exists; then echo "container:  absent"; else
        echo "container:  $(docker inspect -f '{{.State.Status}} (restart={{.HostConfig.RestartPolicy.Name}}, since {{.State.StartedAt}})' "$CONTAINER_NAME")"
    fi
    if running && router_alive; then
        echo "router:     running"
    else
        echo "router:     DOWN        <-- discovery fails silently without it"
    fi
    echo "image:      $IMAGE"
    echo "shared vol: $SHARED_VOLUME"
    echo "disk free:  $(df -h --output=avail / | tail -1 | tr -d ' ') of $(df -h --output=size / | tail -1 | tr -d ' ')"
}

case "${1:-up}" in
    up)       up ;;
    create)   exists && die "$CONTAINER_NAME already exists (use recreate)"; create ;;
    start)    prepare_mount_targets; docker start "$CONTAINER_NAME" >/dev/null && say "started" ;;
    stop)     docker stop "$CONTAINER_NAME" >/dev/null && say "stopped" ;;
    recreate) preflight; say "Removing $CONTAINER_NAME"; docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true; create ;;
    shell)    exec docker exec -it "$CONTAINER_NAME" bash ;;
    status)   status ;;
    *)        die "usage: ihunter-container {up|create|start|stop|recreate|shell|status}" ;;
esac
