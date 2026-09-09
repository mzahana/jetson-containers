#!/usr/bin/env bash
#
# setup-jetson.sh -- a freshly flashed Jetson to a flyable iHunter drone.
#
#   git clone -b custom_packages https://github.com/mzahana/jetson-containers.git ~/src/jetson-containers
#   ~/src/jetson-containers/packages/ihunter/setup-jetson.sh
#
# Does everything after the JetPack flash: host prerequisites, the Docker
# default-runtime configuration the CUDA build needs, a read-only deploy key for
# this board, then bootstrap.sh (workspace import, image build, workspace build,
# host services). Ends with the board starting the container at boot.
#
# Idempotent: safe to re-run, and that is how you resume after a failure.
#
# One step needs a human: you must paste this board's public key into GitHub as
# a deploy key. The script prints it and waits. Nothing else is interactive.
#
#   --no-image-build   the image is already here; skip the long part
#   --skip-key         no private repositories needed on this board
#   --check-only       verify this board's prerequisites and stop before
#                      bootstrap. Use it to audit a board without rebuilding
#                      anything, and to see what a re-run would change.
#
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"

B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; X=$'\033[0m'
step() { echo; echo "${B}==> $*${X}"; }
ok()   { echo "  ${G}ok${X}   $*"; }
warn() { echo "  ${Y}warn${X} $*"; }
die()  { echo "  ${R}fail${X} $*" >&2; exit 1; }

SKIP_KEY=0; CHECK_ONLY=0; BOOTSTRAP_ARGS=()
for a in "$@"; do
    case "$a" in
        --skip-key) SKIP_KEY=1 ;;
        --check-only) CHECK_ONLY=1 ;;
        --no-image-build) BOOTSTRAP_ARGS+=("$a") ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) die "unknown option: $a" ;;
    esac
done

[ "$(id -u)" -ne 0 ] || die "run as the normal user (nvidia), not root.
       The script uses sudo where it needs to; running the whole thing as root
       would put the workspace and the deploy key in /root."

# --- 1. the board ------------------------------------------------------------
step "Checking the board"
[ "$(uname -m)" = aarch64 ] || die "not an aarch64 Jetson (this is $(uname -m))"
if [ -f /etc/nv_tegra_release ]; then
    rel="$(head -1 /etc/nv_tegra_release | grep -oE 'R[0-9]+' | head -1)"
    ok "L4T $rel"
    [ "$rel" = "R36" ] || warn "this package is confirmed on JetPack 6 (R36) only"
else
    warn "no /etc/nv_tegra_release -- is JetPack installed?"
fi

