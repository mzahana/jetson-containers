
#!/bin/bash
# Copy the Realsense udev rules to /etc/udev/rules.d
# ALias for Intel RealSense D435i camera

sudo cp ${HOME}/src/jetson-containers/udev/10-realsense.rules /etc/udev/rules.d

# Reread the rules; You may need to physically replug
sudo udevadm control --reload-rules 
sudo udevadm trigger
echo 'Realsense udev Rules installed'