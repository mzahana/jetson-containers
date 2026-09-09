# WARNING: JetPack 6 Only!

> [!CAUTION]
> This package and its build scripts are **only confirmed to work on JetPack 6** (L4T r36.x). Do not attempt to use this on JetPack 5 or below.

## Setting up a board: read this first

Everything below `System Setup` is the manual procedure, kept because it explains
what each piece is for. **On a fresh board you do not need to follow it by hand:**

```bash
git clone -b custom_packages git@github.com:mzahana/jetson-containers.git
cd jetson-containers
./packages/ihunter/bootstrap.sh
sudo reboot
```

`bootstrap.sh` checks the board, imports the ROS 2 workspace from `ihunter.repos`
(every package pinned to a commit), builds the image, builds the workspace, and
installs the host services. It is a **desk job**: it needs the internet and takes
hours. Steps 2 and 3 of `System Setup` (the Docker default runtime, and the
docker group) still have to be done once by hand before it will work.

After the reboot the board is a flyable vehicle with nothing running that can
command it, and the laptop drives it from there (`ihunter check`).

| File | What it is |
|---|---|
| `bootstrap.sh` | fresh Jetson to flyable vehicle, idempotent |
| `ihunter.repos` | the ROS 2 workspace, every package pinned to a commit |
| `host/` | the host services: container at boot, supervised zenoh router, and `ihunter-run` for starting a flight |
| `build.sh` | incremental image build. Never a bare `jetson-containers build ihunter` |
| `clone_ihunter_ros_pkgs.sh` | **superseded** by `ihunter.repos`; kept only as a pointer |

### The host services

The container is a **service**, not something you log into and start:

```bash
ihunter-container status     # container, router, image, disk -- one line each
ihunter-run status           # what flight is running, its log, its bag
```

Both start at boot. No `ros2 launch` ever does -- the container and the router are
plumbing, but a launch can command the aircraft, so starting one is always a
deliberate act by a person, from the laptop.

Install or update them by hand with `sudo ./host/install.sh --enable`; see
`host/README.md` for why each choice was made, including the four silent failure
modes the reboot tests found.

### Private repositories

`ihunter_system`, `mav_navigator_ros` and `interception_guidance` are private and
use SSH URLs in `ihunter.repos`. A board needs a **read-only deploy key of its
own** to import them -- never a personal key, and never one copied from another
board. The image is built from public dependencies only and the ROS workspace is
bind-mounted rather than baked, so no credential ever enters a Docker layer.

In the field there is no internet: deploy with `git bundle` + `scp`, which needs
no credentials at all.

---

## System Setup

Follow these steps on your Jetson device before building the container.

### 1. Install `jetson-containers`
If you haven't already, clone the specific branch and run the installer:
```bash
cd $HOME
mkdir -p src && cd src
git clone -b feat/add-ihunter git@github.com:mzahana/jetson-containers.git
bash jetson-containers/install.sh
```

