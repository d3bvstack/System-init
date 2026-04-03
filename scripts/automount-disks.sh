#!/usr/bin/env bash
# Purpose: Configure automount entries for unmounted ext4 and NTFS disks on systemd hosts.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: This script must be run with sudo/root privileges."
    exit 1
fi

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

if ! command -v findmnt >/dev/null 2>&1; then
    echo "ERROR: Missing required command: findmnt"
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo "ERROR: Missing required command: systemctl"
    exit 1
fi

if [[ "$(cat /proc/1/comm 2>/dev/null || true)" != "systemd" ]]; then
    echo "ERROR: PID 1 is not systemd. Refusing to modify /etc/fstab in this environment."
    exit 1
fi

sanitize_mount_label() {
    local raw_label="$1"
    local sanitized

    sanitized=$(printf '%s' "$raw_label" \
        | tr '[:space:]' '_' \
        | sed -E 's/[^[:alnum:]_.-]/_/g; s/_+/_/g; s/^[-_.]+//; s/[-_.]+$//')

    if [[ -z "$sanitized" ]]; then
        sanitized="disk"
    fi

    printf '%s' "$sanitized"
}

get_ntfs_fstype() {
    if grep -qw ntfs3 /proc/filesystems; then
        printf '%s' "ntfs3"
        return 0
    fi

    if command -v mount.ntfs-3g >/dev/null 2>&1 || command -v mount.ntfs >/dev/null 2>&1; then
        printf '%s' "ntfs-3g"
        return 0
    fi

    return 1
}

FSTAB_BACKUP_DONE=0
CHANGES_APPLIED=0

ensure_fstab_backup() {
    if [[ "$FSTAB_BACKUP_DONE" -eq 0 ]]; then
        cp /etc/fstab "/etc/fstab.backup.$(date +%F_%T)"
        FSTAB_BACKUP_DONE=1
        echo ">> Backup of /etc/fstab created."
    fi
}

looks_like_linux_root() {
    local dev="$1"
    local probe_dir

    probe_dir=$(mktemp -d /tmp/automount-probe.XXXXXX)

    # Probe read-only to avoid changing metadata while inspecting contents.
    if ! mount -o ro,noload "$dev" "$probe_dir" >/dev/null 2>&1; then
        rmdir "$probe_dir" >/dev/null 2>&1 || true
        return 1
    fi

    if [[ -d "$probe_dir/etc" && -d "$probe_dir/usr" ]] && \
       [[ -f "$probe_dir/etc/os-release" || -f "$probe_dir/etc/fstab" || -d "$probe_dir/var/lib/dpkg" ]]; then
        umount "$probe_dir" >/dev/null 2>&1 || true
        rmdir "$probe_dir" >/dev/null 2>&1 || true
        return 0
    fi

    umount "$probe_dir" >/dev/null 2>&1 || true
    rmdir "$probe_dir" >/dev/null 2>&1 || true
    return 1
}

set_ext4_mount_owner() {
    local dev="$1"
    local mount_dir="$2"
    local owner_uid="$3"
    local owner_gid="$4"

    if ! mount "$dev" "$mount_dir"; then
        echo "ERROR: Failed to mount $dev on $mount_dir for ownership setup."
        return 1
    fi

    if ! chown "$owner_uid":"$owner_gid" "$mount_dir"; then
        echo "ERROR: Failed to set ownership on $mount_dir."
        umount "$mount_dir" >/dev/null 2>&1 || true
        return 1
    fi

    if ! umount "$mount_dir"; then
        echo "ERROR: Failed to unmount $mount_dir after ownership setup."
        return 1
    fi

    return 0
}

upsert_fstab_entry() {
    local uuid="$1"
    local entry="$2"
    local fstab_tmp
    local action
    local existing

    existing=$(awk -v uuid_key="UUID=$uuid" '$1 == uuid_key { print; exit }' /etc/fstab)
    if [[ -n "$existing" && "$existing" == "$entry" ]]; then
        printf '%s' "unchanged"
        return 0
    fi

    ensure_fstab_backup
    fstab_tmp=$(mktemp /etc/fstab.tmp.XXXXXX)

    if [[ -n "$existing" ]]; then
        action="updated"
        awk -v uuid_key="UUID=$uuid" -v new_entry="$entry" '
            BEGIN { replaced = 0 }
            $1 == uuid_key {
                if (!replaced) {
                    print new_entry
                    replaced = 1
                }
                next
            }
            { print }
        ' /etc/fstab > "$fstab_tmp"
    else
        action="added"
        cat /etc/fstab > "$fstab_tmp"
        printf '%s\n' "$entry" >> "$fstab_tmp"
    fi

    if ! findmnt --verify --tab-file "$fstab_tmp" >/dev/null 2>&1; then
        rm -f "$fstab_tmp"
        echo "ERROR: Generated /etc/fstab content failed validation for UUID=$uuid."
        exit 1
    fi

    chmod --reference=/etc/fstab "$fstab_tmp"
    chown --reference=/etc/fstab "$fstab_tmp"
    mv "$fstab_tmp" /etc/fstab

    CHANGES_APPLIED=1
    printf '%s' "$action"
}

