#!/usr/bin/env bash
#
# ihunter-run -- start, stop and inspect a flight launch inside the container.
#
# Field operations plan, phase F1. Every launch is started DETACHED inside the
# already-running container, so its parent is the Docker daemon and not an SSH
# session. Losing the laptop, the wifi, or the terminal cannot stop a flight.
# There is no tmux here and none is needed.
#
#   ihunter-run start <name> <pkg> <launch_file> [key:=value ...]
#   ihunter-run stop [name]        SIGINT, wait, escalate. Closes bags cleanly.
#   ihunter-run status             what is running, its log, its bag
#   ihunter-run logs [name] [-f]   the launch's console output
#   ihunter-run prune              delete logs older than IHUNTER_LOG_DAYS
#
set -euo pipefail
[ -r /etc/ihunter.env ] && . /etc/ihunter.env

CONTAINER_NAME="${IHUNTER_CONTAINER:-ihunter}"
ROS_DISTRO_NAME="${IHUNTER_ROS_DISTRO:-humble}"
OWNER="${IHUNTER_USER:-nvidia}"
HOST_SHARED="${IHUNTER_SHARED_VOLUME:-/home/$OWNER/${CONTAINER_NAME}_shared_volume}"
# The same directory as seen from inside the container.
CTR_SHARED=/root/shared_volume
WS="${IHUNTER_WS:-$CTR_SHARED/ros2_ws}"
MIN_FREE_GB="${IHUNTER_MIN_FREE_GB:-3}"
LOG_DAYS="${IHUNTER_LOG_DAYS:-30}"
# How long a launch may take to shut down cleanly before we escalate. rosbag2
# writes metadata.yaml only on a clean exit, so this is generous on purpose.
STOP_GRACE="${IHUNTER_STOP_GRACE:-45}"

die() { echo "ihunter-run: $*" >&2; exit 1; }
say() { echo "### $*"; }
ctr() { docker exec "$CONTAINER_NAME" "$@"; }

container_up() {
    [ -n "$(docker ps -q -f "name=^/${CONTAINER_NAME}$")" ] \
        || die "container $CONTAINER_NAME is not running (try: ihunter-container up)"
}

# A run is identified by a marker directory in the shared volume, so it survives
# the container and can be read from the host without entering it.
run_dir()  { echo "$HOST_SHARED/run"; }
pid_of()   { cat "$(run_dir)/$1.pid" 2>/dev/null || true; }
alive()    { local p="$1"; [ -n "$p" ] && ctr kill -0 "$p" >/dev/null 2>&1; }

