#!/bin/bash

# Check if network share is mounted
is_network_share_mounted() {
    local mount_point="$1"
    if [ -z "$mount_point" ]; then
        mount_point="$NETWORK_SHARE_PATH"
    fi

    mount | grep -q " on $mount_point "
    return $?
}

# Mount network share
mount_network_share() {
    local mount_point="$1"
    local network_path="$2"
    local username="$3"
    local password="$4"

    if [ -z "$mount_point" ]; then
        mount_point="$NETWORK_SHARE_PATH"
        network_path="$NETWORK_SHARE_URL"
        username="$NETWORK_SHARE_USERNAME"
        password="$NETWORK_SHARE_PASSWORD"
    fi

    log_info "Mounting network share at $mount_point"

    # Check if directory exists for mount point
    if [ ! -d "$mount_point" ]; then
        sudo mkdir -p "$mount_point"
    fi

    # Mount using appropriate method based on share type
    if [[ "$network_path" == smb://* ]]; then
        # SMB mount
        sudo mount -t smbfs "//$username:$password@${network_path#smb://}" "$mount_point"
    elif [[ "$network_path" == afp://* ]]; then
        # AFP mount
        sudo mount -t afp "afp://$username:$password@${network_path#afp://}" "$mount_point"
    elif [[ "$network_path" == nfs://* ]]; then
        # NFS mount
         sudo mount -t nfs "${network_path#nfs://}" "$mount_point"
    else
        log_error "Unsupported network share type: $network_path"
        return 1
    fi

    # Verify mount was successful
    if is_network_share_mounted "$mount_point"; then
        log_info "Network share mounted successfully"
        return 0
    else
        log_error "Failed to mount network share"
        return 1
    fi
}

# Unmount network share
unmount_network_share() {
    local mount_point="$1"

    if [ -z "$mount_point" ]; then
        mount_point="$NETWORK_SHARE_PATH"
    fi

    if is_network_share_mounted "$mount_point"; then
        log_info "Unmounting network share at $mount_point"
        umount "$mount_point"
        return $?
    else
        log_info "Network share not mounted, nothing to unmount"
        return 0
    fi
}
