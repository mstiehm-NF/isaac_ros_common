#!/bin/bash

# ─── Clean shutdown on Ctrl+C or TERM ─────────────────────────────────────────
echo "Creating non-root container '${USERNAME}' for host user uid=${HOST_USER_UID}:gid=${HOST_USER_GID}"

_term() {
    echo "Caught SIGTERM signal!"
    kill -TERM -1
    sleep 2
    echo "Now exiting"
    exit 0
}
trap _term SIGTERM SIGINT

# ─── User / Group setup ───────────────────────────────────────────────────────
if ! getent group "${HOST_USER_GID}" >/dev/null; then
  groupadd --gid "${HOST_USER_GID}" "${USERNAME}" &>/dev/null
else
  CONFLICTING_GROUP_NAME=$(getent group "${HOST_USER_GID}" | cut -d: -f1)
  groupmod -o --gid "${HOST_USER_GID}" -n "${USERNAME}" "${CONFLICTING_GROUP_NAME}"
fi

if ! getent passwd "${HOST_USER_UID}" >/dev/null; then
  useradd --no-log-init --uid "${HOST_USER_UID}" --gid "${HOST_USER_GID}" -m "${USERNAME}" &>/dev/null
else
  CONFLICTING_USER_NAME=$(getent passwd "${HOST_USER_UID}" | cut -d: -f1)
  usermod -l "${USERNAME}" -u "${HOST_USER_UID}" -m -d "/home/${USERNAME}" "${CONFLICTING_USER_NAME}" &>/dev/null
  mkdir -p "/home/${USERNAME}"
  rm -f /var/log/lastlog /var/log/faillog
fi

chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}"
echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
chmod 0440 "/etc/sudoers.d/${USERNAME}"
adduser "${USERNAME}" video    >/dev/null
adduser "${USERNAME}" plugdev  >/dev/null
adduser "${USERNAME}" sudo     >/dev/null

# ─── jtop socket access ────────────────────────────────────────────────────────
if [ -S /run/jtop.sock ]; then
  JETSON_STATS_GID=$(stat -c %g /run/jtop.sock)
  addgroup --gid "${JETSON_STATS_GID}" jtop >/dev/null
  adduser "${USERNAME}" jtop       >/dev/null
fi

# ─── Ensure the user has a ~/.bashrc ───────────────────────────────────────────
HOME_DIR="/home/${USERNAME}"
USER_BASHRC="${HOME_DIR}/.bashrc"

if [ ! -f "${USER_BASHRC}" ]; then
  cp /etc/skel/.bashrc "${USER_BASHRC}"
  chown "${USERNAME}:${USERNAME}" "${USER_BASHRC}"
fi

append_user_bashrc() {
  echo "$1" | tee -a "${USER_BASHRC}" >/dev/null
  chown "${USERNAME}:${USERNAME}" "${USER_BASHRC}"
}

