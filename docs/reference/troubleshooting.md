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

### Failure: post-setup dispatcher rejects execution context
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

### Failure: script exits immediately
Symptoms:
- Error about missing `findmnt` or `systemctl`
- Error saying PID 1 is not systemd
- Error refusing direct root execution

Likely Causes:
- Required util-linux or systemd tooling is missing
- The host was booted without systemd
- The script was launched as root instead of via `sudo` from a normal user account

Troubleshooting:
```bash
command -v findmnt
command -v systemctl
cat /proc/1/comm
whoami
echo "$SUDO_USER"
```

### Failure: no disks configured
Symptoms:
- Script completes but no new fstab entries are added

Likely Causes:
- No unmounted EXT4/NTFS disks detected
- Existing UUIDs already present in `/etc/fstab`
- The current mount point is already occupied or invalid

Troubleshooting:
```bash
lsblk -f
grep -E 'UUID=.*(ext4|ntfs|ntfs3)' /etc/fstab
findmnt --mountpoint "/mnt/your-mount-point"
```

### Failure: mount or ownership operations fail
Symptoms:
- Errors during temporary mount, `chown`, or unmount

Likely Causes:
- Filesystem issues
- Mountpoint conflicts
- Permission/context mismatch
- The ext4 volume is already mounted elsewhere

Troubleshooting:
```bash
sudo dmesg | tail -n 50
sudo mount | grep /mnt/
sudo fsck -N /dev/<device>
findmnt --mountpoint "/mnt/your-mount-point"
```

### Recovery: restore fstab backup
If a generated entry is incorrect, restore backup and reload:

```bash
ls -1 /etc/fstab.backup.* | tail -n 3
sudo cp /etc/fstab.backup.<timestamp> /etc/fstab
sudo systemctl daemon-reload
sudo systemctl restart local-fs.target
```

## scripts/install-docker.sh

### Failure: Docker repository setup or package install fails
Symptoms:
- Errors during key download, apt update, or package installation

Likely Causes:
- Network access to `download.docker.com` is blocked or unavailable
- Host codename in `/etc/os-release` does not match the Debian release you intended to target
- `curl` or apt prerequisites are missing or stale

Troubleshooting:
```bash
cat /etc/os-release
sudo apt-get update
sudo apt-get install -y ca-certificates curl
curl -I https://download.docker.com/linux/debian/gpg
sudo ./scripts/install-docker.sh
```

### Failure: Docker daemon is not running
Symptoms:
- `systemctl status docker` shows inactive, failed, or missing service state

Likely Causes:
- Service did not start automatically
- systemd is not available in the current environment
- Installation completed but the daemon hit a startup error

Troubleshooting:
```bash
sudo systemctl start docker
sudo systemctl status docker --no-pager
sudo journalctl -u docker -n 50 --no-pager
```

### Failure: hello-world verification fails
Symptoms:
- `docker run hello-world` cannot pull or run the test image

Likely Causes:
- Docker daemon is not running
- Networking or DNS issues block image pulls
- User is not allowed to talk to the daemon without sudo

Troubleshooting:
```bash
sudo docker run hello-world
sudo systemctl status docker --no-pager
docker info
```

## scripts/install-labwc.sh

### Failure: install-labwc rejects execution context
Symptoms:
- Error asking to run with sudo from a non-root account

Likely Causes:
- Direct root shell execution without `SUDO_USER`

Troubleshooting:
```bash
whoami
echo "$SUDO_USER"
sudo ./scripts/install-labwc.sh
```

### Failure: package mode cannot install labwc
Symptoms:
- `apt-get install -y labwc` fails

Likely Causes:
- Package unavailable in configured repositories
- Apt cache stale or network issues

Troubleshooting:
```bash
apt-cache policy labwc
sudo apt-get update
sudo apt-get install -y labwc
```

### Failure: source mode build fails
Symptoms:
- Build stops during Meson configure or Ninja compile

Likely Causes:
- Missing or mismatched build dependencies
- Required wlroots version not present on the system and network access blocked for Meson subproject download
- Upstream source changes

Troubleshooting:
```bash
sudo apt-get install -y --no-install-recommends build-essential meson ninja-build pkg-config scdoc wayland-protocols
sudo apt-get -f install
sudo ./scripts/install-labwc.sh
```

### Failure: xwayland-disabled build still pulls X11-related errors
Symptoms:
- Meson configure fails around optional X11 support or xwayland symbols

Likely Causes:
- Outdated build directory from previous configuration
- Source tree configured before xwayland was disabled

Troubleshooting:
```bash
rm -rf /usr/local/src/labwc/build
sudo ./scripts/install-labwc.sh
```

### Failure: no configs copied
Symptoms:
- Install succeeds but expected files are missing under `${XDG_CONFIG_HOME:-$HOME/.config}/labwc`

Likely Causes:
- No matching files in repo `.config/labwc`
- `/usr/share/doc/labwc` does not include expected defaults for current package version

Troubleshooting:
```bash
ls -la .config/labwc
ls -la /usr/share/doc/labwc
ls -la "${XDG_CONFIG_HOME:-$HOME/.config}/labwc"
```

### Failure: LABWC_INSTALL_MODE set to invalid value
Symptoms:
- Script exits immediately with error message

Likely Causes:
- Environment variable set to value other than `package`, `source`, or `docker-package`

Troubleshooting:
```bash
echo "$LABWC_INSTALL_MODE"
unset LABWC_INSTALL_MODE
sudo ./scripts/install-labwc.sh
```

### Failure: docker-package mode cannot start Docker build
Symptoms:
- Docker-based build exits early before package build steps complete

Likely Causes:
- Docker CLI is not installed or not in PATH
- Docker daemon is not reachable

Troubleshooting:
```bash
command -v docker
docker version
sudo systemctl status docker --no-pager
sudo systemctl start docker
```

### Failure: docker-package mode fails during container apt or source fetch
Symptoms:
- Docker build starts, then fails while installing build dependencies or cloning labwc

Likely Causes:
- No network egress from host/container to Debian mirrors
- No network egress from host/container to `https://github.com/labwc/labwc`

Troubleshooting:
```bash
docker run --rm debian:trixie apt-get update
curl -I https://github.com/labwc/labwc
sudo ./scripts/install-labwc.sh
```

### Failure: Git tag resolution or clone fails
Symptoms:
- Error during `git clone`, `git fetch`, or tag resolution in source mode

Likely Causes:
- Network issues accessing `https://github.com/labwc/labwc`
- No network connectivity
- GitHub repository unavailable or access blocked

Troubleshooting:
```bash
ping github.com
git ls-remote https://github.com/labwc/labwc | head -20
rm -rf /usr/local/src/labwc
sudo ./scripts/install-labwc.sh
```

### Failure: /usr/local/src/labwc corrupted or stale
Symptoms:
- Build fails with checkout, configure, or compile errors despite clean dependency install

Likely Causes:
- Previous interrupted build left incomplete files
- Source tree in inconsistent state

Troubleshooting:
```bash
sudo rm -rf /usr/local/src/labwc
sudo ./scripts/install-labwc.sh
```

### Failure: Build cleanup (apt-mark/autoremove) fails or behaves unexpectedly
Symptoms:
- Source build completes but `apt-get autoremove --purge` reports errors or removes unexpected packages

Likely Causes:
- Some build dependencies already manually installed before script run
- System dependency resolver mismatch

Troubleshooting:
```bash
apt-mark showmanual | grep -E 'meson|ninja-build|libwayland|wlroots|libxkbcommon'
sudo apt-get -s autoremove
sudo apt-mark manual <package-name>  # Re-mark if needed
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
