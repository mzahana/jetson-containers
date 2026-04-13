# WARNING: JetPack 6 Only!

> [!CAUTION]
> This package and its build scripts are **only confirmed to work on JetPack 6** (L4T r36.x). Do not attempt to use this on JetPack 5 or below.

## System Setup

Follow these steps on your Jetson device before building the container.

### 1. Install `jetson-containers`
If you haven't already, clone the specific branch and run the installer:
```bash
cd $HOME
mkdir -p src && cd src
git clone -b feat/add-gps-denied-nav git@github.com:mzahana/jetson-containers.git
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
~/gps-denied-nav_shared_volume/
└── ros2_ws/
    └── src/
```

Create it manually using:
```bash
mkdir -p ~/gps-denied-nav_shared_volume/ros2_ws/src
```

## Building the Image

After the restart, run the following command to build the base image:

```bash
# (NEW---still testing!!!)
jetson-containers build --name=gpsd gps-denied-nav --skip-tests all
```

This will chain the necessary dependencies (OpenCV, CUDA, ROS2, etc.) and produce a compatible image.

## Running the Container

The package includes a custom run configuration that sets up persistent shared volumes and hardware access.

### 1. Launch or Re-enter the Container
Run the following command to start a new container or get back into an existing one:

```bash
jetson-containers run gps-denied-nav
```

**What this does:**
- **First time**: Creates a new container with persistent shared volumes and hardware access.
- **Subsequent times**: If the container is stopped, it restarts it. If it is already running, it attaches a new terminal.
- **Unified Workflow**: You only ever need this one command to manage your development environment.

**Configuration features:**
- Mounts a shared volume at `~/gps-denied-nav_shared_volume` on your host to `/root/shared_volume` in the container.
- Sets the container name to `gps-denied-nav`.
- Enables `--privileged` mode and `--network host`.
- Sourcing of ROS2 and environment variables (`RMW_IMPLEMENTATION`) is handled automatically.

### 2. Manual Re-entry (Optional)
If you specifically want to open an additional parallel terminal in the running container, you can still use:

```bash
docker exec -it gps-denied-nav bash
```

## MAVROS Installation (Post-Build)

> [!IMPORTANT]
> The `install_mavros.sh` script needs to be run **once** inside the container after a fresh build to set up the MAVROS workspace.
0. Copy the `install_mavros.sh` script to the shared volume:
   ```bash
   cp install_mavros.sh ~/gps-denied-nav_shared_volume/
   ```
1. Enter the container: `jetson-containers run gps-denied-nav`
2. Run the installation script:
   ```bash
   bash /root/shared_volume/install_mavros.sh
   ```
   *Note: This script will clone and build MAVROS inside your shared ROS2 workspace.*

## Shared Volume
Any data or code placed in `~/gps-denied-nav_shared_volume` on the Jetson host will be available at `/root/shared_volume` inside the container. This is the recommended location for your ROS2 workspace and configuration files.

## Environment Variables
- `RMW_IMPLEMENTATION`: Defaulted to `rmw_zenoh_cpp`.
- `DISPLAY`: Automatically forwarded if available on the host.
- `CUDA_VISIBLE_DEVICES`: All GPUs are visible by default.
