#!/bin/bash

export ISAAC_ROS_WS="/workspaces/isaac_ros-dev"
export ISAAC_ROS_ACCEPT_EULA="1"

USERNAME="${USERNAME:-admin}"
HOST_USER_UID="${HOST_USER_UID:-1000}"
HOST_USER_GID="${HOST_USER_GID:-1000}"

# The workspace is bind-mounted from the host, so every file in it carries the
# host uid/gid. colcon has to run as that same user: as root, git refuses to
# introspect the repo ("detected dubious ownership"), ament's egg_info step
# fails, and micro_ros_msgs plus everything downstream of it aborts.
#
# Only the 'user' image layer creates the account, and that layer is not part of
# every image key (see scripts/image_layers.config), so set the user up here
# instead of assuming it exists.
if [ "$(id -u)" -eq 0 ]; then
    if ! getent group "${HOST_USER_GID}" >/dev/null; then
        groupadd --gid "${HOST_USER_GID}" "${USERNAME}"
    else
        CONFLICTING_GROUP_NAME=$(getent group "${HOST_USER_GID}" | cut -d: -f1)
        if [ "${CONFLICTING_GROUP_NAME}" != "${USERNAME}" ]; then
            groupmod -o --gid "${HOST_USER_GID}" -n "${USERNAME}" "${CONFLICTING_GROUP_NAME}"
        fi
    fi

    if ! getent passwd "${HOST_USER_UID}" >/dev/null; then
        useradd --no-log-init --uid "${HOST_USER_UID}" --gid "${HOST_USER_GID}" -m "${USERNAME}"
    else
        CONFLICTING_USER_NAME=$(getent passwd "${HOST_USER_UID}" | cut -d: -f1)
        if [ "${CONFLICTING_USER_NAME}" != "${USERNAME}" ]; then
            usermod -l "${USERNAME}" -u "${HOST_USER_UID}" -m -d "/home/${USERNAME}" "${CONFLICTING_USER_NAME}"
        fi
    fi

    # Resolve the name actually attached to the uid: if usermod could not rename
    # the pre-existing account, the build still has to address the right user.
    RUNTIME_USER=$(getent passwd "${HOST_USER_UID}" | cut -d: -f1)
    RUNTIME_HOME=$(getent passwd "${HOST_USER_UID}" | cut -d: -f6)

    mkdir -p "${RUNTIME_HOME}"
    chown "${HOST_USER_UID}:${HOST_USER_GID}" "${RUNTIME_HOME}"

    echo "${RUNTIME_USER} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${RUNTIME_USER}"
    chmod 0440 "/etc/sudoers.d/${RUNTIME_USER}"

    # Repairs anything a previous root-owned run left behind in the mount.
    chown -R "${HOST_USER_UID}:${HOST_USER_GID}" "${ISAAC_ROS_WS}"

    # Address the target by uid:gid so this works even if the rename above did not.
    export ISAAC_ROS_WS_REOWNED=1
    exec gosu "${HOST_USER_UID}:${HOST_USER_GID}" "$0" "$@"
fi

# Reached either after the re-exec above, or directly when the container was
# started with --user, which is what CI does via scripts/run_dev_image.sh. In
# that second case nothing has re-owned the mount yet, so do it here.
if [ -z "${ISAAC_ROS_WS_REOWNED}" ] && sudo -n true 2>/dev/null; then
    sudo chown -R "$(id -u):$(id -g)" "${ISAAC_ROS_WS}" || true
fi

# `git config --global` needs a writable HOME, and a container started with
# --user can land on an account whose home directory was never created.
if [ ! -w "${HOME:-/nonexistent}" ]; then
    HOME="$(mktemp -d)"
    export HOME
fi

# Fallback for mounts that cannot be re-owned (rootless docker, uid remapping):
# without this the egg_info step fails the same way it does as root.
git config --global --add safe.directory "${ISAAC_ROS_WS}"

echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> ~/.bashrc

source /opt/ros/${ROS_DISTRO}/setup.bash

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

echo "source /workspaces/isaac_ros-dev/install/setup.bash" >> ~/.bashrc

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
