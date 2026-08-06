#---
# name: ihunter
# depends: [opencv, cudastack, torchvision, gstreamer]
# requires: '>=36'
# config: config.py
#---
#  [opencv, cudastack, torchvision, onnxruntime]
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG ROS_DISTRO

# Set non-interactive installation mode
ENV DEBIAN_FRONTEND=noninteractive

# Avoid setup.py and easy_install deprecation warnings caused by colcon and setuptools
# https://github.com/colcon/colcon-core/issues/454
ENV PYTHONWARNINGS=ignore:::setuptools.command.install,ignore:::setuptools.command.easy_install,ignore:::pkg_resources
RUN echo "Warning: Using the PYTHONWARNINGS environment variable to silence setup.py and easy_install deprecation warnings caused by colcon"

# Setup locale
RUN apt update && apt install -y locales \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8

# Install necessary packages for ROS2
RUN apt update && apt install -y \
    software-properties-common \
    curl \
    && add-apt-repository universe

# Add ROS2 repository
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" | tee /etc/apt/sources.list.d/ros2.list > /dev/null

# Install ROS2 Desktop (continue on error if OpenCV packages fail)
RUN apt update && \
    apt install -y --no-install-recommends ros-${ROS_DISTRO}-desktop

# Install additional required packages
RUN apt update && apt install -y \
    git \
    libbullet-dev \
    libpython3-dev \
    python3-colcon-common-extensions \
    python3-flake8 \
    python3-pip \
    python3-pytest-cov \
    python3-rosdep \
    python3-setuptools \
    python3-vcstool \
    python3-rosinstall-generator \
    libasio-dev \
    libtinyxml2-dev \
    libcunit1-dev

# Install additional ROS2 packages 
RUN apt install -y --no-install-recommends \
    ros-${ROS_DISTRO}-launch-xml \
    ros-${ROS_DISTRO}-launch-yaml \
    ros-${ROS_DISTRO}-launch-testing \
    ros-${ROS_DISTRO}-launch-testing-ament-cmake \
    ros-${ROS_DISTRO}-demo-nodes-cpp \
    ros-${ROS_DISTRO}-demo-nodes-py \
    ros-${ROS_DISTRO}-example-interfaces \
    ros-${ROS_DISTRO}-camera-calibration-parsers \
    ros-${ROS_DISTRO}-camera-info-manager \
    ros-${ROS_DISTRO}-cv-bridge \
    ros-${ROS_DISTRO}-v4l2-camera \
    ros-${ROS_DISTRO}-vision-opencv \
    ros-${ROS_DISTRO}-vision-msgs \
    ros-${ROS_DISTRO}-image-geometry \
    ros-${ROS_DISTRO}-image-pipeline \
    ros-${ROS_DISTRO}-image-transport \
    ros-${ROS_DISTRO}-compressed-image-transport \
    ros-${ROS_DISTRO}-compressed-depth-image-transport \
    ros-${ROS_DISTRO}-rosbag2-storage-mcap \
    ros-${ROS_DISTRO}-topic-tools \
    ros-${ROS_DISTRO}-rmw-zenoh-cpp

# Make sure python3 is available as python
RUN apt install -y python-is-python3

# Initialize rosdep
RUN rosdep init || echo "rosdep already initialized" && rosdep update

# Install linux packages
RUN apt update \
    && apt install --no-install-recommends -y zip curl htop libgl1 libglib2.0-0 libusb-1.0-0 usbutils

# Install pip packages manually for TensorRT compatibility https://github.com/NVIDIA/TensorRT/issues/2567
RUN python3 -m pip install --upgrade pip wheel

# Install onnxslim==0.1.34. Needed in "yolo export"
RUN pip install "onnxslim==0.1.34"
RUN pip3 install transforms3d
RUN pip3 install numpy scipy rasterio pyproj pandas matplotlib
# Pin NumPy <2 so ROS Humble cv_bridge (compiled against NumPy 1.x) does not hit
# the _ARRAY_API ABI mismatch error at import time.
RUN pip3 install "numpy==1.26.4"
#
# MAVROS dependencies
#
# Original apt install (requires ports.ubuntu.com — blocked on this network):
# RUN apt update && \
#     apt install -y \
#         python3-vcstool \
#         python3-rosinstall-generator \
#         python3-osrf-pycommon \
#         geographiclib-tools \
#         libgeographic-dev \
#         libasio-dev \
#         libgoogle-glog-dev \
#         ros-${ROS_DISTRO}-eigen-stl-containers \
#         ros-${ROS_DISTRO}-diagnostic-updater \
#         ros-${ROS_DISTRO}-geographic-msgs \
#     && apt-get clean autoclean \
#     && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*

