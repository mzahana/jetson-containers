#!/usr/bin/env bash

# configure dialout group

# Add docker group and user to it
echo " " && echo "Docker configuration ..." && echo " "
sudo groupadd docker
sudo gpasswd -a $(whoami) docker

# Adjust serial port permissions
echo " " && echo "Serial ports configuration (ttyTHS1) ..." && echo " "
sudo usermod -aG dialout $(whoami)
sudo usermod -aG tty $(whoami)

echo " " && echo "Adding udev rules for /dev/ttyTHS* ..." && echo " " && sleep 1
echo 'KERNEL=="ttyTHS*", MODE="0666"' | sudo tee /etc/udev/rules.d/55-tegraserial.rules
# nvgetty needs to be disabled in order to set ppermanent permissions for ttyTHS1 on jetson nano
# see (https://forums.developer.nvidia.com/t/read-write-permission-ttyths1/81623/5)

echo " " && echo "Disabling nvgetty ..." && echo " " && sleep 1
sudo systemctl stop nvgetty
sudo systemctl disable nvgetty
sudo udevadm trigger


echo && echo "Install udev rules for Realsense D435..."
cd $HOME/src/jetson-containers/scripts
./installRealsenseUdev.sh

cd $HOME/src/jetson-containers/
echo " " && echo "Building $HOME/src/jetson-containers/Dockerfile.ros.melodic.px4 ..." && echo " " && sleep 1
./scripts/docker_build_ros_px4.sh

echo " " && echo "Adding alias to .bashrc script ..." && echo " "
grep -xF "alias px4_container='source \$HOME/src/jetson-containers/scripts/docker_run_px4.sh'" ${HOME}/.bashrc || echo "alias px4_container='source \$HOME/src/jetson-containers/scripts/docker_run_px4.sh'" >> ${HOME}/.bashrc

echo " " && echo "#------------- You can run the px4 container from the terminal by executing px4_container -------------#" && echo " "

cd $HOME

echo "#------------- Please reboot your Jetson Nano for some changes to take effect -------------#" && echo "" && echo " "