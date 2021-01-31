#!/usr/bin/env bash

set -e

BASE_IMAGE="nvcr.io/nvidia/l4t-base"
L4T_VERSION="r32.4.4"
ROS_DISTRO=melodic

echo "building containers for $ROS_DISTRO..."

sh ./scripts/docker_build.sh ros:$ROS_DISTRO-ros-px4-l4t-$L4T_VERSION Dockerfile.ros.$ROS_DISTRO.px4 --build-arg BASE_IMAGE=$BASE_IMAGE:$L4T_VERSION