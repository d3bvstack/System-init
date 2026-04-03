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

Side Effects:
- Rewrites `/etc/apt/sources.list`
- Installs and upgrades packages
- Enables `bluetooth` and `seatd`
- Adds target user to `video`, `render`, and `seat`
- Installs VS Code Insiders repository and package
- Performs cleanup and triggers reboot

Idempotency:
- Partially idempotent for package install/update steps
- Not fully idempotent because it rewrites apt sources and reboots unconditionally
- `group add seat` can fail if group already exists

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

## post-setup/hooks/30-install-labwc.sh

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
Install labwc from Debian repos or build latest tagged release from source, then deploy missing user config files.

Inputs and Invocation:
- Run as root via sudo from non-root account: `sudo ./scripts/install-labwc.sh`
- Interactive prompt selects installation mode unless `LABWC_INSTALL_MODE` environment variable is set
- Uses `SUDO_USER` to determine target user context

Required Environment:
- Root privileges and valid `SUDO_USER`
- `apt-get`, `apt-mark`, `git`, `meson`, `ninja`, `install`, `ldconfig`
- Network access to Debian repositories and `https://github.com/labwc/labwc`
- Optional: `LABWC_INSTALL_MODE` — When set to `package` or `source`, skips interactive prompt. Any other value causes script to exit with error.

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
- If `LABWC_INSTALL_MODE` not set, displays interactive prompt allowing user to select between `package` or `source` mode
- Package mode: installs `labwc` package through apt
- Source mode: installs build dependencies, clones/fetches `https://github.com/labwc/labwc`, resolves latest release tag using `git tag --sort=-v:refname`, checks out tag, builds with `meson`/`ninja`, installs with `ninja install`, calls `ldconfig`
- Source mode: configures Meson with `-Dxwayland=disabled`
- Source mode: if the correct wlroots version is not available on the system, Meson may automatically download the wlroots repository as a subproject
- Source mode: marks only newly-installed build dependencies as auto (preserves pre-existing manual installs), then runs `apt-get autoremove --purge -y`
- Deploys config files to `${XDG_CONFIG_HOME:-$HOME/.config}/labwc`: uses binary selection (not partial fallback) — if any candidate files exist in repo `.config/labwc`, copies matching files from there; otherwise, if zero files found in repo, attempts to copy matching files from `/usr/share/doc/labwc`
- Config files targeted: `rc.xml`, `menu.xml`, `autostart`, `shutdown`, `environment`, `themerc-override`
- Makes `autostart`, `shutdown`, and `environment` config files executable (chmod 755) after copying
- Never overwrites existing destination files
- Creates `/usr/local/src/labwc` directory if needed and clones source repository there

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
Detect unmounted EXT4/NTFS partitions and configure systemd automount entries.

Inputs and Invocation:
- Run via sudo from non-root account: `sudo ./scripts/automount-disks.sh`
- Uses `SUDO_USER` for UID/GID mapping; rejects direct root context

Required Environment:
- Root privileges
- `lsblk`, `grep`, `mount`, `umount`, `chown`, `systemctl`

Side Effects:
- Creates backup `/etc/fstab.backup.<timestamp>`
- Appends entries to `/etc/fstab` for eligible devices
- Creates mount directories under `/mnt`
- Temporarily mounts EXT4 volumes to set ownership
- Reloads systemd and restarts `local-fs.target`

Idempotency:
- Checks existing UUID entries in `/etc/fstab` before appending
- Generally idempotent for previously configured disks
- New disks produce new state changes

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
