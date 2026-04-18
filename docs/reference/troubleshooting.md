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

### Failure: seat group already exists
Symptoms:
- `groupadd seat` exits non-zero because the group already exists

Likely Causes:
- The `seat` group was created by a previous setup run or is pre-created on the base image

Troubleshooting:
```bash
getent group seat
sudo groupadd -f seat
sudo ./scripts/setup.sh
```

### Failure: boot-time fixes do not rebuild
Symptoms:
- `update-initramfs` exits non-zero
- The initramfs still reflects the old module policy after setup
- `btusb` autosuspend does not appear disabled in the new boot environment

Likely Causes:
- `initramfs-tools` is missing or broken
- The current kernel image is not installed correctly
- The `btusb` module is not loaded yet, so the runtime sysfs parameter is absent

Troubleshooting:
```bash
command -v update-initramfs
grep -n '^MODULES=' /etc/initramfs-tools/initramfs.conf
ls /sys/module/btusb/parameters/ 2>/dev/null
sudo update-initramfs -u -k "$(uname -r)"
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
- Devices are already mounted at non-managed paths and were skipped by design
- The current mount point is already occupied or invalid
- NTFS disks were detected but the host does not provide `ntfs3` or `ntfs-3g`, so they were skipped with a warning

Troubleshooting:
```bash
lsblk -f
grep -E 'UUID=.*(ext4|ntfs|ntfs3)' /etc/fstab
findmnt --mountpoint "/mnt/your-mount-point"
```

Expected informational output can include skip messages such as:
- `Skipping /dev/... - mounted at /boot/efi (expected managed path: /mnt/...)`
- `Skipping /dev/... - mounted at / (expected managed path: /mnt/...)`
- `Skipping /dev/... - mounted at /run/media/... (expected managed path: /mnt/...)`

These are normal when the partition is already mounted elsewhere (for example system partitions or LVM-backed filesystems mounted by the OS).

### Warning: NTFS disks skipped
Symptoms:
- Script reports that NTFS support is unavailable

Likely Causes:
- The kernel lacks `ntfs3`
- The `ntfs-3g` userspace helper is not installed
- Helper binaries exist only in non-standard locations that are not in probe paths/PATH

Troubleshooting:
```bash
command -v mount.ntfs-3g || command -v mount.ntfs
grep -qw ntfs3 /proc/filesystems
```

The script checks for helpers in this order:
1. `/sbin/mount.ntfs-3g`
2. `/usr/sbin/mount.ntfs-3g`
3. `/sbin/mount.ntfs`
4. `/usr/sbin/mount.ntfs`
5. `command -v mount.ntfs-3g` or `command -v mount.ntfs`

If your distro installs helpers in a different location, add that location to `PATH` for the sudo environment or install/link the helper in a standard `sbin` path.

### Recovery: legacy NTFS entry still uses `users`
Symptoms:
- A desktop file manager shows a permission error when opening a managed NTFS mount created by an older script version
- Journal entries include: `Error opening read-only '/dev/sdb1': Permission denied`

Likely Causes:
- An older or manually edited NTFS `/etc/fstab` entry still contains `users`; current automount runs no longer generate that option

Troubleshooting:
```bash
grep -nE 'UUID=.*ntfs-3g' /etc/fstab
journalctl -b -n 120 --no-pager | grep -E 'sdb1|ntfs|Permission denied|Unknown error when mounting'
```

Recovery:
```bash
# Regenerate managed entries with the current NTFS options.
sudo ./scripts/automount-disks.sh

# If needed, adjust an existing legacy entry manually by removing only the `users` token.
sudo sed -i 's/,users,/,/g; s/,users / /g; s/ users,/ /g' /etc/fstab

sudo systemctl daemon-reload
sudo systemctl restart local-fs.target
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

For EXT4, the script intentionally sets mount-root ownership on each run. If access fails with `Permission denied` because the mount root is owned by `root:root`, rerun:

```bash
sudo ./scripts/automount-disks.sh
```

If the disk is mounted at its expected managed path, the script repairs ownership in place. If it is mounted somewhere else, the script skips it and prints an informational message; unmount/remount to the managed path and rerun.

### Failure: mount path exists but is not a directory
Symptoms:
- Script exits with `Mount path exists and is not a directory`

Likely Causes:
- A stale file or symlink already occupies the generated `/mnt/...` mount path
- Manual cleanup left behind a non-directory placeholder

Troubleshooting:
```bash
ls -ld "/mnt/<mount-path-from-error>"
sudo rm -f "/mnt/<mount-path-from-error>"
sudo ./scripts/automount-disks.sh
```

### Failure: generated /etc/fstab content fails validation
Symptoms:
- Script exits with `Generated /etc/fstab content failed validation for UUID=...`

Likely Causes:
- Existing manual edits left `/etc/fstab` in an invalid state
- A conflicting entry or malformed option line was already present

