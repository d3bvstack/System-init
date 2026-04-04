# Script Contracts Reference

This reference describes execution contracts for each script:

- Inputs and invocation mode
- Required environment and assumptions
- Side effects
- Idempotency characteristics

## scripts/setup.sh

Purpose:
Bootstrap a Debian 13 desktop baseline and reboot.

Inputs and Invocation:
- Run as root via sudo from a non-root account: `sudo ./scripts/setup.sh`
- Uses `SUDO_USER` when available to determine the target user context.

Required Environment:
- Debian 13 (Trixie)
- `apt-get`, `systemctl`, `wget`, `gpg`, `pam-auth-update`
- Network connectivity to Debian and Microsoft package repositories

Note:
- `initramfs-tools` is installed by the script before `update-initramfs` is invoked.

Side Effects:
- Rewrites `/etc/apt/sources.list`
- Installs and upgrades packages
- Enables `bluetooth` and `seatd`
- Writes `/etc/modprobe.d/btusb.conf` to disable `btusb` autosuspend
- Updates `/etc/initramfs-tools/initramfs.conf` to use `MODULES=dep`
- Rebuilds the current initramfs with `update-initramfs`
- Adds target user to `video`, `render`, and `seat`
- Installs VS Code Insiders repository and package
- Performs cleanup and triggers reboot

Idempotency:
- Partially idempotent for package install/update steps
- Not fully idempotent because it rewrites apt sources and reboots unconditionally
- `groupadd seat` can fail if the group already exists

## scripts/post-setup.sh

Purpose:
Run ordered post-reboot hooks and optional local extension hooks.

Inputs and Invocation:
- Run as root via sudo from non-root account: `sudo ./scripts/post-setup.sh`
- Expects repository layout on disk to resolve hook paths.

Required Environment:
- Local clone of repository
- Root permissions and valid `SUDO_USER`
- Shell utilities: `find`, `sort`, `bash`

Side Effects:
- Executes each configured hook in order
- Executes optional `/etc/post-setup.d/*.sh` hooks in lexicographic order
- Stops on first failing hook

Idempotency:
- Dispatcher itself is idempotent by control flow
- Effective idempotency depends on hook implementations

## post-setup/hooks/10-install-onboot-update.sh

Purpose:
Install updater script and systemd service.

Inputs and Invocation:
- Executed by dispatcher (or manually) as root
- Requires repository files:
  - `scripts/onboot-update.sh`
  - `systemd/onboot-update.service`

Required Environment:
- `install`, `systemctl`

Side Effects:
- Writes files to:
  - `/usr/local/sbin/onboot-update.sh`
  - `/etc/systemd/system/onboot-update.service`
- Runs `systemctl daemon-reload`
- Enables `onboot-update.service`

Idempotency:
- Mostly idempotent (reinstalling same files is safe)
- `enable` is idempotent

## post-setup/hooks/20-run-automount-disks.sh

Purpose:
Invoke disk automount configuration script.

Inputs and Invocation:
- Executed by dispatcher as root
- Requires repository file: `scripts/automount-disks.sh`

Required Environment:
- `bash`

Side Effects:
- Delegates all side effects to `scripts/automount-disks.sh`

Idempotency:
- Same idempotency profile as `scripts/automount-disks.sh`

## post-setup/hooks/30-install-docker.sh

Purpose:
Invoke Docker installer script.

Inputs and Invocation:
- Executed by dispatcher as root
- Requires repository file: `scripts/install-docker.sh`

Required Environment:
- `bash`

Side Effects:
- Delegates all side effects to `scripts/install-docker.sh`

Idempotency:
- Same idempotency profile as `scripts/install-docker.sh`

## post-setup/hooks/40-install-labwc.sh

Purpose:
Invoke labwc installer script.

Inputs and Invocation:
- Executed by dispatcher as root
- Requires repository file: `scripts/install-labwc.sh`

Required Environment:
- `bash`

Side Effects:
- Delegates all side effects to `scripts/install-labwc.sh`

Idempotency:
- Same idempotency profile as `scripts/install-labwc.sh`

## scripts/install-labwc.sh

Purpose:
Install labwc from Debian repos, build latest tagged release from source, or build/install a Debian package via Docker, then deploy missing user config files.

