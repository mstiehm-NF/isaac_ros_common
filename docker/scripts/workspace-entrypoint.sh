#!/bin/bash

# Set the machine identification
MACHINE_CONFIG_PATH="/usr/config/good_machine_config.json"


if [ -f "$MACHINE_CONFIG_PATH" ]; then
    CONFIG_ROUTE=".desired.machine_config.identification"
    MACHINE_ID=$(jq -r "$CONFIG_ROUTE.machine_id" $MACHINE_CONFIG_PATH)
    ROS_DOMAIN_ID=$(jq -r "$CONFIG_ROUTE.ros_domain_id" $MACHINE_CONFIG_PATH)
    ROS_NAMESPACE=$(jq -r "$CONFIG_ROUTE.ros_namespace" $MACHINE_CONFIG_PATH)
else
    echo "Error: $MACHINE_CONFIG_PATH does not exist."
fi

# if ros domain id is less than 232 and greater than 0 set it
if [ "$ROS_DOMAIN_ID" != "null" ] && [ "$ROS_DOMAIN_ID" -lt "233" ] && [ "$ROS_DOMAIN_ID" -gt "-1" ]; then
    export ROS_DOMAIN_ID=$ROS_DOMAIN_ID
    echo "export ROS_DOMAIN_ID=$ROS_DOMAIN_ID" >> ~/.bashrc
    echo "ROS_DOMAIN_ID is set to $ROS_DOMAIN_ID"
else
    export ROS_DOMAIN_ID=0
    echo "ROS_DOMAIN_ID is not set or out of range"
    echo "ROS_DOMAIN_ID is set to $ROS_DOMAIN_ID"
    echo "export ROS_DOMAIN_ID=$ROS_DOMAIN_ID" >> ~/.bashrc
fi

if [ "$ROS_NAMESPACE" == "null" ]; then
    echo "ROS_NAMESPACE is not set"
    export ROS_NAMESPACE=''
    echo "export ROS_NAMESPACE=$ROS_NAMESPACE" >> ~/.bashrc
    echo "ROS_NAMESPACE is set to $ROS_NAMESPACE"
else
    export ROS_NAMESPACE=$ROS_NAMESPACE
    echo "ROS_NAMESPACE is set to $ROS_NAMESPACE"
    echo "export ROS_NAMESPACE=$ROS_NAMESPACE" >> ~/.bashrc
fi

# Get platform
PLATFORM="$(uname -m)"

# Make sure the user has the correct permissions
sudo chown -R 1000:1000 /workspaces/isaac_ros-dev/install

# Source ROS2
source /opt/ros/${ROS_DISTRO}/setup.bash
echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ~/.bashrc

# Restart udev daemon
sudo service udev restart

colcon build \
    --continue-on-error --packages-select \
    backend_msgs \
    backend_ui_server \
    camera_pose_calibration \
    can_ros_nodes \
    custom_nitros_image \
    custom_nitros_string \
    drive_system_odometry \
    isaac_ros_apriltag \
    isaac_ros_apriltag_interfaces \
    isaac_ros_bi3d_interfaces \
    isaac_ros_common \
    isaac_ros_depth_image_proc \
    isaac_ros_detectnet \
    isaac_ros_dnn_image_encoder \
    isaac_ros_gxf \
    isaac_ros_image_pipeline \
    isaac_ros_image_proc \
    isaac_ros_managed_nitros \
    isaac_ros_nitros \
    isaac_ros_nitros_april_tag_detection_array_type \
    isaac_ros_nitros_bridge_interfaces \
    isaac_ros_nitros_camera_info_type \
    isaac_ros_nitros_compressed_image_type \
    isaac_ros_nitros_detection2_d_array_type \
    isaac_ros_nitros_detection3_d_array_type \
    isaac_ros_nitros_disparity_image_type \
    isaac_ros_nitros_encoder_ticks_type \
    isaac_ros_nitros_flat_scan_type \
    isaac_ros_nitros_imu_type \
    isaac_ros_nitros_image_type \
    isaac_ros_nitros_interfaces \
    isaac_ros_nitros_occupancy_grid_type \
    isaac_ros_nitros_odometry_type \
    isaac_ros_nitros_point_cloud_type \
    isaac_ros_nitros_pose_array_type \
    isaac_ros_nitros_pose_cov_stamped_type \
    isaac_ros_nitros_std_msg_type \
    isaac_ros_nitros_tensor_list_type \
    isaac_ros_nitros_twist_type \
    isaac_ros_nvblox \
    isaac_ros_pointcloud_interfaces \
    isaac_ros_stereo_image_proc \
    isaac_ros_tensor_list_interfaces \
    isaac_ros_tensor_rt \
    isaac_ros_test \
    isaac_ros_triton \
    isaac_ros_visual_slam \
    isaac_ros_visual_slam_interfaces \
    isaac_ros_yolov8 \
    isaac_slam_saver \
    map_saver_2d \
    microcdr \
    micro_ros_agent \
    micro_ros_msgs \
    microxrcedds_client \
    mmc_ui_msgs \
    mli_ros_simulator \
    nvblox \
    nvblox_cpu_gpu_tools \
    nvblox_examples_bringup \
    nvblox_image_padding \
    nvblox_isaac_sim \
    nvblox_msgs \
    nvblox_nav2 \
    nvblox_performance_measurement \
    nvblox_performance_measurement_msgs \
    nvblox_ros \
    nvblox_ros_common \
    nvblox_rviz_plugin \
    odometry_flattener \
    realsense2_camera \
    realsense2_camera_msgs \
    realsense2_description \
    realsense_splitter \
    ros_simulator_web_app \
    semantic_label_conversion \
    serial_ros_nodes \
     
    # isaac_ros_nitros_battery_state_type \
    # isaac_ros_nitros_correlated_timestamp_type \
    # isaac_ros_nova_interfaces \
    # network_performance_measurement \
    # depthai_bridge \
    # depthai_descriptions \
    # depthai_examples \
    # depthai_filters \
    # depthai-ros \
    # depthai_ros_driver \
    # depthai_ros_msgs \

echo "source /workspaces/isaac_ros-dev/install/setup.bash" >> ~/.bashrc
source /workspaces/isaac_ros-dev/install/setup.bash

# Setup before starting BE server
sudo chown 1000:1000 /usr/config/
sudo chown 1000:1000 /usr/data/
sudo chown 1000:1000 /usr/certs/

if [[ "$PLATFORM" == "aarch64" ]]; then
    pip3 install typing-extensions --upgrade
fi

export RUN_DEV=true

# If VS Code is installed
if [[ "$VSCODE" == true ]]; then
    code --install-extension ms-python.python --force --user-data-dir $HOME/.vscode/ 
    code --install-extension codium.codium --force --user-data-dir $HOME/.vscode/
    code --install-extension github.copilot --force --user-data-dir $HOME/.vscode/
    code --install-extension ms-azuretools.vscode-docker --force --user-data-dir $HOME/.vscode/
    code --install-extension github.vscode-pull-request-github --force --user-data-dir $HOME/.vscode/
    code --install-extension eamodio.gitlens --force --user-data-dir $HOME/.vscode/
    code --disable-gpu
fi

_term() {
    echo "Caught SIGTERM signal!!!"
    kill -TERM -1
    exit 0
}
trap _term SIGTERM SIGINT

# Start the application
ros2 run backend_ui_server server --ros-args -r __ns:=/${ROS_NAMESPACE} &

# Task to catch the SIGTERM signal
child=$! 
wait "$child"

