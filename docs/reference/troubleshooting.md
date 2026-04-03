# Failure Modes and Troubleshooting

This guide covers common failures for the setup flow and how to recover safely.

## Stage 1: scripts/setup.sh

### Failure: apt update or upgrade fails
Symptoms:
- Errors during `apt-get update` or `apt-get full-upgrade -y`

Likely Causes:
- No network connectivity
- Repository mirror outage
- Interrupted dpkg state

Troubleshooting:
```bash
sudo apt-get update
sudo dpkg --configure -a
sudo apt-get -f install
sudo apt-get full-upgrade -y
```

### Failure: group creation fails for seat
Symptoms:
- `groupadd`/`group add` reports group already exists or command mismatch

Likely Causes:
- Group already exists
- Script line uses distro-specific command syntax

Troubleshooting:
```bash
getent group seat
sudo usermod -aG video,render,seat "$USER"
```

### Failure: code-insiders install fails
Symptoms:
- Package not found or repository key/source errors

Likely Causes:
- Microsoft repo unreachable
- keyring file missing or unreadable

Troubleshooting:
```bash
ls -l /usr/share/keyrings/microsoft.gpg
cat /etc/apt/sources.list.d/vscode.sources
sudo apt-get update
sudo apt-get install -y code-insiders
```

## Stage 2: scripts/post-setup.sh

### Failure: script rejects execution context
Symptoms:
- Error asking for sudo or non-root account execution

Likely Causes:
- Script launched as root shell without `SUDO_USER`

Troubleshooting:
```bash
whoami
echo "$SUDO_USER"
sudo ./scripts/post-setup.sh
```

### Failure: missing hook/source files
Symptoms:
- Hook reports missing `scripts/...` or `systemd/...` files

Likely Causes:
- Running dispatcher or hook remotely without repository layout
- Incomplete clone or wrong working directory

Troubleshooting:
```bash
pwd
ls -la scripts post-setup/hooks systemd
sudo ./scripts/post-setup.sh
```

### Failure: local extension hook breaks dispatcher
Symptoms:
- Dispatcher stops during `/etc/post-setup.d/*.sh`

Likely Causes:
- Extension hook exits non-zero
- Syntax/runtime error in local hook

Troubleshooting:
```bash
sudo bash -n /etc/post-setup.d/*.sh
sudo bash -x /etc/post-setup.d/<failing-hook>.sh
```

## scripts/automount-disks.sh

### Failure: no disks configured
Symptoms:
- Script completes but no new fstab entries are added

Likely Causes:
- No unmounted EXT4/NTFS disks detected
- Existing UUIDs already present in `/etc/fstab`

Troubleshooting:
```bash
lsblk -f
grep -E 'UUID=.*(ext4|ntfs|ntfs3)' /etc/fstab
```

### Failure: mount or ownership operations fail
Symptoms:
- Errors during temporary mount, `chown`, or unmount

Likely Causes:
- Filesystem issues
- Mountpoint conflicts
- Permission/context mismatch

Troubleshooting:
```bash
sudo dmesg | tail -n 50
sudo mount | grep /mnt/
sudo fsck -N /dev/<device>
```

### Recovery: restore fstab backup
If a generated entry is incorrect, restore backup and reload:

```bash
ls -1 /etc/fstab.backup.* | tail -n 3
sudo cp /etc/fstab.backup.<timestamp> /etc/fstab
sudo systemctl daemon-reload
sudo systemctl restart local-fs.target
```

## scripts/onboot-update.sh and onboot-update.service

### Failure: updater does not run at boot
Symptoms:
- No recent logs from unit

Likely Causes:
- Service not enabled
- Script not installed or not executable

Troubleshooting:
```bash
systemctl is-enabled onboot-update.service
systemctl status onboot-update.service
ls -l /usr/local/sbin/onboot-update.sh
```

### Failure: updater runs but immediately skips
Symptoms:
- Log says update was performed less than 12 hours ago

Likely Causes:
- Debounce window active

Troubleshooting:
```bash
sudo stat /var/lib/local-updates/last-update.stamp
sudo journalctl -u onboot-update.service -n 50 --no-pager
```

## Diagnostics Checklist

When reporting an issue, include:

- Command run and full stderr output
- Current user context (`whoami`, `echo "$SUDO_USER"`)
- Current branch/commit
- Relevant logs:

```bash
sudo journalctl -u onboot-update.service -n 100 --no-pager
sudo tail -n 200 /var/log/apt/history.log
```
