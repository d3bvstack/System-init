# Debian 13 (Trixie) Post-Install and System Initialization

This README is a how-to guide with quick orientation.

The setup flow has two stages:

1. `scripts/setup.sh` performs the base system bootstrap and reboots.
2. `scripts/post-setup.sh` runs post-reboot tasks through ordered hooks.

Deep behavior details are in the reference documents linked at the end of this file.

## Table of Contents

- [Quick Orientation](#1-quick-orientation)
- [Prerequisites](#2-prerequisites)
- [Stage One: Base Setup](#3-stage-one-base-setup)
- [Stage Two: Post-Setup Dispatcher](#4-stage-two-post-setup-dispatcher)
- [Extending Post-Setup](#5-extending-post-setup)
- [Remote Bootstrap (No Clone)](#6-remote-bootstrap-no-clone)
- [Trust and Integrity](#7-trust-and-integrity)
- [Verification](#8-verification)
- [Reference](#9-reference)

## Repository Layout

```text
.
|-- README.md
|-- docs/
|   `-- reference/
|       |-- script-contracts.md
|       `-- troubleshooting.md
|-- post-setup/
|   `-- hooks/
|       |-- 10-install-onboot-update.sh
|       |-- 20-run-automount-disks.sh
|       `-- 30-install-labwc.sh
|-- scripts/
|   |-- automount-disks.sh
|   |-- install-labwc.sh
|   |-- onboot-update.sh
|   |-- post-setup.sh
|   `-- setup.sh
`-- systemd/
    `-- onboot-update.service
```

## 1. Quick Orientation

What this repository does:

- Configures Debian Trixie package sources and installs desktop-focused packages.
- Enables core services (`bluetooth`, `seatd`) and user group mappings.
- Installs and enables an on-boot update service.
- Configures on-demand automount for detected unmounted EXT4/NTFS disks.

## 2. Prerequisites

- Debian 13 (Trixie).
- A non-root account with `sudo` privileges.
- Internet access for apt and package repositories.
- Commands run from the repository root.

Make scripts executable:

```bash
chmod +x scripts/*.sh post-setup/hooks/*.sh
```

## 3. Stage One: Base Setup

### Prerequisites

- Run from your normal user account.
- Save your work before running, because the script reboots the machine.

### Side Effects

- Rewrites `/etc/apt/sources.list` for Trixie repositories.
- Runs `apt-get update` and `apt-get full-upgrade -y`.
- Installs system packages and enables services.
- Adds the invoking sudo user to `video`, `render`, and `seat` groups.
- Installs `code-insiders` and its apt source.
- Reboots automatically after a 5-second delay.

`scripts/setup.sh` configures repositories, upgrades packages, installs core tooling, and configures services/users.

WARNING: this script is destructive and reboots the machine when it finishes.

Run:

```bash
sudo ./scripts/setup.sh
```

After reboot, log back in and continue with stage two.

## 4. Stage Two: Post-Setup Dispatcher

### Prerequisites

- Stage one completed and the system has rebooted.
- Run from a local clone of this repository.
- Run through `sudo` from a non-root account.

### Side Effects

- Installs `onboot-update.sh` to `/usr/local/sbin/onboot-update.sh`.
- Installs `onboot-update.service` to `/etc/systemd/system/onboot-update.service`.
- Reloads systemd and enables `onboot-update.service`.
- May append automount entries to `/etc/fstab` for detected unmounted EXT4/NTFS disks.
- Creates `/etc/fstab.backup.<timestamp>` before writing fstab changes.
- Reloads systemd and restarts `local-fs.target` during automount configuration.
- Prompts for labwc install mode (Debian package or latest source build), unless `LABWC_INSTALL_MODE` environment variable is set to skip prompt.
- Source mode installs build dependencies transiently, then removes only newly-added packages via `apt-mark auto` (preserves pre-existing manual package installs).
- Deploys labwc config files to `${XDG_CONFIG_HOME:-$HOME/.config}/labwc`: uses binary selection to copy from repo `.config/labwc` if it contains any candidate files; otherwise attempts `/usr/share/doc/labwc` as fallback. Never overwrites existing files.
- Source mode builds labwc with xwayland disabled and may let Meson download wlroots automatically when the required system version is unavailable.

`scripts/post-setup.sh` runs ordered hooks and stops on the first failure.

Current core hooks:

- Install and enable the on-boot update service.
- Run disk automount configuration.
- Install labwc (Debian package or latest source build, chosen interactively).

Run:

```bash
sudo ./scripts/post-setup.sh
```

## 5. Extending Post-Setup

The dispatcher uses a hybrid model:

- Core ordered hooks in `post-setup/hooks/` (versioned in this repo).
- Optional local hooks in `/etc/post-setup.d/*.sh` (machine-local extensions).

Add a local extension hook with an ordering prefix:

```bash
sudo install -d /etc/post-setup.d
sudo tee /etc/post-setup.d/30-example.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
echo "Running custom post-setup extension"
EOF
sudo chmod +x /etc/post-setup.d/30-example.sh
```

Rerun dispatcher:

```bash
sudo ./scripts/post-setup.sh
```


## 6. Remote Bootstrap (No Clone)

Only self-contained scripts should be run remotely. Each command block below shows what it will execute:

**Bootstrap the base system (stage one only):**
Downloads and runs the main setup script, which configures repositories, installs core packages, and reboots.
```bash
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/scripts/setup.sh | sudo bash
```

**Configure disk automounting only:**
Downloads and runs the automount script, which detects unmounted EXT4/NTFS disks and appends automount entries to `/etc/fstab`.
```bash
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/scripts/automount-disks.sh | sudo bash
```

**Install and enable the on-boot update service only:**
Downloads the update script and systemd unit, installs them to the correct locations, reloads systemd, and enables the service.
```bash
cd "$(mktemp -d)"
curl -sSLo onboot-update.sh https://raw.githubusercontent.com/d3bvstack/System-init/master/scripts/onboot-update.sh
curl -sSLo onboot-update.service https://raw.githubusercontent.com/d3bvstack/System-init/master/systemd/onboot-update.service
sudo install -Dm755 onboot-update.sh /usr/local/sbin/onboot-update.sh
sudo install -Dm644 onboot-update.service /etc/systemd/system/onboot-update.service
sudo systemctl daemon-reload
sudo systemctl enable onboot-update.service
```

Not supported as standalone remote execution (requires repository layout on disk):

- `scripts/post-setup.sh`
- `post-setup/hooks/*.sh`

## 7. Trust and Integrity

Piping remote scripts into a privileged shell is high risk. Prefer download-review-run:

```bash
curl -sSLo /tmp/setup.sh https://raw.githubusercontent.com/d3bvstack/System-init/master/scripts/setup.sh
less /tmp/setup.sh
sudo bash /tmp/setup.sh
```

For unattended automation, pin to an immutable ref (tag or commit SHA) and verify content before execution.

## 8. Verification

Check stage outcomes:

```bash
systemctl --user status pipewire
code-insiders --version
systemctl status onboot-update.service
grep -E 'x-systemd\.automount' /etc/fstab
```

Optional updater smoke test:

```bash
sudo systemctl start onboot-update.service
sudo journalctl -u onboot-update.service -n 50 --no-pager
```


## 9. Reference

For in-depth technical details, see the reference documentation:

- [Reference Index](docs/reference/README.md): Overview of all available technical docs.
- [Script Contracts](docs/reference/script-contracts.md): Inputs, required environment, side effects, and idempotency for each script.
- [Failure Modes & Troubleshooting](docs/reference/troubleshooting.md): Common errors, recovery steps, and diagnostics for each stage.
