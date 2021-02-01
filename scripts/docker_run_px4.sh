#!/usr/bin/env bash

DOCKER_REPO="ros:melodic-ros-px4-l4t-r32.4.4"
CONTAINER_NAME="px4"
USER_VOLUME=""
USER_COMMAND=""
USER_NAME=riot

# This will enable running containers with different names
# It will create a local workspace and link it to the image's catkin_ws
if [ "$1" != "" ]; then
    CONTAINER_NAME=$1
    WORKSPACE_DIR=~/$1_shared_volume
    if [ ! -d $WORKSPACE_DIR ]; then
        mkdir -p $WORKSPACE_DIR
    fi
    echo "Container name:$1 WORSPACE DIR:$WORKSPACE_DIR" 
fi

#echo "CONTAINER_IMAGE: $CONTAINER_IMAGE"
#echo "USER_VOLUME:     $USER_VOLUME"
#echo "USER_COMMAND:    '$USER_COMMAND'"

# run the container
sudo xhost +si:localuser:root

echo "Starting Container: ${CONTAINER_NAME} with REPO: $DOCKER_REPO"
 
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    if [ "$(docker ps -aq -f status=exited -f name=${CONTAINER_NAME})" ]; then
        # cleanup
        docker start ${CONTAINER_NAME}
    fi
    if [ -z "$CMD" ]; then
        docker exec -it --user $USER_NAME ${CONTAINER_NAME} bash
    else
        docker exec -it --user $USER_NAME ${CONTAINER_NAME} bash -c "$CMD"
    fi
else

# sudo docker run --runtime nvidia -it --rm --network host -e DISPLAY=$DISPLAY \
#     -v /tmp/.X11-unix/:/tmp/.X11-unix \
#     $USER_VOLUME $CONTAINER_IMAGE $USER_COMMAND

docker run --runtime nvidia -it --network host -e DISPLAY=$DISPLAY \
    -v /tmp/.X11-unix/:/tmp/.X11-unix \
    --group-add=dialout \
    --group-add=tty \
    --tty=true \
    --device=/dev/ttyTHS1 \
    --volume="$WORKSPACE_DIR:/home/$USER_NAME/shared_volume:rw" \
    --workdir="/home/$USER_NAME" \
    --name=${CONTAINER_NAME} \
    --privileged=true \
    $DOCKER_REPO
fi