Inputs and Invocation:
- Run as root via sudo from non-root account: `sudo ./scripts/install-labwc.sh`
- Interactive prompt selects installation mode unless `LABWC_INSTALL_MODE` environment variable is set
- Interactive prompt asks how labwc should be installed and offers three choices: install the Debian package from apt, build and install the latest upstream release from source, or build a Debian package in Docker and install it on the host
- Uses `SUDO_USER` to determine target user context

Required Environment:
- Root privileges and valid `SUDO_USER`
- `apt-get`, `apt-mark`, `git`, `meson`, `ninja`, `install`, `ldconfig`
- Network access to Debian repositories and `https://github.com/labwc/labwc`
- Optional: `LABWC_INSTALL_MODE` — When set to `package`, `source`, or `docker-package`, skips interactive prompt. Any other value causes script to exit with error.
- Optional: `LABWC_DOCKER_IMAGE` — Overrides docker-package container image. Default is `debian:${VERSION_CODENAME}` resolved from host `/etc/os-release`. Empty value is rejected.
- Docker-package mode also requires Docker CLI availability, a reachable Docker daemon, and outbound access from the container to Debian package mirrors plus:
  - `https://github.com/labwc/labwc`
  - `https://gitlab.freedesktop.org/wlroots/wlroots`

Labwc Runtime Dependencies (Upstream Reference):
- wlroots, wayland, libinput, xkbcommon
- libxml2, cairo, pango, glib-2.0
- libpng
- Optional: librsvg >= 2.46, libsfdo, xwayland, xcb

Labwc Build Dependencies (Upstream Reference):
- meson, ninja, gcc/clang, wayland-protocols

Note: Source mode installs the Debian packages currently required to build labwc on this repository's target release, which may include more than the minimal upstream build set.

Build Dependencies (Source Mode Only):
The script installs and then removes the following packages when building from source:
- build-essential, git, meson, ninja-build, pkg-config, scdoc
- libwayland-dev, wayland-protocols, libwlroots-dev, libpixman-1-dev
- libxkbcommon-dev, libxml2-dev, libpango1.0-dev, libcairo2-dev

Note: Assume these package names are valid for Debian Trixie; verify availability for target release.

Side Effects:
- If `LABWC_INSTALL_MODE` is not set, displays an interactive prompt asking how labwc should be installed and allowing the user to select package, source, or docker-package mode
- Package mode: installs `labwc` package through apt
- Source mode: installs build dependencies, clones/fetches `https://github.com/labwc/labwc`, resolves latest release tag using `git tag --sort=-v:refname`, checks out tag, builds with `meson`/`ninja`, installs with `ninja install`, calls `ldconfig`
- Source mode: configures Meson with `-Dxwayland=disabled`
- Source mode: if the correct wlroots version is not available on the system, Meson may automatically download the wlroots repository as a subproject
- Source mode: marks only newly-installed build dependencies as auto (preserves pre-existing manual installs), then runs `apt-get autoremove --purge -y`
- Docker-package mode: builds a labwc `.deb` in a Debian container using `LABWC_DOCKER_IMAGE` when set, otherwise `debian:${VERSION_CODENAME}`; installs the resulting package on host; retains build artifacts at `/usr/local/src/labwc-docker-build/<timestamp>/` (including `labwc*.deb`)
- Docker-package mode: does not pre-install a fixed wlroots dev package name in container build deps
- Docker-package mode: after checking out latest labwc tag, parses `/tmp/labwc/meson.build` for `wlroots-X.Y`, maps that to `libwlroots-X.Y-dev`, and attempts distro package install
- Docker-package mode: if matching distro wlroots package is unavailable, clones `https://gitlab.freedesktop.org/wlroots/wlroots`, checks out ref `X.Y` (fallback `X.Y.0`), builds and installs wlroots in-container via meson+ninja, runs `ldconfig`, verifies pkg-config visibility, then proceeds with labwc build
- Docker-package mode: still builds the Debian package with `checkinstall` and installs that package on the host via apt
- Deploys config files to `${XDG_CONFIG_HOME:-$HOME/.config}/labwc`: if any candidate files exist in repo `.config/labwc`, copies matching files from there; otherwise, falls back to `/usr/share/doc/labwc` only when the `labwc` package is already installed and that directory exists
- Config files targeted: `rc.xml`, `menu.xml`, `autostart`, `shutdown`, `environment`, `themerc-override`
- Makes `autostart`, `shutdown`, and `environment` config files executable (chmod 755) after copying
- Never overwrites existing destination files
- Creates `/usr/local/src/labwc` directory if needed and clones source repository there

