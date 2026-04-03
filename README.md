# Debian 13 (Trixie) Post-Install and System Initialization

This repository now uses a two-stage flow:

1. `scripts/setup.sh` performs the base system bootstrap and reboots.
2. `scripts/post-setup.sh` runs post-reboot tasks through ordered hooks.

The post-setup step is intentionally extensible so future scripts can be added without rewriting the main entrypoint.

## Table of Contents

- [Preparation](#1-preparation)
- [Stage One: Base Setup](#2-stage-one-base-setup)
- [Stage Two: Post-Setup Dispatcher](#3-stage-two-post-setup-dispatcher)
- [Extending Post-Setup](#4-extending-post-setup)
- [Curl-Based Quick Start](#5-curl-based-quick-start)
- [Verification](#6-verification)

## Repository Layout

```text
.
├── README.md
├── post-setup/
│   └── hooks/
│       ├── 10-install-onboot-update.sh
│       └── 20-run-automount-disks.sh
├── scripts/
│   ├── automount-disks.sh
│   ├── onboot-update.sh
│   ├── post-setup.sh
│   └── setup.sh
└── systemd/
	└── onboot-update.service
```

## Opinionated Defaults

This repository intentionally makes a few choices for a Debian 13 desktop setup:

- Repositories include `non-free` and `non-free-firmware` because the setup is aimed at common desktop hardware, including AMD graphics and some Wi-Fi chipsets.
- Core packages include `pipewire`, `pipewire-pulse`, `wireplumber`, `seatd`, `bluetooth`, `bluez-tools`, `gnome-keyring`, `libsecret`, `foot`, `bemenu`, `ddcutil`, `playerctl`, `git`, `wget`, `gpg`, and `apt-transport-https` so the machine is ready for a graphical desktop, media, Bluetooth, and common hardware utilities.
- GPU and firmware packages include `firmware-amd-graphics`, `mesa` components, and `firmware-realtek` to cover typical AMD plus Realtek desktop hardware.
- `code-insiders` is installed instead of the stable VS Code build.
- `bluetooth` and `seatd` are enabled system-wide during setup, and the primary user is added to `video`, `render`, and `seat` groups so desktop and input access work without manual follow-up.
- `onboot-update.sh` is designed as a debounced maintenance job with a 12-hour cooldown, `Nice=19`, and `IOSchedulingClass=idle` so it stays out of the way during login.
- The updater service is locked down with `ProtectSystem=strict`, `PrivateTmp=true`, and explicit `ReadWritePaths` for only the apt and state directories it needs.
- Disk automounting uses `x-systemd.automount`, `noauto`, and `x-systemd.idle-timeout=15min` so drives mount on demand instead of delaying boot or staying mounted forever.
- EXT4 mounts are temporarily mounted once so ownership can be corrected for the active user, while NTFS mounts use `ntfs3` with `uid`, `gid`, `umask=022`, and `nofail` for predictable desktop access.
- `scripts/automount-disks.sh` only configures disks it detects as `ext4`, `ntfs`, or `ntfs3`; other filesystems are left untouched.
- The generated `fstab` entries end with `0 0`, which means the filesystems are not scheduled for boot-time fsck checks.

## 1. Preparation

From the repository directory, ensure scripts are executable:

```bash
chmod +x scripts/*.sh post-setup/hooks/*.sh
```

## 2. Stage One: Base Setup

`scripts/setup.sh` configures repositories, upgrades packages, installs core tooling, and configures services/users.

WARNING: this script is destructive and reboots the machine when it finishes.

Run from your normal user account via `sudo`:

```bash
sudo ./scripts/setup.sh
```

After reboot, log back in and continue with stage two.

## 3. Stage Two: Post-Setup Dispatcher

`scripts/post-setup.sh` is the new entrypoint for post-reboot actions. It runs ordered hooks and stops on the first failure.

Current core hooks:

- Installs `onboot-update.sh` to `/usr/local/sbin/onboot-update.sh`
- Installs `onboot-update.service` to `/etc/systemd/system/onboot-update.service`
- Reloads systemd and enables `onboot-update.service`
- Runs `automount-disks.sh` to configure EXT4/NTFS automount entries

Run:

```bash
sudo ./scripts/post-setup.sh
```

## 4. Extending Post-Setup

The dispatcher uses a hybrid model:

- Core ordered hooks in `post-setup/hooks/` (versioned in this repo)
- Optional local hooks in `/etc/post-setup.d/*.sh` (machine-local extensions)

Add new behavior by creating a new hook script with an ordering prefix, for example:

```bash
sudo install -d /etc/post-setup.d
sudo tee /etc/post-setup.d/30-example.sh > /dev/null <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
echo "Running custom post-setup extension"
EOF
sudo chmod +x /etc/post-setup.d/30-example.sh
```

Then rerun:

```bash
sudo ./scripts/post-setup.sh
```

## 5. Curl-Based Quick Start

If you do not want to clone the repository, you can launch individual scripts directly from curl.

Bootstrap the base system:

```bash
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/scripts/setup.sh | sudo bash
```

Run the full post-setup dispatcher after reboot:

```bash
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/scripts/post-setup.sh | sudo bash
```

Run only the disk automount script:

```bash
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/scripts/automount-disks.sh | sudo bash
```

Install and enable only the on-boot update service:

```bash
cd $(mktemp -d)
curl -sSLo onboot-update.sh https://raw.githubusercontent.com/d3bvstack/System-init/master/scripts/onboot-update.sh
curl -sSLo onboot-update.service https://raw.githubusercontent.com/d3bvstack/System-init/master/systemd/onboot-update.service
sudo install -Dm755 onboot-update.sh /usr/local/sbin/onboot-update.sh
sudo install -Dm644 onboot-update.service /etc/systemd/system/onboot-update.service
sudo systemctl daemon-reload
sudo systemctl enable onboot-update.service
```

Run a single post-setup hook directly:

```bash
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/post-setup/hooks/10-install-onboot-update.sh | sudo bash
```

## 6. Verification

Check that each phase completed as expected:

```bash
systemctl --user status pipewire
code-insiders --version
systemctl status onboot-update.service
grep -E 'x-systemd\.automount' /etc/fstab
```

Optional: trigger and inspect updater logs immediately:

```bash
sudo systemctl start onboot-update.service
sudo journalctl -u onboot-update.service -n 50 --no-pager
```
