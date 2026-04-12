#---
# name: gps-denied-nav
# depends: [opencv, cudastack, torchvision, onnxruntime]
# requires: '>=36'
# config: config.py
#---
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
RUN pip install colorama

# Set up environment variables
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ~/.bashrc
ENV ROS_ROOT=/opt/ros/${ROS_DISTRO}
ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp

CMD ["/bin/bash"]
