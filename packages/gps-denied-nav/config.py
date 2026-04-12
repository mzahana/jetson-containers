from jetson_containers import LSB_RELEASE

pkg = package.copy()

# Automatically select ROS distribution based on the Ubuntu version
# JetPack 6 (Ubuntu 22.04) uses humble
# JetPack 7 (Ubuntu 24.04) uses jazzy
ros_distro = 'humble' if LSB_RELEASE == '22.04' else 'jazzy'

pkg['build_args'] = {
    'ROS_DISTRO': ros_distro
}

package = pkg
