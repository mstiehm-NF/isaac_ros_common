#!/bin/bash

echo "Creating non-root container '${USERNAME}' for host user uid=${HOST_USER_UID}:gid=${HOST_USER_GID}"

if [ ! $(getent group ${HOST_USER_GID}) ]; then
  groupadd --gid ${HOST_USER_GID} ${USERNAME} &>/dev/null
else
  CONFLICTING_GROUP_NAME=`getent group ${HOST_USER_GID} | cut -d: -f1`
  groupmod -o --gid ${HOST_USER_GID} -n ${USERNAME} ${CONFLICTING_GROUP_NAME}
fi

if [ ! $(getent passwd ${HOST_USER_UID}) ]; then
  useradd --no-log-init --uid ${HOST_USER_UID} --gid ${HOST_USER_GID} -m ${USERNAME} &>/dev/null
else
  CONFLICTING_USER_NAME=`getent passwd ${HOST_USER_UID} | cut -d: -f1`
  usermod -l ${USERNAME} -u ${HOST_USER_UID} -m -d /home/${USERNAME} ${CONFLICTING_USER_NAME} &>/dev/null
  mkdir -p /home/${USERNAME}
  # Wipe files that may create issues for users with large uid numbers.
  rm -f /var/log/lastlog /var/log/faillog
fi

# Update 'admin' user
chown ${USERNAME}:${USERNAME} /home/${USERNAME}
echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME}
chmod 0440 /etc/sudoers.d/${USERNAME}
adduser ${USERNAME} video >/dev/null
adduser ${USERNAME} plugdev >/dev/null
adduser ${USERNAME} sudo  >/dev/null

# If jtop present, give the user access
if [ -S /run/jtop.sock ]; then
  JETSON_STATS_GID="$(stat -c %g /run/jtop.sock)"
  addgroup --gid ${JETSON_STATS_GID} jtop >/dev/null
  adduser ${USERNAME} jtop >/dev/null
fi

# Run all entrypoint additions
shopt -s nullglob
for addition in /usr/local/bin/scripts/entrypoint_additions/*.sh; do
  if [[ "${addition}" =~ ".user." ]]; then
    echo "Running entryrypoint extension: ${addition} as user ${USERNAME}"
    gosu ${USERNAME} ${addition}
  else
    echo "Sourcing entryrypoint extension: ${addition}"
    source ${addition}
  fi
done

# Set the machine identification
MACHINE_CONFIG_PATH="/usr/config/machine_config.json"


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
export ISAAC_ROS_WS="/workspaces/isaac_ros-dev"
export ISAAC_ROS_ACCEPT_EULA="1"

# Make sure the user has the correct permissions
sudo chown -R 1000:1000 /workspaces/isaac_ros-dev/install

#add nice capabilities to python3.8
sudo setcap cap_sys_nice+ep /usr/bin/python3.10

# Create ROS 2 library config file
echo "/opt/ros/$ROS_DISTRO/lib" | sudo tee /etc/ld.so.conf.d/ros2_$ROS_DISTRO.conf
echo "/opt/ros/$ROS_DISTRO/lib/x86_64-linux-gnu/" | sudo tee -a /etc/ld.so.conf.d/ros2_$ROS_DISTRO.conf
echo "/opt/ros/$ROS_DISTRO/opt/rviz_ogre_vendor/lib" | sudo tee -a /etc/ld.so.conf.d/ros2_$ROS_DISTRO.conf

# Create NVIDIA library config file
echo "/usr/local/cuda/compat/lib" | sudo tee /etc/ld.so.conf.d/nvidia_libs.conf
echo "/usr/local/nvidia/lib" | sudo tee -a /etc/ld.so.conf.d/nvidia_libs.conf
echo "/usr/local/nvidia/lib64" | sudo tee -a /etc/ld.so.conf.d/nvidia_libs.conf
echo "/opt/tritonserver/backends/onnxruntime" | sudo tee -a /etc/ld.so.conf.d/nvidia_libs.conf
echo "/opt/tritonserver/lib" | sudo tee -a /etc/ld.so.conf.d/nvidia_libs.conf

# Update the dynamic linker cache
sudo ldconfig

# Source ROS2
source /opt/ros/${ROS_DISTRO}/setup.bash
echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ~/.bashrc
echo "export ISAAC_ROS_WS=${ISAAC_ROS_WS}" >> ~/.bashrc
echo "export ISAAC_ROS_ACCEPT_EULA=${ISAAC_ROS_ACCEPT_EULA}" >> ~/.bashrc

# Restart udev daemon
service udev restart

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

# Find all lib directories under your workspace install and write them to a temporary file.
find /workspaces/isaac_ros-dev/install -type d -name lib > d/tmp/isaac_ros_install_libs.conf

# Move the temporary file to /etc/ld.so.conf.d/ (using sudo to have proper permissions)
sudo mv /tmp/isaac_ros_install_libs.conf /etc/ld.so.conf.d/isaac_ros_install_libs.conf

# Update the dynamic linker cache
sudo ldconfig

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
# exec gosu ${USERNAME} "$@"

# Task to catch the SIGTERM signal
child=$! 
wait "$child"

