# gps-denied-nav

This package provides a ROS2-based navigation stack optimized for Jetson devices in GPS-denied environments.

## Prerequisites

- Jetson device running JetPack 6.x (L4T r36.x)
- `jetson-containers` repository installed

## Building the Image

To build the `gps-denied-nav` container, run the following command from the root of the `jetson-containers` repository:

```bash
jetson-containers build gps-denied-nav
```

This will chain the necessary dependencies (OpenCV, CUDA, ROS2, etc.) and produce a compatible image.

## Running the Container

The package includes a custom run configuration that sets up persistent shared volumes and hardware access.

### 1. Launch the Container
Run the following command to start the container:

```bash
jetson-containers run gps-denied-nav
```

**What this does:**
- Finds the most recent `gps-denied-nav` image.
- Mounts a shared volume at `~/gps-denied-nav_shared_volume` on your host to `/root/shared_volume` in the container.
- Sets the container name to `gps-denied-nav`.
- Enables `--privileged` mode and `--network host`.
- Sourcing of ROS2 and environment variables (`RMW_IMPLEMENTATION`) is handled automatically.

### 2. Re-entering the Container
Since the container is launched with `--no-rm`, it will persist after you exit. To open a new terminal in the running container, use:

```bash
docker exec -it gps-denied-nav bash
```

## Shared Volume
Any data or code placed in `~/gps-denied-nav_shared_volume` on the Jetson host will be available at `/root/shared_volume` inside the container. This is the recommended location for your ROS2 workspace and configuration files.

## Environment Variables
- `RMW_IMPLEMENTATION`: Defaulted to `rmw_zenoh_cpp`.
- `DISPLAY`: Automatically forwarded if available on the host.
- `CUDA_VISIBLE_DEVICES`: All GPUs are visible by default.