# --- 2. host packages --------------------------------------------------------
step "Host packages"
need=()
command -v git  >/dev/null || need+=(git)
# python3-yaml, NOT python3-vcstool: vcstool is not in Ubuntu's archive, it
# comes from the ROS apt repo, and this board deliberately does not have that
# repo -- ROS lives in the container. import-workspace.sh uses git directly.
python3 -c 'import yaml' 2>/dev/null || need+=(python3-yaml)
command -v rsync >/dev/null || need+=(rsync)
if [ ${#need[@]} -gt 0 ]; then
    sudo apt-get update -qq
    # This board has been seen with a broken dpkg state, which blocks apt while
    # leaving containers untouched. Say which it is rather than failing opaquely.
    sudo apt-get install -y "${need[@]}" || die "apt failed.
       If dpkg is in a broken state: sudo dpkg --configure -a"
fi
ok "git, python3-yaml, rsync"

# --- 3. docker ---------------------------------------------------------------
step "Docker"
command -v docker >/dev/null || die "docker is not installed. Install it, then re-run."

# CUDA must be available at BUILD time, which requires nvidia to be the DEFAULT
# runtime and not merely an available one. Without this the image build dies
# partway with CUDA errors that read like a broken Dockerfile.
if docker info 2>/dev/null | grep -qi "default runtime: nvidia"; then
    ok "nvidia is the default runtime"
else
    warn "setting nvidia as the default docker runtime"
    [ -f /etc/docker/daemon.json ] && sudo cp /etc/docker/daemon.json \
        "/etc/docker/daemon.json.bak-$(date +%s)" && echo "       (old daemon.json backed up)"
    sudo tee /etc/docker/daemon.json >/dev/null <<'JSON'
{
    "runtimes": { "nvidia": { "path": "nvidia-container-runtime", "runtimeArgs": [] } },
    "default-runtime": "nvidia"
}
JSON
    sudo systemctl restart docker
    ok "default runtime set"
fi

if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    ok "added $USER to the docker group"
fi
# The group is in /etc/group but not in this shell's credentials until a new
# login. Re-exec under it rather than making the operator log out and back in.
if ! docker info >/dev/null 2>&1; then
    if [ "${IHUNTER_SG_RETRY:-0}" = 1 ]; then
        die "still cannot talk to the docker daemon. Is it running?  systemctl status docker"
    fi
    warn "re-running under the docker group"
    exec sg docker -c "IHUNTER_SG_RETRY=1 $(printf '%q ' "$0" "$@")"
fi
ok "docker daemon reachable"

# --- 4. power ----------------------------------------------------------------
step "Power mode"
if command -v nvpmodel >/dev/null; then
    sudo nvpmodel -m 0 >/dev/null 2>&1 && ok "MAX power mode" || warn "nvpmodel -m 0 failed"
else
    warn "nvpmodel not found"
fi

# --- 5. a deploy key for this board -----------------------------------------
if [ "$SKIP_KEY" = 1 ]; then
    step "Deploy key: skipped (--skip-key)"
else
    step "GitHub access for the private repositories"
    if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 \
        | grep -q "successfully authenticated"; then
        ok "this board can already authenticate to GitHub"
    else
        [ -f ~/.ssh/id_ed25519 ] || {
            ssh-keygen -t ed25519 -C "ihunter-$(hostname)" -f ~/.ssh/id_ed25519 -N "" >/dev/null
            ok "generated ~/.ssh/id_ed25519"
        }
        cat <<KEY

  ${B}This board's public key:${X}

$(sed 's/^/      /' ~/.ssh/id_ed25519.pub)

  Add it as a ${B}read-only deploy key${X} on each private repository:
      ihunter_system, mav_navigator_ros, interception_guidance
  GitHub -> the repo -> Settings -> Deploy keys -> Add deploy key.
  Leave "Allow write access" UNCHECKED.

  A deploy key is per-repository, so add it to all three. Do not use a personal
  key: this board is shared, and anyone who can log in would inherit your whole
  GitHub account.

KEY
        if [ "$CHECK_ONLY" = 1 ]; then
            warn "--check-only: not waiting for the key to be added"
        else
            read -r -p "  Press Enter once the key is added (or Ctrl-C to stop) ... " _
        fi
        if ssh -o BatchMode=yes -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            ok "GitHub authentication works"
        else
            warn "still cannot authenticate. The public repositories will import;
       the three private ones will not. Add the key and re-run this script."
        fi
    fi
fi

# --- 6. bootstrap ------------------------------------------------------------
if [ "$CHECK_ONLY" = 1 ]; then
    step "Stopping before bootstrap (--check-only)"
    ok "prerequisites verified; nothing was built"
    command -v ihunter-container >/dev/null \
        && { echo; ihunter-container status; } \
        || warn "host services are not installed yet -- re-run without --check-only"
    exit 0
fi

step "Handing over to bootstrap.sh (the long part)"
"$HERE/bootstrap.sh" "${BOOTSTRAP_ARGS[@]}"

cat <<DONE

${B}Reboot to prove it comes up on its own:${X}

    sudo reboot
    # then, ~40 s later:
    ihunter-container status        # both lines must say running

Then set up the laptop -- ihunter_system/scripts/install-laptop.sh -- and drive
this board from there. Nothing on this Jetson needs to be logged into again.

DONE
