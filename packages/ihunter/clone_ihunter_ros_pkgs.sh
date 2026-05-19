#!/bin/bash
# The following variables should be paths inside the gpsd container not the host!!
ROS2_SRC=/root/shared_volume/ros2_ws/src
ROS2_WS=/root/shared_volume/ros2_ws

# Silence Python deprecation warnings (pkg_resources, setuptools)
export PYTHONWARNINGS="ignore"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

#
# MAVROS
#
echo -e "${YELLOW}Cloning mavlink package ... ${NC}" && sleep 1
if [ ! -d "$ROS2_SRC/mavlink" ]; then
    mkdir -p $ROS2_SRC
    cd $ROS2_SRC
    git clone https://github.com/ros2-gbp/mavlink-gbp-release.git mavlink
    cd $ROS2_SRC/mavlink && git checkout release/humble/mavlink/2023.9.9-1
fi

echo -e "${YELLOW}Cloning custom mavros package ... ${NC}" && sleep 1
if [ ! -d "$ROS2_SRC/mavros" ]; then
    cd $ROS2_SRC
    git clone https://github.com/mzahana/mavros.git
    cd $ROS2_SRC/mavros && git checkout ros2_humble
fi


#
# d2dtracker_drone_detector
#
echo -e "${YELLOW}Cloning d2dtracker_drone_detector ... ${NC}" && sleep 1
if [ ! -d "$ROS2_SRC/d2dtracker_drone_detector" ]; then
    cd $ROS2_SRC
    git clone https://github.com/mzahana/d2dtracker_drone_detector.git
    cd $ROS2_SRC/d2dtracker_drone_detector && git checkout ros2_humble && git pull origin ros2_humble
else
    cd $ROS2_SRC/d2dtracker_drone_detector && git checkout ros2_humble && git pull origin ros2_humble
fi

#
# multi_target_kf
#
echo -e "${YELLOW}Cloning multi_target_kf ... ${NC}" && sleep 1
if [ ! -d "$ROS2_SRC/multi_target_kf" ]; then
    cd $ROS2_SRC
    git clone https://github.com/mzahana/multi_target_kf.git -b ros2_humble
else
    cd $ROS2_SRC/multi_target_kf && git checkout ros2_humble && git pull origin ros2_humble
fi

#
# custom_trajectory_msgs
#
echo -e "${YELLOW}Cloning custom_trajectory_msgs ... ${NC}" && sleep 1
if [ ! -d "$ROS2_SRC/custom_trajectory_msgs" ]; then
    cd $ROS2_SRC
    git clone https://github.com/mzahana/custom_trajectory_msgs.git -b ros2_humble
else
    cd $ROS2_SRC/custom_trajectory_msgs && git checkout ros2_humble && git pull origin ros2_humble
fi

#
# trajectory_prediction
# Constant velocity and Bezier based trajectory prediction
#
echo -e "${YELLOW}Cloning trajectory_prediction ... ${NC}" && sleep 1
if [ ! -d "$ROS2_SRC/trajectory_prediction" ]; then
    cd $ROS2_SRC
    git clone https://github.com/mzahana/trajectory_prediction.git -b ros2_humble
else
    cd $ROS2_SRC/trajectory_prediction && git checkout ros2_humble && git pull origin ros2_humble
fi

#
# drone_path_predictor_ros
# GRU-based trajectory prediction
#
echo -e "${YELLOW}Cloning drone_path_predictor_ros ... ${NC}" && sleep 1
if [ ! -d "$ROS2_SRC/drone_path_predictor_ros" ]; then
    cd $ROS2_SRC
    git clone https://github.com/mzahana/drone_path_predictor_ros.git -b ros2_humble
else
    cd $ROS2_SRC/drone_path_predictor_ros && git checkout ros2_humble && git pull origin ros2_humble
fi

#
# trajectory_generation
# MPC-based trajectory generation
#
echo -e "${YELLOW}Cloning trajectory_generation ... ${NC}" && sleep 1
if [ ! -d "$ROS2_SRC/trajectory_generation" ]; then
    cd $ROS2_SRC
    git clone https://github.com/mzahana/trajectory_generation.git -b ros2_humble
else
    cd $ROS2_SRC/trajectory_generation && git checkout ros2_humble && git pull origin ros2_humble
fi

#
# mav_controllers_ros
#
echo -e "${YELLOW}Cloning mav_controllers_ros ... ${NC}" && sleep 1
if [ ! -d "$ROS2_SRC/mav_controllers_ros" ]; then
    cd $ROS2_SRC
    git clone https://github.com/mzahana/mav_controllers_ros.git
    cd $ROS2_SRC/mav_controllers_ros && git checkout ros2_humble
else
    cd $ROS2_SRC/mav_controllers_ros && git checkout ros2_humble && git pull origin ros2_humble
fi

# Fix PYTHONPATH for the current session if it's missing system paths
export PYTHONPATH=$PYTHONPATH:/usr/lib/python3/dist-packages

cd $ROS2_WS
# Only init rosdep if it hasn't been done
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    rosdep init
fi
echo -e "${YELLOW}Updating rosdep...${NC}"
rosdep update
echo -e "${YELLOW}Installing dependencies...${NC}"
rosdep install --from-paths src --ignore-src -r -y

# Build with flags to suppress CMake warnings and handle Python policies
echo -e "${GREEN}Starting build...${NC}"
cd $ROS2_WS
MAKEFLAGS='-j1 -l1' colcon build \
    --packages-up-to mavros_msgs \
    --executor sequential \
    --cmake-args \
    -Wno-dev \
    -Wno-deprecated \
    -DCMAKE_POLICY_DEFAULT_CMP0148=OLD \
    -DCMAKE_BUILD_TYPE=Release

cd $ROS2_WS
MAKEFLAGS='-j1 -l1' colcon build \
    --executor sequential \
    --cmake-args \
    -Wno-dev \
    -Wno-deprecated \
    -DCMAKE_POLICY_DEFAULT_CMP0148=OLD \
    -DCMAKE_BUILD_TYPE=Release