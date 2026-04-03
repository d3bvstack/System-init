#!/usr/bin/env bash
# /usr/local/sbin/automount-disks.sh
# Safely detects unmounted EXT4/NTFS disks and configures systemd.automount

set -Eeuo pipefail

# 1. Determine the primary user (for ownership and NTFS UID mapping)
if [ -n "${SUDO_USER:-}" ]; then
    ACTUAL_USER="$SUDO_USER"
else
    ACTUAL_USER="$USER"
fi

# Ensure we don't accidentally map permissions to the root user
if [ "$ACTUAL_USER" = "root" ]; then
    echo "ERROR: Please run this script with sudo from a normal user account, not as root directly."
    exit 1
fi

ACTUAL_UID=$(id -u "$ACTUAL_USER")
ACTUAL_GID=$(id -g "$ACTUAL_USER")

echo ">> Configuring disks for user: $ACTUAL_USER (UID: $ACTUAL_UID)"

# Backup fstab before doing anything destructive
cp /etc/fstab "/etc/fstab.backup.$(date +%F_%T)"
echo ">> Backup of /etc/fstab created."

# 2. Scan block devices
# -n: no headers, -o: specific columns, -r: raw output (easy to parse)
lsblk -n -r -o NAME,FSTYPE,UUID,LABEL,MOUNTPOINT | while read -r DEV FSTYPE UUID LABEL MOUNTPOINT; do
    
    # Skip if it doesn't have a UUID or is already mounted (like your root partition)
    if [ -z "$UUID" ] || [ -n "$MOUNTPOINT" ]; then
        continue
    fi

    # Check if the UUID is already in /etc/fstab to ensure idempotency
    if grep -q "$UUID" /etc/fstab; then
        echo ">> Skipping $DEV ($UUID) - already present in /etc/fstab."
        continue
    fi

    # Determine Mount Point Name (Prefer LABEL, fallback to UUID)
    if [ -n "$LABEL" ]; then
        # Replace spaces in label with underscores
        SAFE_LABEL=$(echo "$LABEL" | tr ' ' '_')
        MOUNT_DIR="/mnt/$SAFE_LABEL"
    else
        MOUNT_DIR="/mnt/disk_$UUID"
    fi

    # 3. Handle EXT4 and NTFS
    if [[ "$FSTYPE" == "ext4" ]]; then
        echo ">> Found EXT4 drive on $DEV. Configuring automount..."
        mkdir -p "$MOUNT_DIR"
        
        # x-systemd.automount: Mounts on request
        # noauto: Prevents mounting at boot
        # x-systemd.idle-timeout=15min: Unmounts after 15 minutes of inactivity
        echo "UUID=$UUID  $MOUNT_DIR  ext4  defaults,noatime,noauto,x-systemd.automount,x-systemd.idle-timeout=15min  0  0" >> /etc/fstab
        
        # Temporarily mount to fix root ownership issue, then unmount
        mount "$DEV" "$MOUNT_DIR"
        chown -R "$ACTUAL_UID":"$ACTUAL_GID" "$MOUNT_DIR"
        umount "$MOUNT_DIR"

    elif [[ "$FSTYPE" == "ntfs" || "$FSTYPE" == "ntfs3" ]]; then
        echo ">> Found NTFS drive on $DEV. Configuring automount..."
        mkdir -p "$MOUNT_DIR"

        # Uses modern ntfs3 driver and maps permissions directly to your user
        echo "UUID=$UUID  $MOUNT_DIR  ntfs3  defaults,noatime,uid=$ACTUAL_UID,gid=$ACTUAL_GID,umask=022,nofail,noauto,x-systemd.automount,x-systemd.idle-timeout=15min  0  0" >> /etc/fstab
    fi
done

# 4. Reload Systemd so it registers the new automount targets
echo ">> Reloading systemd daemons..."
systemctl daemon-reload
systemctl restart local-fs.target

echo ">> Done! Your drives are now ready and will mount automatically upon access."