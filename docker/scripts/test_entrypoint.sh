#!/bin/bash

export ISAAC_ROS_WS="/workspaces/isaac_ros-dev"
export ISAAC_ROS_ACCEPT_EULA="1"

echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ~/.bashrc

source /opt/ros/${ROS_DISTRO}/setup.bash

sudo chown -R admin /workspaces/isaac_ros-dev/

colcon build --packages-ignore \
    isaac_ros_common \
    isaac_ros_peoplenet_models_install \
    isaac_ros_apriltag_interfaces \
    isaac_ros_bi3d_interfaces \
    isaac_ros_launch_utils \
    isaac_ros_nitros_bridge_interfaces \
    isaac_ros_nova_interfaces \
    isaac_ros_pointcloud_interfaces \
    isaac_ros_tensor_list_interfaces \
    isaac_ros_test

echo "source /workspaces/isaac_ros-dev/install/setup.bash" >> ~/.bashrc

source /workspaces/isaac_ros-dev/install/setup.bash

rm -rf /workspaces/isaac_ros-dev/test_results

mkdir -p /workspaces/isaac_ros-dev/test_results

echo Starting Tests...

# -vs to show logs
pytest -v --disable-warnings \
    /workspaces/isaac_ros-dev/src/backend_components/backend_ui_server/backend_ui_server/tests/ \
    /workspaces/isaac_ros-dev/src/azure_iot/configurator/tests/ \
    --junitxml=/workspaces/isaac_ros-dev/test_results/test-result.xml \
    --cov=. \
    --cov-report xml:/workspaces/isaac_ros-dev/test_results/coverage-result.xml