running_names() {
    local f n p
    for f in "$(run_dir)"/*.pid; do
        [ -e "$f" ] || continue
        n="$(basename "$f" .pid)"; p="$(pid_of "$n")"
        alive "$p" && echo "$n"
    done
}

# --- start -------------------------------------------------------------------
start() {
    local name="${1:-}"; shift || true
    local pkg="${1:-}"; shift || true
    local file="${1:-}"; shift || true
    [ -n "$name" ] && [ -n "$pkg" ] && [ -n "$file" ] \
        || die "usage: ihunter-run start <name> <pkg> <launch_file> [args...]"
    container_up

    # One flight at a time. Two launches means two publishers into the same
    # controller input, which is the single thing the launch files are written
    # to prevent -- so it must be impossible here, not merely unlikely.
    local busy; busy="$(running_names | tr '\n' ' ')"
    [ -z "$busy" ] || die "already running: $busy   (ihunter-run stop first)"

    local free_gb; free_gb=$(df -BG --output=avail "$HOST_SHARED" | tail -1 | tr -dc '0-9')
    [ "$free_gb" -ge "$MIN_FREE_GB" ] \
        || die "only ${free_gb}G free (need ${MIN_FREE_GB}G). Fetch and sweep bags first."

    mkdir -p "$HOST_SHARED/logs" "$HOST_SHARED/run" "$HOST_SHARED/bags"
    chown -R "$OWNER:$OWNER" "$HOST_SHARED/logs" "$HOST_SHARED/run" "$HOST_SHARED/bags" 2>/dev/null || true

    local stamp log
    stamp="$(date -u +%Y%m%d-%H%M%S)"
    log="$CTR_SHARED/logs/${name}_${stamp}.log"

    # Quote every launch argument for the shell that runs inside the container.
    local args="" a
    for a in "$@"; do args+=" $(printf '%q' "$a")"; done

    say "Starting $name: ros2 launch $pkg $file$args"
    say "Log: $HOST_SHARED/logs/${name}_${stamp}.log"

    # `exec ros2 launch` replaces this shell, so the PID written here stays the
    # PID of the launch -- which is what `stop` sends SIGINT to.
    docker exec -d "$CONTAINER_NAME" bash -c "
        exec > $(printf '%q' "$log") 2>&1
        echo \"### \$(date -u +%FT%TZ) ihunter-run start $name\"
        source /opt/ros/${ROS_DISTRO_NAME}/setup.bash
        source $(printf '%q' "$WS")/install/setup.bash
        echo \$\$ > $(printf '%q' "$CTR_SHARED/run/$name.pid")
        exec ros2 launch $(printf '%q' "$pkg") $(printf '%q' "$file")$args
    "

    echo "ros2 launch $pkg $file$args" > "$(run_dir)/$name.cmd"
    echo "$HOST_SHARED/logs/${name}_${stamp}.log" > "$(run_dir)/$name.log"

    # Confirm it is actually up rather than reporting success on a typo.
    local i p
    for i in $(seq 1 20); do
        p="$(pid_of "$name")"
        alive "$p" && { say "$name running (pid $p)"; return 0; }
        sleep 1
    done
    echo "ihunter-run: $name did not come up. Last lines of its log:" >&2
    tail -20 "$HOST_SHARED/logs/${name}_${stamp}.log" 2>/dev/null >&2 || true
    rm -f "$(run_dir)/$name.pid"
    exit 1
}

# --- stop --------------------------------------------------------------------
stop_one() {
    local name="$1" p i
    p="$(pid_of "$name")"
    if ! alive "$p"; then
        say "$name is not running"
        rm -f "$(run_dir)/$name.pid"
        return 0
    fi
    # SIGINT, never SIGKILL first. `ros2 launch` forwards it to every node, and
    # rosbag2 writes its metadata.yaml on that clean shutdown -- a bag killed
    # before it finishes has no index and is painful to recover.
    say "Stopping $name (pid $p) with SIGINT"
    ctr kill -INT "$p" || true
    for i in $(seq 1 "$STOP_GRACE"); do
        alive "$p" || { say "$name stopped cleanly after ${i}s"; rm -f "$(run_dir)/$name.pid"; return 0; }
        sleep 1
    done
    say "still up after ${STOP_GRACE}s -- escalating to SIGTERM"
    ctr kill -TERM "$p" || true
    for i in $(seq 1 10); do
        alive "$p" || { rm -f "$(run_dir)/$name.pid"; return 0; }
        sleep 1
    done
    say "escalating to SIGKILL -- any bag from this run may be missing metadata.yaml"
    ctr kill -KILL "$p" || true
    rm -f "$(run_dir)/$name.pid"
}

stop() {
    container_up
    if [ $# -gt 0 ]; then stop_one "$1"; return; fi
    local n any=""
    while read -r n; do [ -n "$n" ] || continue; any=1; stop_one "$n"; done < <(running_names)
    [ -n "$any" ] || say "nothing running"
}

# --- status ------------------------------------------------------------------
status() {
    local n p any=""
    while read -r n; do
        [ -n "$n" ] || continue
        any=1; p="$(pid_of "$n")"
        echo "run:        $n (pid $p)"
        echo "  command:  $(cat "$(run_dir)/$n.cmd" 2>/dev/null || echo '?')"
        echo "  log:      $(cat "$(run_dir)/$n.log" 2>/dev/null || echo '?')"
    done < <(running_names)
    [ -n "$any" ] || echo "run:        nothing running"

    # The newest bag, and whether it has been closed properly. metadata.yaml is
    # written on clean shutdown, so its absence in a bag nobody is writing to is
    # the signature of a hard kill.
    local bag
    bag="$(ls -1dt "$HOST_SHARED"/bags/*/ 2>/dev/null | head -1 || true)"
    if [ -n "$bag" ]; then
        echo "bag:        $bag ($(du -sh "$bag" 2>/dev/null | cut -f1))"
        if [ -f "$bag/metadata.yaml" ]; then echo "  closed:   yes"
        elif [ -n "$any" ];                 then echo "  closed:   not yet (still recording)"
        else echo "  closed:   NO -- written by a run that did not shut down cleanly"; fi
    else
        echo "bag:        none yet"
    fi
    echo "disk free:  $(df -h --output=avail "$HOST_SHARED" | tail -1 | tr -d ' ')"
}

logs() {
    local name="${1:-}" follow="${2:-}"
    [ -n "$name" ] || name="$(running_names | head -1)"
    [ -n "$name" ] || { local l; l="$(ls -1t "$HOST_SHARED"/logs/*.log 2>/dev/null | head -1)"; \
                        [ -n "$l" ] || die "no logs yet"; \
                        [ "$follow" = "-f" ] && exec tail -f "$l" || exec tail -100 "$l"; }
    local f; f="$(cat "$(run_dir)/$name.log" 2>/dev/null || true)"
    [ -n "$f" ] && [ -f "$f" ] || f="$(ls -1t "$HOST_SHARED"/logs/${name}_*.log 2>/dev/null | head -1)"
    [ -n "$f" ] || die "no log for '$name'"
    if [ "$follow" = "-f" ]; then exec tail -f "$f"; else exec tail -100 "$f"; fi
}

prune() {
    local n
    n=$(find "$HOST_SHARED/logs" -name '*.log' -mtime "+$LOG_DAYS" -print -delete 2>/dev/null | wc -l)
    say "pruned $n log(s) older than $LOG_DAYS days"
    say "bags are NEVER pruned automatically -- use ihunter fetch, then delete by hand"
}

case "${1:-status}" in
    start)  shift; start "$@" ;;
    stop)   shift; stop "$@" ;;
    status) status ;;
    logs)   shift; logs "$@" ;;
    prune)  prune ;;
    *)      die "usage: ihunter-run {start|stop|status|logs|prune}" ;;
esac
