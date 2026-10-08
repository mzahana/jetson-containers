#!/usr/bin/env bash
#
# bootstrap.sh -- a fresh Jetson to a recording GPS-denied-nav vehicle.
#
#   git clone <this fork> && cd jetson-containers
#   ./packages/gps-denied-nav/bootstrap.sh [--no-image-build]
#
# This is a DESK JOB. It needs the internet. Port of packages/ihunter/bootstrap.sh;
# keep the two in step so fixes flow both ways.
#
# What it does, in order:
#   1. checks the board is what this image was built for, and has the disk
#   2. imports the public ROS 2 workspace from gpsdnav.repos, pinned commit by commit
#   3. builds the container image (incremental; see build.sh)
#   4. builds the workspace inside the container
#   5. installs the host services, so the container comes up at boot
#
# No GitHub credential goes on this board. The vehicle package
# gps_denied_navigation_system is private and arrives from the laptop
# (`gpsdnav deploy --init`). If it is not there yet, step 4 builds the public
# packages only and says so; deploy it and re-run with --no-image-build.
#
# Every step is idempotent: re-running after a failure resumes rather than
# starting again.
#
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
JC_ROOT="$(readlink -f "$HERE/../..")"
OWNER="${SUDO_USER:-$USER}"
SHARED="${GPSDNAV_SHARED_VOLUME:-/home/$OWNER/gpsdnav_shared_volume}"
IMAGE="${GPSDNAV_IMAGE:-gpsdnav:r36.5.tegra-aarch64-cu126-22.04}"
ROS_DISTRO_NAME="${GPSDNAV_ROS_DISTRO:-humble}"
VEHICLE_PKG=gps_denied_navigation_system
# The image build needs real headroom.
MIN_BUILD_GB="${GPSDNAV_MIN_BUILD_GB:-25}"

B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; X=$'\033[0m'
step() { echo; echo "${B}==> $*${X}"; }
ok()   { echo "  ${G}ok${X}   $*"; }
warn() { echo "  ${Y}warn${X} $*"; }
die()  { echo "  ${R}fail${X} $*" >&2; exit 1; }

SKIP_BUILD=0
[ "${1:-}" = "--no-image-build" ] && SKIP_BUILD=1

# --- 1. the board ------------------------------------------------------------
step "Checking the board"
[ "$(uname -m)" = aarch64 ] || die "not an aarch64 Jetson (this is $(uname -m))"
if [ -f /etc/nv_tegra_release ]; then
    ok "$(head -1 /etc/nv_tegra_release | cut -c1-60)"
else
    warn "no /etc/nv_tegra_release -- is this really a Jetson with JetPack installed?"
fi
command -v docker >/dev/null || die "docker is not installed"
docker info >/dev/null 2>&1 || die "cannot talk to the docker daemon (add \$USER to the docker group?)"
ok "docker $(docker --version | awk '{print $3}' | tr -d ,)"

free_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
if [ "$SKIP_BUILD" = 0 ] && [ "$free_gb" -lt "$MIN_BUILD_GB" ]; then
    die "${free_gb}G free on / but the image build needs ~${MIN_BUILD_GB}G.
       Free space first, or pass --no-image-build if the image is already here."
fi
ok "${free_gb}G free on /"

python3 -c 'import yaml' 2>/dev/null \
    || die "python3-yaml is missing: sudo apt install -y python3-yaml"
ok "git + python3-yaml (vcstool is deliberately NOT required -- see import-workspace.sh)"

# --- 2. the workspace --------------------------------------------------------
step "Importing the ROS 2 workspace"
# These live OUTSIDE the container on purpose: container-local files are lost
# when the container is recreated, and `gpsdnav-container up` recreates.
#   calib      camera intrinsics and latency measurements (DEPLOYMENT_PLAN.md 10)
#   data/maps  satellite tiles for the later onboard phase
mkdir -p "$SHARED/ros2_ws/src" "$SHARED/logs" "$SHARED/bags" "$SHARED/run" \
         "$SHARED/calib" "$SHARED/data/maps"

"$HERE/import-workspace.sh" "$HERE/gpsdnav.repos" "$SHARED" \
    || warn "some repositories failed -- see above"
ok "workspace at $SHARED/ros2_ws/src ($(ls -1 "$SHARED/ros2_ws/src" 2>/dev/null | wc -l) packages)"

HAVE_VEHICLE_PKG=0
if [ -d "$SHARED/ros2_ws/src/$VEHICLE_PKG/.git" ]; then
    HAVE_VEHICLE_PKG=1
    ok "$VEHICLE_PKG present (deployed from the laptop)"
else
    warn "$VEHICLE_PKG is not on this board yet. It is private and is never
       cloned here; from the laptop run:  gpsdnav deploy --init
       The public packages are built now; re-run with --no-image-build after."
fi

# --- 3. the image ------------------------------------------------------------
if [ "$SKIP_BUILD" = 1 ]; then
    step "Skipping the image build (--no-image-build)"
    docker image inspect "$IMAGE" >/dev/null 2>&1 || die "$IMAGE is not present either"
    ok "$IMAGE already present"
else
    step "Building the container image (this is the long part)"
    # build.sh, never a bare `jetson-containers build gps-denied-nav`: that
    # computes a different image name and forces an 18-stage rebuild from scratch.
    ( cd "$HERE" && ./build.sh )
    ok "built $IMAGE"
fi

# --- 4. the workspace build --------------------------------------------------
step "Building the workspace inside the container"
# mavros_msgs first: building everything at once hits a known ordering failure.
# rosdep failures are tolerated (-r, || true) but must not mask a failed
# source/cd, hence the braces.
docker run --rm --runtime nvidia --network host --shm-size=8g \
    -v "$SHARED:/root/shared_volume" "$IMAGE" \
    bash -lc "source /opt/ros/${ROS_DISTRO_NAME}/setup.bash \
              && cd /root/shared_volume/ros2_ws \
              && { rosdep install --from-paths src --ignore-src -r -y 2>/dev/null || true; } \
              && colcon build --symlink-install --packages-up-to mavros_msgs \
              && colcon build --symlink-install"
ok "workspace built"

# --- 5. the host services ----------------------------------------------------
step "Installing the host services"
if [ ! -x "$HERE/host/install.sh" ]; then
    warn "host/install.sh is not in this checkout yet; the container will not
       start at boot until the host services are installed."
elif [ "$(id -u)" -eq 0 ]; then
    "$HERE/host/install.sh" --enable
else
    sudo "$HERE/host/install.sh" --enable
fi

step "Done"
if [ "$HAVE_VEHICLE_PKG" = 0 ]; then
    cat <<DONE

  ${B}Not finished:${X} $VEHICLE_PKG is missing, so nothing can be launched yet.
  From the laptop:

      gpsdnav deploy --init

  then on this board:

      $HERE/bootstrap.sh --no-image-build

DONE
else
    cat <<DONE

  The container starts at boot with the zenoh router supervised. Reboot once
  and confirm nothing needed a human:

      sudo reboot
      # then, from the laptop:
      gpsdnav check

DONE
fi