Operational caveat:
- `LABWC_DOCKER_IMAGE` should point to a trusted Debian-compatible image source to reduce supply-chain risk.

Idempotency:
- Package mode is mostly idempotent via apt
- Source mode reinstalls the latest tag and is repeatable but not strictly no-op (re-runs build, reinstalls binary)
- Config deployment is idempotent because existing files are preserved and skipped

## scripts/onboot-update.sh

Purpose:
Run apt maintenance with a 12-hour debounce.

Inputs and Invocation:
- Intended to run under systemd service
- No command-line arguments

Required Environment:
- Root privileges
- `apt-get`, `find`, writable `/var/lib/local-updates`

Side Effects:
- Updates apt cache and performs full upgrade
- Runs autoremove and clean
- Updates timestamp file at `/var/lib/local-updates/last-update.stamp`

Idempotency:
- Debounced by modification time of stamp file
- Safe to trigger repeatedly; no-op when within cooldown

## scripts/automount-disks.sh

Purpose:
Detect eligible EXT4/NTFS partitions and configure systemd automount entries.

Inputs and Invocation:
- Run via sudo from non-root account: `sudo ./scripts/automount-disks.sh`
- Uses `SUDO_USER` for UID/GID mapping; rejects direct root context

Required Environment:
- Root privileges
- `findmnt`, `lsblk`, `grep`, `mount`, `umount`, `chown`, `systemctl`
- systemd as PID 1

Side Effects:
- Creates backup `/etc/fstab.backup.<timestamp>`
- Adds or updates entries in `/etc/fstab` for eligible devices
- Creates mount directories under `/mnt`
- Enforces EXT4 mount-root ownership for managed disks on every run (including disks already mounted at their expected managed path)
- Maps NTFS ownership with `uid=`, `gid=`, and `umask=022`
- Uses `ntfs3` when available, otherwise `ntfs-3g` when helpers are found (`/sbin/mount.ntfs-3g`, `/usr/sbin/mount.ntfs-3g`, `/sbin/mount.ntfs`, `/usr/sbin/mount.ntfs`, then `command -v` fallback)
- Warns once when neither `ntfs3` nor `ntfs-3g` support is available, then skips NTFS volumes
- Skips devices already mounted somewhere other than their expected managed mount path, with an informational message
- Reloads systemd daemon state after changes

Idempotency:
- Checks existing UUID entries in `/etc/fstab` before appending
- Generally idempotent for previously configured disks; EXT4 ownership repair may still run without changing `/etc/fstab`
- New disks produce new state changes

## scripts/install-docker.sh

Purpose:
Install Docker Engine and plugins from Docker's official apt repository.

Inputs and Invocation:
- Run from repository root with elevated privileges: `sudo ./scripts/install-docker.sh`
- Script can also run as root directly, but sudo invocation is preferred for consistency with repository usage patterns
- Reads `/etc/os-release` and uses `VERSION_CODENAME` to write the Docker apt source stanza

Required Environment:
- Root privileges
- Debian family host with `/etc/os-release`
- `apt-get`, `curl`, `dpkg`, `install`, `chmod`, `systemctl`
- Network connectivity to Debian package mirrors and `https://download.docker.com`

Side Effects:
- Runs `apt-get update` before dependency install and again after writing Docker source metadata
- Installs `ca-certificates` and `curl` if missing
- Writes the Docker GPG key to `/etc/apt/keyrings/docker.asc`
- Writes `/etc/apt/sources.list.d/docker.sources`
- Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`
- Does not modify user group membership (`docker` group access is out of scope)
- Does not force-enable or force-start Docker service; runtime state follows package/system defaults

Idempotency:
- Re-running refreshes key/source files to the same target paths and re-runs apt metadata refresh
- Package installation is apt-managed and safe to repeat
- Expected repeat-run changes are limited to package manager refresh/install behavior

## systemd/onboot-update.service

Purpose:
Define updater execution policy and hardening.

Inputs and Invocation:
- Installed as a system service and enabled for boot

Required Environment:
- `/usr/local/sbin/onboot-update.sh` present and executable
- systemd with network-online target available

Side Effects:
- Runs updater script at boot sequence (`multi-user.target`)
- Applies CPU/IO niceness and filesystem hardening constraints

Idempotency:
- Service file itself is declarative
- Runtime idempotency depends on `onboot-update.sh` debounce logic
