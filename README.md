# Extended Setup for PX4 Integration
This section is added to provide instructions regarding the extra steps required to setup docker images on Jetson Nano that can work with PX4 autopilot hardware e.g. Pixhawk.

## Added files
* `Dockerfile.ros.melodic.px4`: Adds MAVROS and some extra confgiurations to prepare the docker image to work with PX4-supported autopilot hardware
* `scripts/docker_build_ros_px4.sh`: Builds `Dockerfile.ros.melodic.px4`
* `scripts/docker_run_px4.sh` provides a convenience script to run docker containers from `Dockerfile.ros.melodic.px4`
* `scripts/setup_jetson.sh`: A convenience script to install everything on a jetson nano.
* `scripts/installRealsenseUdev.md` Installs the required udev rules for Intel D435 depth cameras. **This is required before using te camera inside a docker container**.

## Setup instructions
* Clone this package to your `~/src/` folder
    ```bash
    cd ~/src
    git clone https://github.com/mzahana/jetson-containers.git
    ```
* Execute the setup script, `./setup_jetson.sh`
```bash
cd ~/src/jetson-containers/scripts/
./setup_jetson.sh
```
* Reboot your Jetson after the setup is completed
* The setup script creates an alias in the `$HOME/.bashrc` file. The alias is named `px4_container`. You can execute this alias in a terminal and you will be logged into the container with username (and password) `riot`.
* Setup instruction for **Jetson Nano 4G shield** can be found [here ](https://github.com/phillipdavidstearns/simcom_wwan-setup)
    * Follow the instructions in the above page to setup the 4G shield
    * Before executing `sudo dhclient -1 -v wwan0` to allocate an IP, you may need to set the APN as described in [this issue](https://github.com/phillipdavidstearns/simcom_wwan-setup/issues/1). Basically, you will need to send the AT command `AT+CGDCONT=1,"IP","inet.bell.ca"`. `inet.bell.ca` is the APN. Make sure that you find the right APN for your 4G service provider.

## Communication with PX4
The docker container has MAVROS package which can be used to communicate with PX4 as follows
* Connect the serial port `/dev/ttyTHS1` (pins 6-GND, 8-TX, 10-RX), [reference](https://www.jetsonhacks.com/nvidia-jetson-nano-j41-header-pinout/), to Pixhawk serial port, usually `TELEM2`
* Configure the serial port on Pixhawk, [reference](https://docs.px4.io/master/en/companion_computer/pixhawk_companion.html#pixhawk-setup). Use Baud rate of `500000` as `921600` baudrate is not supported in the default Jetson kernel. **On Xavier NX, you can use 921600 baudrate**
* In the docker container terminal, launch a MAVROS node to establish the communication
    ```bash
    roslaunch mavros px4.launch fcu_url:=/dev/ttyTHS1:500000
    ```


**NOTE: The following sections are from the original repo**

# Machine Learning Containers for Jetson and JetPack

Hosted on [NVIDIA GPU Cloud](https://ngc.nvidia.com/catalog/containers?orderBy=modifiedDESC&query=L4T&quickFilter=containers&filters=) (NGC) are the following Docker container images for machine learning on Jetson:

* [`l4t-ml`](https://ngc.nvidia.com/catalog/containers/nvidia:l4t-ml)
* [`l4t-pytorch`](https://ngc.nvidia.com/catalog/containers/nvidia:l4t-pytorch)
* [`l4t-tensorflow`](https://ngc.nvidia.com/catalog/containers/nvidia:l4t-tensorflow)

Dockerfiles are also provided for the following containers, which can be built for JetPack 4.4 or newer:

* ROS Melodic (`ros:melodic-ros-base-l4t-r32.4.4`)
* ROS Noetic (`ros:noetic-ros-base-l4t-r32.4.4`)
* ROS2 Eloquent (`ros:eloquent-ros-base-l4t-r32.4.4`)
* ROS2 Foxy (`ros:foxy-ros-base-l4t-r32.4.4`)

Below are the instructions to build and test the containers using the included Dockerfiles.

## Docker Default Runtime

To enable access to the CUDA compiler (nvcc) during `docker build` operations, add `"default-runtime": "nvidia"` to your `/etc/docker/daemon.json` configuration file before attempting to build the containers:

``` json
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

You will then want to restart the Docker service or reboot your system before proceeding.

## Building the Containers

To rebuild the containers from a Jetson device running [JetPack 4.4](https://developer.nvidia.com/embedded/jetpack) or newer, first clone this repo:

``` bash
$ git clone https://github.com/dusty-nv/jetson-containers
$ cd jetson-containers
```

### ML Containers

To build the ML containers (`l4t-pytorch`, `l4t-tensorflow`, `l4t-ml`), use [`scripts/docker_build_ml.sh`](scripts/docker_build_ml.sh) - along with an optional argument of which container(s) to build: 

``` bash
$ ./scripts/docker_build_ml.sh all        # build all: l4t-pytorch, l4t-tensorflow, and l4t-ml
$ ./scripts/docker_build_ml.sh pytorch    # build only l4t-pytorch
$ ./scripts/docker_build_ml.sh tensorflow # build only l4t-tensorflow
```

> You have to build `l4t-pytorch` and `l4t-tensorflow` to build `l4t-ml`, because it uses those base containers in the multi-stage build.

Note that the TensorFlow and PyTorch pip wheel installers for aarch64 are automatically downloaded in the Dockerfiles from the [Jetson Zoo](https://elinux.org/Jetson_Zoo).

### ROS Containers

To build the ROS containers, use [`scripts/docker_build_ros.sh`](scripts/docker_build_ros.sh) with the name of the ROS distro to build:

``` bash
$ ./scripts/docker_build_ros.sh all       # build all: melodic, noetic, eloquent, foxy
$ ./scripts/docker_build_ros.sh melodic   # build only melodic
$ ./scripts/docker_build_ros.sh noetic    # build only noetic
$ ./scripts/docker_build_ros.sh eloquent  # build only eloquent
$ ./scripts/docker_build_ros.sh foxy      # build only foxy
```

Note that ROS Noetic and ROS2 Foxy are built from source for Ubuntu 18.04, while ROS Melodic and ROS2 Eloquent are installed from Debian packages into the containers.

## Testing the Containers

To run a series of automated tests on the packages installed in the containers, run the following from your `jetson-containers` directory:

``` bash
$ ./scripts/docker_test_ml.sh all        # test all: l4t-pytorch, l4t-tensorflow, and l4t-ml
$ ./scripts/docker_test_ml.sh pytorch    # test only l4t-pytorch
$ ./scripts/docker_test_ml.sh tensorflow # test only l4t-tensorflow
```

To test ROS:

``` bash
$ ./scripts/docker_test_ros.sh all       # build all: melodic, noetic, eloquent, foxy
$ ./scripts/docker_test_ros.sh melodic   # build only melodic
$ ./scripts/docker_test_ros.sh noetic    # build only noetic
$ ./scripts/docker_test_ros.sh eloquent  # build only eloquent
$ ./scripts/docker_test_ros.sh foxy      # build only foxy
```