NTFS_FSTYPE=""
if ! NTFS_FSTYPE=$(get_ntfs_fstype); then
    echo "ERROR: Neither ntfs3 kernel support nor ntfs-3g userspace support is available."
    exit 1
fi

# Scan block devices in key-value mode so labels with spaces parse reliably.
while IFS= read -r line; do
    DEV=""
    FSTYPE=""
    UUID=""
    LABEL=""
    MOUNTPOINT=""
    re_path='PATH="([^"]*)"'
    re_fstype='FSTYPE="([^"]*)"'
    re_uuid='UUID="([^"]*)"'
    re_label='LABEL="([^"]*)"'
    re_mountpoint='MOUNTPOINT="([^"]*)"'

    # Extract values from lsblk key="value" pairs.
    [[ "$line" =~ $re_path ]] && DEV="${BASH_REMATCH[1]}"
    [[ "$line" =~ $re_fstype ]] && FSTYPE="${BASH_REMATCH[1]}"
    [[ "$line" =~ $re_uuid ]] && UUID="${BASH_REMATCH[1]}"
    [[ "$line" =~ $re_label ]] && LABEL="${BASH_REMATCH[1]}"
    [[ "$line" =~ $re_mountpoint ]] && MOUNTPOINT="${BASH_REMATCH[1]}"

    # Skip devices without UUIDs and anything already mounted.
    if [ -z "$UUID" ] || [ -n "$MOUNTPOINT" ]; then
        continue
    fi

    # Build mount directory name from label when present, otherwise UUID.
    if [ -n "$LABEL" ]; then
        SAFE_LABEL=$(sanitize_mount_label "$LABEL")
        MOUNT_DIR="/mnt/${SAFE_LABEL}-${UUID:0:8}"
    else
        SAFE_LABEL="disk_$(basename "$DEV")"
        MOUNT_DIR="/mnt/${SAFE_LABEL}-${UUID:0:8}"
    fi

    if [[ -e "$MOUNT_DIR" && ! -d "$MOUNT_DIR" ]]; then
        echo "ERROR: Mount path exists and is not a directory: $MOUNT_DIR"
        exit 1
    fi

    if findmnt --mountpoint "$MOUNT_DIR" >/dev/null 2>&1; then
        echo ">> Skipping $DEV - mount point $MOUNT_DIR is already in use."
        continue
    fi

    # Write filesystem-specific automount entries.
    if [[ "$FSTYPE" == "ext4" ]]; then
        if looks_like_linux_root "$DEV"; then
            echo ">> Skipping $DEV - detected Linux root-like filesystem layout."
            continue
        fi

        echo ">> Found EXT4 drive on $DEV. Configuring automount..."
        mkdir -p "$MOUNT_DIR"

        # Mount on access, do not mount at boot, and unmount after idle timeout.
        FSTAB_ENTRY="UUID=$UUID  $MOUNT_DIR  ext4  defaults,noatime,nofail,noauto,users,x-systemd.automount,x-systemd.idle-timeout=15min,x-gvfs-show,x-gvfs-name=$SAFE_LABEL  0  0"
        UPSERT_RESULT=$(upsert_fstab_entry "$UUID" "$FSTAB_ENTRY")
        if [[ "$UPSERT_RESULT" == "added" ]]; then
            # Mount briefly to set the mount root ownership, then unmount.
            if ! set_ext4_mount_owner "$DEV" "$MOUNT_DIR" "$ACTUAL_UID" "$ACTUAL_GID"; then
                exit 1
            fi
        fi
        if [[ "$UPSERT_RESULT" != "unchanged" ]]; then
            echo ">> ${UPSERT_RESULT^} /etc/fstab entry for UUID=$UUID."
        fi

    elif [[ "$FSTYPE" == "ntfs" || "$FSTYPE" == "ntfs3" ]]; then
        echo ">> Found NTFS drive on $DEV. Configuring automount..."
        mkdir -p "$MOUNT_DIR"

        # Use the available NTFS driver and map file ownership to the target user.
        FSTAB_ENTRY="UUID=$UUID  $MOUNT_DIR  $NTFS_FSTYPE  defaults,noatime,uid=$ACTUAL_UID,gid=$ACTUAL_GID,umask=022,nofail,noauto,users,x-systemd.automount,x-systemd.idle-timeout=15min,x-gvfs-show,x-gvfs-name=$SAFE_LABEL  0  0"
        UPSERT_RESULT=$(upsert_fstab_entry "$UUID" "$FSTAB_ENTRY")
        if [[ "$UPSERT_RESULT" != "unchanged" ]]; then
            echo ">> ${UPSERT_RESULT^} /etc/fstab entry for UUID=$UUID."
        fi
    fi
done < <(lsblk -n -p -P -o PATH,FSTYPE,UUID,LABEL,MOUNTPOINT)

if [[ "$CHANGES_APPLIED" -eq 1 ]]; then
    # Reload systemd so it recognizes newly created automount units.
    echo ">> Reloading systemd daemons..."
    systemctl daemon-reload
else
    echo ">> No /etc/fstab changes were required."
fi

echo ">> Done! Your drives are now ready and will mount automatically upon access."