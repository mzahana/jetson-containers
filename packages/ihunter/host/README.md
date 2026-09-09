# Host services for the iHunter Jetson

Phase F0 of the field operations plan: **the container is a service, not
something you log in and start.**

Every long-running flight process runs inside a detached container owned by the
Docker daemon. Nothing is parented by an SSH session, so `tmux` is not needed and
losing the laptop or the wifi cannot take the aircraft's software down.

| File | What it is |
|---|---|
| `ihunter-container.sh` | create / start / stop / inspect the container. Reuses jetson-containers' `run.sh` for the Jetson hardware mounts, adding only `--detach`, `--no-rm`, a restart policy, and `sleep infinity` as PID 1 |
| `ihunter-router.sh` | `rmw_zenohd` in the foreground, so systemd can supervise it |
| `ihunter-container.service` | brings the container up at boot |
| `ihunter-router.service` | keeps the router alive, and bound to the container's life |
| `install.sh` | installs the above; `--enable` also turns on boot start |

## Install

```bash
sudo ./install.sh --enable
```

Then, from anywhere:

```bash
ihunter-container status
```

## Why these particular choices

- **`sleep infinity` as the container's main process.** The container's life is
  not tied to any one job, so a launch can be started, stopped and restarted
  inside it without the container disappearing underneath.
- **Not `jetson-containers run ihunter`.** That path autotags against
  `registry-1.docker.io` and therefore fails with no internet — which is exactly
  the field condition. This names the image explicitly and touches no registry.
- **Not a hand-written `docker run`.** The Jetson hardware mounts (tegra libs,
  multimedia API, V4L2, I2C, argus socket) are easy to get subtly wrong, and the
  symptom is a camera or CUDA fault on the flight line. `run.sh` already has
  them right.
- **The router is supervised.** Without `rmw_zenohd`, `rmw_zenoh_cpp` discovery
  fails *silently*: nodes run, topics exist, the ground station sees nothing.
  A failure that quiet must not depend on someone remembering a command.
- **Install and enable are separate.** Putting files on a vehicle and changing
  what it does on power-up are different decisions.

## What still does not start automatically

Any `ros2 launch`. The container and the router are plumbing; a launch can
command the aircraft. Launches are started explicitly, from the laptop, by
`ihunter fly` (phase F3).