Troubleshooting:
```bash
sudo findmnt --verify --tab-file /etc/fstab
sudo cp /etc/fstab.backup.<timestamp> /etc/fstab
sudo systemctl daemon-reload
sudo systemctl restart local-fs.target
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

### Failure: install-docker rejects execution context or missing codename
Symptoms:
- Script asks for sudo/root privileges
- Script exits because `/etc/os-release` cannot be read or `VERSION_CODENAME` is empty

Likely Causes:
- Script was run without root privileges
- Host is not a Debian-style system release
- `/etc/os-release` is missing or malformed

Troubleshooting:
```bash
whoami
cat /etc/os-release
sudo ./scripts/install-docker.sh
```

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

## scripts/install-vscode.sh

### Failure: VS Code repository setup or install fails
Symptoms:
- Package not found or repository key/source errors
- Errors during GPG key download or apt update

Likely Causes:
- Microsoft repository unreachable
- Keyring file missing or unreadable
- Network connectivity issues

Troubleshooting:
```bash
ls -l /usr/share/keyrings/microsoft.gpg
cat /etc/apt/sources.list.d/vscode.sources
wget -qO- https://packages.microsoft.com/keys/microsoft.asc
sudo apt-get update
sudo apt-get install -y code-insiders
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

### Failure: no configs copied
Symptoms:
- Install succeeds but expected files are missing under `${XDG_CONFIG_HOME:-$HOME/.config}/labwc`

Likely Causes:
- No matching files exist in repo `.config/labwc`
- The `labwc` package is not installed yet, so `/usr/share/doc/labwc` is unavailable
- The installed `labwc` package does not ship the expected default files for this release

Troubleshooting:
```bash
ls -la .config/labwc
apt-cache policy labwc
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

### Failure: LABWC_DOCKER_IMAGE is set but empty
Symptoms:
- Script exits with `LABWC_DOCKER_IMAGE is set but empty.`

Likely Causes:
- A wrapper script or shell profile exported an empty override value
- CI or manual invocation passed `LABWC_DOCKER_IMAGE=` without a value

Troubleshooting:
```bash
env | grep '^LABWC_DOCKER_IMAGE='
unset LABWC_DOCKER_IMAGE
sudo ./scripts/install-labwc.sh
```

### Failure: docker-package mode cannot start Docker build
Symptoms:
- Docker-based build exits early before package build steps complete

Likely Causes:
- Docker CLI is not installed or not in PATH
- Docker daemon is not reachable
- Host `/etc/os-release` is missing or does not define `VERSION_CODENAME`

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

### Failure: docker-package latest tag fails due wlroots ABI mismatch
Symptoms:
- Docker-package mode reaches Meson configure/build for labwc, then fails with wlroots package/version errors
- Output indicates missing pkg-config entry for `wlroots-X.Y` or missing `libwlroots-X.Y-dev`

Likely Causes:
- Latest labwc tag requires a wlroots ABI not packaged in the selected container image
- Upstream `meson.build` format changed and the wlroots ABI parser could not extract `wlroots-X.Y`
- wlroots source fallback checkout fails for both `X.Y` and `X.Y.0` refs
- wlroots source build/install completed but required pkg-config name is still not visible

Troubleshooting:
```bash
# Re-run in docker-package mode and capture logs
sudo LABWC_INSTALL_MODE=docker-package ./scripts/install-labwc.sh 2>&1 | tee /tmp/labwc-docker-build.log

# Inspect detected ABI and wlroots steps in log
grep -E 'wlroots-|libwlroots|pkg-config|checkout -f' /tmp/labwc-docker-build.log

# If image is too old/new for required ABI, try a different Debian-compatible image
sudo LABWC_INSTALL_MODE=docker-package LABWC_DOCKER_IMAGE=debian:trixie ./scripts/install-labwc.sh
```

### Failure: Docker-package build completes but no .deb is emitted
Symptoms:
- Script exits with `Docker build completed but no labwc .deb package was found in $build_dir.`

Likely Causes:
- `checkinstall` did not emit a package into the mounted artifacts directory
- The container build failed after compilation but before packaging
- The artifact volume was unavailable or the output path was changed

Troubleshooting:
```bash
find /usr/local/src/labwc-docker-build -maxdepth 2 -type f \( -name 'labwc*.deb' -o -name '*.log' \)
sudo LABWC_INSTALL_MODE=docker-package ./scripts/install-labwc.sh
```

Operational note:
- The script already handles ABI detection and source fallback automatically. Persistent failure usually indicates mirror/network restrictions, missing source-build prerequisites in the image, or upstream ref availability issues.

### Failure: container image pull blocked; use LABWC_DOCKER_IMAGE mirror
Symptoms:
- Docker-package mode fails before build steps with image pull/auth/network errors
- Default image `debian:${VERSION_CODENAME}` cannot be pulled from current environment

Likely Causes:
- Registry egress restrictions or DNS/proxy policy blocks default registry path
- Environment requires an internal or mirrored registry endpoint

Troubleshooting:
```bash
# Verify daemon access first
docker info

# Test pull from your approved mirror image
sudo docker pull mirror.gcr.io/library/debian:trixie

# Re-run using mirror override
sudo LABWC_INSTALL_MODE=docker-package \
	LABWC_DOCKER_IMAGE=mirror.gcr.io/library/debian:trixie \
	./scripts/install-labwc.sh
```

Security/operational caveat:
- Use only trusted, Debian-compatible mirror images. Untrusted images can change build inputs and package contents.

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