# ─── Run any entrypoint extensions ────────────────────────────────────────────
shopt -s nullglob
for addition in /usr/local/bin/scripts/entrypoint_additions/*.sh; do
  if [[ "${addition}" =~ ".user." ]]; then
    echo "Running entrypoint extension: ${addition} as user ${USERNAME}"
    gosu "${USERNAME}" "${addition}"
  else
    echo "Sourcing entrypoint extension: ${addition}"
    source "${addition}"
  fi
done

# ─── Machine configuration ────────────────────────────────────────────────────
MACHINE_CONFIG_PATH="/usr/config/machine_config.json"
if [[ -f "${MACHINE_CONFIG_PATH}" ]]; then
  CONFIG_ROUTE=".desired.machine_config.identification"
  ROS_DOMAIN_ID=$(jq -r "${CONFIG_ROUTE}.ros_domain_id" "${MACHINE_CONFIG_PATH}")
  ROS_NAMESPACE=$(jq -r "${CONFIG_ROUTE}.ros_namespace"  "${MACHINE_CONFIG_PATH}")
else
  echo "Error: ${MACHINE_CONFIG_PATH} does not exist."
fi

# ─── ROS_DOMAIN_ID & ROS_NAMESPACE ────────────────────────────────────────────
if [[ "${ROS_DOMAIN_ID}" != "null" ]] && (( ROS_DOMAIN_ID >= 0 && ROS_DOMAIN_ID < 233 )); then
  export ROS_DOMAIN_ID
  echo "ROS_DOMAIN_ID is set to ${ROS_DOMAIN_ID}"
else
  export ROS_DOMAIN_ID=0
  echo "ROS_DOMAIN_ID not set or out of range; defaulting to 0"
fi
append_user_bashrc "export ROS_DOMAIN_ID=${ROS_DOMAIN_ID}"

if [[ "${ROS_NAMESPACE}" == "null" ]]; then
  export ROS_NAMESPACE=''
  echo "ROS_NAMESPACE not set; using empty string"
else
  export ROS_NAMESPACE
  echo "ROS_NAMESPACE is set to ${ROS_NAMESPACE}"
fi
append_user_bashrc "export ROS_NAMESPACE=${ROS_NAMESPACE}"

if [[ "${LOG_RETENTION_DAYS}" != "null" ]] && [[ "${LOG_RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
  export LOG_RETENTION_DAYS
  echo "ROS Log retention time is set to ${LOG_RETENTION_DAYS} days"
else
  echo "ROS Log retention time is not set or invalid, defaulting to 7 days"
  export LOG_RETENTION_DAYS=7
fi
append_user_bashrc "export LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS}"

# ─── ISAAC_ROS environment ────────────────────────────────────────────────────
export ISAAC_ROS_WS="/workspaces/isaac_ros-dev"
export ISAAC_ROS_ACCEPT_EULA="1"
append_user_bashrc "export ISAAC_ROS_WS=${ISAAC_ROS_WS}"
append_user_bashrc "export ISAAC_ROS_ACCEPT_EULA=1"

# ─── Permissions, capabilities, and linker configs ────────────────────────────
sudo chown -R 1000:1000 /workspaces/isaac_ros-dev/install
sudo setcap cap_sys_nice+ep /usr/bin/python3.10

{
  echo "/opt/ros/${ROS_DISTRO}/lib"
  echo "/opt/ros/${ROS_DISTRO}/lib/x86_64-linux-gnu/"
  echo "/opt/ros/${ROS_DISTRO}/opt/rviz_ogre_vendor/lib"
} | sudo tee /etc/ld.so.conf.d/ros2_${ROS_DISTRO}.conf

{
  echo "/usr/local/cuda/compat/lib"
  echo "/usr/local/nvidia/lib"
  echo "/usr/local/nvidia/lib64"
  echo "/opt/tritonserver/backends/onnxruntime"
  echo "/opt/tritonserver/lib"
} | sudo tee /etc/ld.so.conf.d/nvidia_libs.conf

sudo ldconfig

# ─── Source ROS2 & workspace in this script (and save for future shells) ─────
source /opt/ros/${ROS_DISTRO}/setup.bash
append_user_bashrc "source /opt/ros/${ROS_DISTRO}/setup.bash"

# ─── Build workspace ──────────────────────────────────────────────────────────
colcon build --packages-ignore \
    isaac_ros_peoplenet_models_install \
    isaac_ros_apriltag_interfaces \
    isaac_ros_bi3d_interfaces \
    isaac_ros_nitros_bridge_interfaces \
    isaac_ros_nova_interfaces \
    isaac_ros_pointcloud_interfaces \
    isaac_ros_tensor_list_interfaces \
    isaac_ros_test \
    --allow-overriding isaac_ros_common \
    --allow-overriding isaac_ros_launch_utils


# ─── Source the built workspace & record for future shells ────────────────────
source /workspaces/isaac_ros-dev/install/setup.bash
append_user_bashrc "source /workspaces/isaac_ros-dev/install/setup.bash"

# ─── LD cache for workspace libs ──────────────────────────────────────────────
find /workspaces/isaac_ros-dev/install -type d -name lib \
  > /tmp/isaac_ros_install_libs.conf
sudo mv /tmp/isaac_ros_install_libs.conf \
          /etc/ld.so.conf.d/isaac_ros_install_libs.conf
sudo ldconfig

# ─── Set up permissions and groups ──────────────────────────────────────────────────────
LOGGING_DIR="/usr/log"
if [ ! -d "$LOGGING_DIR" ]; then
  sudo mkdir -p "$LOGGING_DIR"
fi

# ─── Final directory perms & optional VS Code extensions ─────────────────────
sudo chown 1000:1000 /usr/config/ /usr/data/ /usr/certs/ /usr/log/

if [[ "$(uname -m)" == "aarch64" ]]; then
  pip3 install typing-extensions --upgrade
fi

export RUN_DEV=true

if [[ "${VSCODE}" == "true" ]]; then
  for ext in \
    ms-python.python \
    github.copilot \
    ms-azuretools.vscode-docker \
    github.vscode-pull-request-github \
    eamodio.gitlens; do
    gosu "${USERNAME}" code --install-extension "${ext}" \
      --force --user-data-dir "${HOME_DIR}/.vscode/"
  done
  gosu "${USERNAME}" code --disable-gpu
fi

service udev restart

# ─── Set up ROS logging directory ────────────────────────────────────────────────
export ROS_LOG_DIR=$LOGGING_DIR

autodelete_logs() {
  while true; do
    if [[ -f "${MACHINE_CONFIG_PATH}" ]]; then
      LOG_ROUTE=".desired.machine_config.log_config"
      LOG_RETENTION_DAYS=$(jq -r "${LOG_ROUTE}.log_retention_days" "${MACHINE_CONFIG_PATH}")
        if [[ "${LOG_RETENTION_DAYS}" != "null" ]] && [[ "${LOG_RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
          export LOG_RETENTION_DAYS
          echo "ROS Log retention time is set to ${LOG_RETENTION_DAYS} days"
        else
          echo "ROS Log retention time is not set or invalid, defaulting to 7 days"
          export LOG_RETENTION_DAYS=7
        fi
    else
      echo "Error: ${MACHINE_CONFIG_PATH} does not exist. Defaulting log retention to 7 days."
      export LOG_RETENTION_DAYS=7
    fi
    # Delete logs older than LOG_RETENTION_DAYS
    echo "Deleting logs older than ${LOG_RETENTION_DAYS} days in ${ROS_LOG_DIR}"
    find "${ROS_LOG_DIR}" -mindepth 1 -mtime +${LOG_RETENTION_DAYS} -delete
    # Sleep for 3600 seconds
    sleep 3600
  done
}
autodelete_logs &

# ─── Launch backend and keep this script alive ────────────────────────────────
echo "Starting backend_ui_server as ${USERNAME}"
gosu "${USERNAME}" bash -l -c "\
  export ROS_DOMAIN_ID=${ROS_DOMAIN_ID} && \
  export ROS_NAMESPACE=${ROS_NAMESPACE} && \
  export LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS} && \
  export ROS_LOG_DIR=${ROS_LOG_DIR} && \
  export ISAAC_ROS_WS=${ISAAC_ROS_WS} && \
  export ISAAC_ROS_ACCEPT_EULA=1 && \
  ros2 run backend_ui_server server \
    --ros-args -r __ns:=/${ROS_NAMESPACE}" &

# Task to catch the SIGTERM signal
child=$! 
wait "$child"
