#!/bin/bash

export ISAAC_ROS_WS="/workspaces/isaac_ros-dev"
export ISAAC_ROS_ACCEPT_EULA="1"

echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ~/.bashrc

source /opt/ros/${ROS_DISTRO}/setup.bash

sudo chown -R admin /workspaces/isaac_ros-dev/

colcon build --packages-select \
    backend_msgs \
    backend_ui_server \
    camera_pose_calibration \
    can_ros_nodes \
    drive_system_odometry \
    microcdr \
    micro_ros_agent \
    micro_ros_msgs \
    microxrcedds_client \
    mmc_ui_msgs \
    serial_ros_nodes \
    mli_ros_simulator \
    ros_simulator_web_app

source /workspaces/isaac_ros-dev/install/setup.bash

rm -rf /workspaces/isaac_ros-dev/test_results

mkdir -p /workspaces/isaac_ros-dev/test_results

echo Starting Tests...

# -vs to show logs
pytest -v --disable-warnings \
    /workspaces/isaac_ros-dev/src/backend_components/backend_ui_server/backend_ui_server/tests/ \
    --junitxml=/workspaces/isaac_ros-dev/test_results/test-result.xml \
    --cov=. \
    --cov-report xml:/workspaces/isaac_ros-dev/test_results/coverage-result.xml