### 2. Configure Docker Default Runtime
Replace the contents of `/etc/docker/daemon.json` with the following to make `nvidia` the default runtime. This is required for CUDA acceleration during Docker builds.
```json
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    },
    "default-runtime": "nvidia"
}
```
*Reference: [Docker Default Runtime Setup](https://github.com/dusty-nv/jetson-containers/blob/master/docs/setup.md#docker-default-runtime)*

### 3. Permissions & Power Mode
Add your user to the `docker` group and set the power mode to MAX:
```bash
sudo usermod -aG docker $USER
sudo nvpmodel -m 0  # Set to MAX mode (Orin/Xavier)
```

**Restart your Jetson** before proceeding to ensure all changes take effect.

## Recommended Directory Structure

The build and run scripts assume a shared volume for your ROS2 workspace. It is highly recommended to create the following structure on your **host** machine before running the container:

```text
~/ihunter_shared_volume/
└── ros2_ws/
    └── src/
```

Create it manually using:
```bash
mkdir -p ~/ihunter_shared_volume/ros2_ws/src
```

## Building the Image

> [!WARNING]
> **Do not run a bare `jetson-containers build ihunter`.** Without `--name`,
> the tool computes the image name from the last package (`ihunter`, not
> `ihunter_container`), so it can't find the existing intermediate images and
> rebuilds the **entire 18-stage chain from scratch** under the wrong name.
> That takes hours and needs disk this device does not have to spare.

### Everyday case: you only changed `ihunter/Dockerfile`

Use the wrapper script, which always builds under the right name and only
rebuilds the `ihunter` layer on top of the existing chain:

```bash
./build.sh              # incremental build (only the ihunter layer)
./build.sh --simulate   # dry run first — confirm it prints exactly ONE
                         # "docker buildx build" before running for real
```

This is equivalent to:
```bash
jetson-containers build --name ihunter_container --start-from ihunter --skip-tests all ihunter
```

### Full chain rebuild (only with disk headroom — check `df -h /` first)

```bash
./build.sh --full
# equivalent to:
# jetson-containers build --name ihunter_container --skip-tests all ihunter
```

## Running the Container

> [!IMPORTANT]
> **On a vehicle, do not use `jetson-containers run ihunter` for bring-up.** The
> container is a systemd service that starts at boot (`host/`), and two things
> make the manual command wrong there: it needs the internet (its autotag step
> contacts a registry, so it fails in the field), and it creates a container
> that no restart policy owns. Use `ihunter-container up` / `status`, or just
> power the board on. `jetson-containers run ihunter` remains the right command
> on a **development** board where you want an interactive container.
>
> For a shell inside the running container: `ihunter-container shell`.

The package includes a custom run configuration that sets up persistent shared volumes and hardware access.

### 1. Launch or Re-enter the Container
Run the following command to start a new container or get back into an existing one:

```bash
jetson-containers run ihunter
```

**What this does:**
- **First time**: Creates a new container with persistent shared volumes and hardware access.
- **Subsequent times**: If the container is stopped, it restarts it. If it is already running, it attaches a new terminal.
- **Unified Workflow**: You only ever need this one command to manage your development environment.

**Configuration features:**
- Mounts a shared volume at `~/ihunter_shared_volume` on your host to `/root/shared_volume` in the container.
- Sets the container name to `ihunter`.
- Enables `--privileged` mode and `--network host`.
- Sourcing of ROS2 and environment variables (`RMW_IMPLEMENTATION`) is handled automatically.

### 2. Manual Re-entry (Optional)
If you specifically want to open an additional parallel terminal in the running container, you can still use:

```bash
docker exec -it ihunter bash
```

## ROS2 Packages Installation (Post-Build)

> [!IMPORTANT]
> The `clone_ihunter_ros_pkgs.sh` script needs to be run **once** inside the container after a fresh build to clone and build all required ROS2 packages into the shared workspace.

The script clones and builds the following packages (all on the `ros2_humble` branch):

- **MAVROS** — `mavros` + `mavlink` (built via colcon)
- **d2dtracker_drone_detector** — drone detection
- **multi_target_kf** — multi-target Kalman filter
- **custom_trajectory_msgs** — custom ROS2 message definitions
- **trajectory_prediction** — constant-velocity and Bezier-based trajectory prediction
- **drone_path_predictor_ros** — GRU-based trajectory prediction
- **trajectory_generation** — MPC-based trajectory generation
- **mav_controllers_ros** — MAV controllers

**Steps:**

0. Copy the script to the shared volume:
   ```bash
   cp clone_ihunter_ros_pkgs.sh ~/ihunter_shared_volume/
   ```
1. Enter the container: `jetson-containers run ihunter`
2. Run the script:
   ```bash
   bash /root/shared_volume/clone_ihunter_ros_pkgs.sh
   ```
   *Note: This script will clone all packages and build MAVROS inside your shared ROS2 workspace.*

## Shared Volume
Any data or code placed in `~/ihunter_shared_volume` on the Jetson host will be available at `/root/shared_volume` inside the container. This is the recommended location for your ROS2 workspace and configuration files.

## Environment Variables
- `RMW_IMPLEMENTATION`: Defaulted to `rmw_zenoh_cpp`.
- `DISPLAY`: Automatically forwarded if available on the host.
- `CUDA_VISIBLE_DEVICES`: All GPUs are visible by default.
