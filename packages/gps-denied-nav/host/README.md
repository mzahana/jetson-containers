# Host services for the GPS-denied navigation Jetson

Port of `packages/ihunter/host/`: **the container is a service, not something
you log in and start.** Keep the two in step so fixes flow both ways.

Every long-running process runs inside a detached container owned by the Docker
daemon. Nothing is parented by an SSH session, so `tmux` is not needed and
losing the laptop or the wifi cannot take the aircraft's software down.

| File | What it is |
|---|---|
| `gpsdnav-container.sh` | create / start / stop / inspect the container. Reuses jetson-containers' `run.sh` for the Jetson hardware mounts, adding only `--detach`, `--no-rm`, `--init`, a restart policy, and `sleep infinity` as PID 1 |
| `gpsdnav-router.sh` | `rmw_zenohd` in the foreground, so systemd can supervise it |
| `gpsdnav-run.sh` | start / stop / inspect one launch inside the container (`docker exec -d`, SIGINT with a 60 s grace so bags close) |
| `gpsdnav-container.service` | brings the container up at boot |
| `gpsdnav-router.service` | keeps the router alive, and bound to the container's life |
| `drone-mode.sh` | hands the shared board to iHunter or gpsdnav |
| `install.sh` | installs the above; `--enable` also hands the board to gpsdnav |

## This board is shared with iHunter

Only one stack may be up at a time: both routers bind `tcp/0.0.0.0:7447` and
both MAVROS instances would open `/dev/ttyUSB0`. So:

- `gpsdnav-container up|start|recreate` refuses while the `ihunter` container
  is running, and `ihunter-container` refuses while `gpsdnav` is running.
- `drone-mode` is the only supported way to switch. It disables the other
  stack's units (so it stays off across reboots), stops its container, then
  enables and starts the requested stack. It refuses if the other stack has a
  launch running, unless `--force`, which stops that launch cleanly first.

```bash
drone-mode status
sudo drone-mode gpsdnav
sudo drone-mode ihunter
```

The shared volumes stay separate (`~/ihunter_shared_volume`,
`~/gpsdnav_shared_volume`); the disk is shared, so fetch bags after every session.

## Install

```bash
sudo ./install.sh            # files only; changes nothing running
sudo drone-mode gpsdnav      # when the board should boot into gpsdnav
```

Then, from anywhere: `gpsdnav-container status`.

## What still does not start automatically

Any `ros2 launch`. The container and the router are plumbing. Recordings are
started explicitly, from the laptop, through `gpsdnav-run`.