# Install packages available from reachable repos (ROS apt server)
RUN apt update && \
    apt install -y \
        python3-vcstool \
        python3-rosinstall-generator \
        python3-osrf-pycommon \
        libasio-dev \
        ros-${ROS_DISTRO}-eigen-stl-containers \
        ros-${ROS_DISTRO}-diagnostic-updater \
        ros-${ROS_DISTRO}-geographic-msgs \
        python3-click \
        python3-colorama \
        python3-future \
    && apt-get clean autoclean \
    && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*

# Build gflags from source (ports.ubuntu.com blocked on this network)
RUN cd /tmp && \
    git clone -b v2.2.2 --depth 1 https://github.com/gflags/gflags.git && \
    cd gflags && mkdir build && cd build && \
    cmake -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && make install && \
    ldconfig && \
    cd / && rm -rf /tmp/gflags

# Build glog from source (ports.ubuntu.com blocked on this network)
RUN cd /tmp && \
    git clone -b v0.6.0 --depth 1 https://github.com/google/glog.git && \
    cd glog && mkdir build && cd build && \
    cmake -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && make install && \
    ldconfig && \
    cd / && rm -rf /tmp/glog

# Build GeographicLib from source (ports.ubuntu.com blocked on this network)
RUN cd /tmp && \
    git clone -b v2.3 --depth 1 https://github.com/geographiclib/geographiclib.git && \
    cd geographiclib && mkdir build && cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make -j$(nproc) && make install && \
    ldconfig && \
    cd / && rm -rf /tmp/geographiclib
RUN  geographiclib-get-geoids egm96-5 && \
    geographiclib-get-gravity egm96 && \
    geographiclib-get-magnetic emm2015
RUN pip3 install catkin_pkg pyyaml lxml
RUN pip3 install empy==3.3.4


# Set up environment variables
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ~/.bashrc
ENV ROS_ROOT=/opt/ros/${ROS_DISTRO}
ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp
ENV PYTHONPATH="/opt/venv/lib/python3.10/site-packages:/usr/lib/python3/dist-packages:${PYTHONPATH}"

# Enable colored terminal
ENV TERM=xterm-256color
ENV FORCE_COLOR=1
RUN echo "export PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '" >> ~/.bashrc && \
    echo "alias ls='ls --color=auto'" >> ~/.bashrc && \
    echo "alias grep='grep --color=auto'" >> ~/.bashrc

CMD ["/bin/bash"]

# Install SIYI SDK dependencies (avoiding opencv-python to use jetson-containers opencv)
RUN pip3 install "structlog>=24.0" "pyserial-asyncio>=0.6" "typing-extensions>=4.10"

# Install optional SIYI SDK dependencies and Web UI dependencies
# PyGObject is provided by python3-gi which is installed by the gstreamer package in jetson-containers
RUN pip3 install "aiortsp>=1.2" "av>=12.0" "fastapi>=0.110" "uvicorn[standard]>=0.29" "pydantic>=2.7"



#
# Install osqp and osqpEigen. Needed for MPC and quadratic optimization
#
RUN cd / && \
    git clone --recursive https://github.com/osqp/osqp.git && \
    cd /osqp && git checkout 25b6b39 && \
    git submodule update --recursive && \
    cd /osqp && \
    mkdir build && cd build && \
    cmake -G "Unix Makefiles" .. && \
    cmake --build . && \
    cmake --build . --target install
RUN cd / && git clone https://github.com/robotology/osqp-eigen.git && \
    cd /osqp-eigen && git checkout v0.8.0 && \
    cd /osqp-eigen && \
    mkdir build && mkdir install && \
    cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release ../ && \
    make && make install
ENV LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Final NumPy pin: defeat any transitive upgrade pulled in by later pip installs.
RUN pip3 install --force-reinstall --no-deps "numpy==1.26.4"

RUN echo "Busting cache for SDK update: siyi_sdk 15b60b8 gstreamer reconnect fix, siyi_ros2 9dda970 udp transport 2026-08-06"
# Clone and install SIYI SDK from GitHub (without its own pip dependencies to avoid overriding OpenCV).
RUN cd /tmp && \
    git clone -b siyi-sdk-v2 https://github.com/mzahana/siyi_sdk.git && \
    cd siyi_sdk && \
    pip3 install --no-deps . && \
    cd / && \
    rm -rf /tmp/siyi_sdk
# Install ROS2 Camera Info Manager Python package    
RUN apt-get update && apt-get install -y --no-install-recommends ros-${ROS_DISTRO}-camera-info-manager-py
