#!/usr/bin/env bash
#
# drone-mode -- which stack owns this shared Jetson: iHunter or gpsdnav.
#
#   drone-mode status                   which stack is enabled and running
#   sudo drone-mode gpsdnav [--force]   hand the board to gpsdnav
#   sudo drone-mode ihunter [--force]   hand the board to iHunter
#
# Only one stack may be up at a time: both zenoh routers bind tcp/0.0.0.0:7447
# and both MAVROS instances would open /dev/ttyUSB0 (DEPLOYMENT_PLAN.md 7).
# Switching disables the other stack's units (so it stays off across reboots),
# stops its container, then enables and starts the requested stack.
#
# A launch running in the other stack (a recording, or a flight) is never
# interrupted silently: the switch refuses unless --force is given, and with
# --force the launch is stopped through <stack>-run first, so bags close cleanly.
#
set -euo pipefail

STACKS=(ihunter gpsdnav)
UNITS=/etc/systemd/system
BIN=/usr/local/bin

die() { echo "drone-mode: $*" >&2; exit 1; }
say() { echo "### $*"; }

installed()    { [ -f "$UNITS/$1-container.service" ]; }
running()      { [ -n "$(docker ps -q -f "name=^/$1$")" ]; }
# is-enabled exits non-zero for "disabled" too, so judge by its output.
unit_state()   { local s; s="$(systemctl is-enabled "$1" 2>/dev/null || true)"; echo "${s:-not-installed}"; }

# A launch is active when <stack>-run status lists one.
launch_active() {
    [ -x "$BIN/$1-run" ] && running "$1" || return 1
    ! "$BIN/$1-run" status 2>/dev/null | grep -q '^run: *nothing running'
}

status() {
    local s owner=""
    for s in "${STACKS[@]}"; do
        printf '%-8s units: container=%s router=%s   container: %s\n' "$s" \
            "$(unit_state "$s-container.service")" "$(unit_state "$s-router.service")" \
            "$(running "$s" && echo running || echo stopped)"
        running "$s" && owner+="$s "
    done
    case "$(echo $owner | wc -w)" in
        0) echo "board:   no stack running" ;;
        1) echo "board:   owned by ${owner% }" ;;
        *) echo "board:   CONFLICT -- more than one stack running: $owner" ;;
    esac
}

switch_to() {
    local want="$1" force="$2" s
    [ "$(id -u)" -eq 0 ] || die "run with sudo"
    installed "$want" || die "$want host services are not installed (packages/<pkg>/host/install.sh)"

    for s in "${STACKS[@]}"; do
        [ "$s" = "$want" ] && continue
        if launch_active "$s"; then
            [ "$force" = 1 ] || die "$s has a launch running (recording or flying):
$("$BIN/$s-run" status 2>/dev/null | sed 's/^/       /')
       Stop it first ($s-run stop), or pass --force to stop it cleanly here."
            say "stopping the $s launch cleanly"
            "$BIN/$s-run" stop
        fi
        if installed "$s"; then
            say "disabling $s"
            systemctl disable --now "$s-router.service" "$s-container.service" 2>/dev/null || true
        fi
        # A container started by hand is not stopped by its unit. `docker stop`
        # also marks it stopped for the unless-stopped policy, so it stays down
        # across a reboot.
        if running "$s"; then
            say "stopping the $s container"
            docker stop "$s" >/dev/null
        fi
    done

    say "enabling $want"
    systemctl enable --now "$want-container.service" "$want-router.service"
    echo
    status
}

FORCE=0; MODE=""
for a in "$@"; do
    case "$a" in
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) [ -z "$MODE" ] || die "one mode at a time"; MODE="$a" ;;
    esac
done

case "${MODE:-status}" in
    status) status ;;
    ihunter|gpsdnav) switch_to "$MODE" "$FORCE" ;;
    *) die "usage: drone-mode {status|ihunter|gpsdnav} [--force]" ;;
esac
