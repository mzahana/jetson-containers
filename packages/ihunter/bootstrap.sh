#!/usr/bin/env bash
#
# bootstrap.sh -- a fresh Jetson to a flyable iHunter vehicle.
#
#   git clone <this fork> && cd jetson-containers
#   ./packages/ihunter/bootstrap.sh
#
# This is a DESK JOB. It needs the internet and takes hours (the image build
# dominates). Nothing in the field path uses it -- in the field the board boots
# into a working stack on its own, which is the whole point of the host
# services this installs.
#
# What it does, in order:
#   1. checks the board is what this image was built for, and has the disk
#   2. imports the ROS 2 workspace from ihunter.repos, pinned commit by commit
#   3. builds the container image (incremental; see build.sh)
#   4. builds the workspace inside the container
#   5. installs the host services, so the container comes up at boot
#
# Every step is idempotent: re-running after a failure resumes rather than
# starting again.
#
set -euo pipefail

HERE="$(dirname "$(readlink -f "$0")")"
JC_ROOT="$(readlink -f "$HERE/../..")"
OWNER="${SUDO_USER:-$USER}"
SHARED="${IHUNTER_SHARED_VOLUME:-/home/$OWNER/ihunter_shared_volume}"
IMAGE="${IHUNTER_IMAGE:-ihunter_container:r36.5.tegra-aarch64-cu126-22.04-ihunter}"
ROS_DISTRO_NAME="${IHUNTER_ROS_DISTRO:-humble}"
# The image build needs real headroom; the 18-stage chain cannot finish without it.
MIN_BUILD_GB="${IHUNTER_MIN_BUILD_GB:-25}"

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

command -v vcs >/dev/null || die "vcstool is missing: sudo apt install python3-vcstool"
ok "vcstool present"

# --- 2. the workspace --------------------------------------------------------
step "Importing the ROS 2 workspace"
mkdir -p "$SHARED/ros2_ws/src" "$SHARED/logs" "$SHARED/bags" "$SHARED/reports" \
         "$SHARED/mav_controllers_config" "$SHARED/run"

# Private repositories need a key. Say so plainly rather than letting vcs fail
# fifteen times with the same message.
if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 \
     | grep -q "successfully authenticated"; then
    warn "no working SSH key for github.com on this board."
    echo "       ihunter_system, mav_navigator_ros and interception_guidance are"
    echo "       private and will fail to import. Install a READ-ONLY deploy key"
    echo "       for this board (never a personal key, never a key copied from"
    echo "       another board), then re-run. Everything else will import now."
fi

( cd "$SHARED" && vcs import --input "$HERE/ihunter.repos" --workers 4 ) \
    || warn "some repositories failed to import -- see above (private ones need the key)"
missing=$(cd "$SHARED" && vcs validate --input "$HERE/ihunter.repos" 2>&1 | grep -c "does not exist" || true)
ok "workspace at $SHARED/ros2_ws/src ($(ls -1 "$SHARED/ros2_ws/src" | wc -l) packages)"

# --- 3. the image ------------------------------------------------------------
if [ "$SKIP_BUILD" = 1 ]; then
    step "Skipping the image build (--no-image-build)"
    docker image inspect "$IMAGE" >/dev/null 2>&1 || die "$IMAGE is not present either"
    ok "$IMAGE already present"
else
    step "Building the container image (this is the long part)"
    # build.sh, never a bare `jetson-containers build ihunter`: that computes a
    # different image name and forces an 18-stage rebuild from scratch.
    ( cd "$HERE" && ./build.sh )
    ok "built $IMAGE"
fi

# --- 4. the workspace build --------------------------------------------------
step "Building the workspace inside the container"
docker run --rm --runtime nvidia --network host --shm-size=8g \
    -v "$SHARED:/root/shared_volume" "$IMAGE" \
    bash -lc "source /opt/ros/${ROS_DISTRO_NAME}/setup.bash \
              && cd /root/shared_volume/ros2_ws \
              && rosdep install --from-paths src --ignore-src -r -y 2>/dev/null || true \
              && colcon build --symlink-install --packages-up-to mavros_msgs \
              && colcon build --symlink-install"
ok "workspace built"

# --- 5. the host services ----------------------------------------------------
step "Installing the host services"
if [ "$(id -u)" -eq 0 ]; then
    "$HERE/host/install.sh" --enable
else
    sudo "$HERE/host/install.sh" --enable
fi

step "Done"
cat <<DONE

  The container now starts at boot with the zenoh router supervised. Reboot
  once and confirm nothing needed a human:

      sudo reboot
      # then, from the laptop:
      ihunter check

  Before this airframe flies:

    - ${B}max_thrust is per airframe.${X} Every controller gain scales with it, so
      the gains that came with the repo are only valid for the aircraft they
      were measured on. Fly hover_test, pull the ulog, run geo-tuner-hover, and
      write the result into ihunter_system/config/geometric_controller/.
      Until then this vehicle is not tuned, whatever the config says.

    - Set the ${B}PX4 geofence${X} for the actual flying area. During an engagement
      the flight state machine is not running, so the geofence is the boundary.

DONE
