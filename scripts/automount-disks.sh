#!/usr/bin/env bash
# Purpose: Configure automount entries for unmounted ext4 and NTFS disks.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

# Resolve the target user for mount ownership and NTFS UID/GID mapping.
if [ -n "${SUDO_USER:-}" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    ACTUAL_USER="$USER"
fi

# Refuse direct root execution to avoid assigning disk ownership to root.
if [ "$ACTUAL_USER" = "root" ]; then
    echo "ERROR: Please run this script with sudo from a normal user account, not as root directly."
    exit 1
fi

ACTUAL_UID=$(id -u "$ACTUAL_USER")
ACTUAL_GID=$(id -g "$ACTUAL_USER")

echo ">> Configuring disks for user: $ACTUAL_USER (UID: $ACTUAL_UID)"

# Back up /etc/fstab before writing new mount entries.
cp /etc/fstab "/etc/fstab.backup.$(date +%F_%T)"
echo ">> Backup of /etc/fstab created."

# Scan block devices in parse-friendly mode (no headers, raw output).
lsblk -n -r -o NAME,FSTYPE,UUID,LABEL,MOUNTPOINT | while read -r DEV FSTYPE UUID LABEL MOUNTPOINT; do
    
    # Skip devices without UUIDs or devices that are already mounted.
    if [ -z "$UUID" ] || [ -n "$MOUNTPOINT" ]; then
        continue
    fi

    # Skip entries that already exist to keep the script idempotent.
    if grep -q "$UUID" /etc/fstab; then
        echo ">> Skipping $DEV ($UUID) - already present in /etc/fstab."
        continue
    fi

    # Build mount directory name from label when present, otherwise UUID.
    if [ -n "$LABEL" ]; then
        # Replace label spaces so the directory path remains shell-safe.
        SAFE_LABEL=$(echo "$LABEL" | tr ' ' '_')
        MOUNT_DIR="/mnt/$SAFE_LABEL"
    else
        MOUNT_DIR="/mnt/disk_$UUID"
    fi

    # Write filesystem-specific automount entries.
    if [[ "$FSTYPE" == "ext4" ]]; then
        echo ">> Found EXT4 drive on $DEV. Configuring automount..."
        mkdir -p "$MOUNT_DIR"
        
        # Mount on access, do not mount at boot, and unmount after idle timeout.
        echo "UUID=$UUID  $MOUNT_DIR  ext4  defaults,noatime,noauto,x-systemd.automount,x-systemd.idle-timeout=15min  0  0" >> /etc/fstab
        
        # Mount briefly to apply user ownership, then unmount.
        mount "$DEV" "$MOUNT_DIR"
        chown -R "$ACTUAL_UID":"$ACTUAL_GID" "$MOUNT_DIR"
        umount "$MOUNT_DIR"

    elif [[ "$FSTYPE" == "ntfs" || "$FSTYPE" == "ntfs3" ]]; then
        echo ">> Found NTFS drive on $DEV. Configuring automount..."
        mkdir -p "$MOUNT_DIR"

        # Use ntfs3 and map file ownership directly to the target user.
        echo "UUID=$UUID  $MOUNT_DIR  ntfs3  defaults,noatime,uid=$ACTUAL_UID,gid=$ACTUAL_GID,umask=022,nofail,noauto,x-systemd.automount,x-systemd.idle-timeout=15min  0  0" >> /etc/fstab
    fi
done

    # Reload systemd so it recognizes newly created automount units.
echo ">> Reloading systemd daemons..."
systemctl daemon-reload
systemctl restart local-fs.target

echo ">> Done! Your drives are now ready and will mount automatically upon access."