# Debian Trixie Post-Install & System Initialization Guide

This guide details how to use the provided scripts to configure a fresh Debian Trixie installation, automate disk mounting, and set up a debounced on-boot update service.

## 1. Preparation

First, ensure all scripts are executable. From the directory containing these files, run:

```bash
chmod +x *.sh
```

## 2. Post-Install Setup

The `setup.sh` script bootstraps your Trixie environment. It configures APT repositories (including non-free firmware), performs a full system upgrade, installs core packages (like PipeWire, seatd, Mesa drivers, and VS Code Insiders), and sets up user groups.

**WARNING:** This script is destructive and **will reboot your system** upon completion.

Run the script using `sudo` from your normal user account (do not run as root directly, as it needs to configure your user environment):

**Option A: From a local copy (shell)**
```bash
sudo ./setup.sh
```

**Option B: Directly via curl**
You can download and execute it directly from this repo:
```bash
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/setup.sh | sudo bash
```

Wait for the system to reboot, then log back in.

## 3. Storage Automounting

The `automount-disks.sh` script detects unmounted EXT4 and NTFS disks and safely configures systemd.automount in `/etc/fstab`. This ensures drives are mounted on-demand without hanging your boot process.

Run the script from your **normal user account** (it uses your UID/GID for NTFS permissions):

**Option A: From a local copy (shell)**
```bash
sudo cp automount-disks.sh /usr/local/sbin/
sudo /usr/local/sbin/automount-disks.sh
```

**Option B: Directly via curl**
You can download and execute it directly from this repo:
```bash
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/automount-disks.sh | sudo bash
```

*Note: A backup of your `fstab` is automatically created in `/etc/` before any changes are made.*

## 4. On-Boot Updates

The `onboot-update.sh` script and corresponding `onboot-update.service` provide a safe, debounced (12-hour timeout) background auto-updater. It runs early in the boot process but uses low IO/CPU priority to avoid slowing down your desktop login.

**Option A: From a local copy (shell)**
```bash
sudo cp onboot-update.sh /usr/local/sbin/
sudo cp onboot-update.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable onboot-update.service
```

**Option B: Directly via curl **
You can download and execute it directly from this repo:
```bash
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/onboot-update.sh | sudo tee /usr/local/sbin/onboot-update.sh > /dev/null
curl -sSL https://raw.githubusercontent.com/d3bvstack/System-init/master/onboot-update.service | sudo tee /etc/systemd/system/onboot-update.service > /dev/null
sudo chmod +x /usr/local/sbin/onboot-update.sh
sudo systemctl daemon-reload
sudo systemctl enable onboot-update.service
```

*You can optionally test it immediately by running `sudo systemctl start onboot-update.service`.*

## Verification

To ensure everything is working as expected:

- **System Setup**: Verify PipeWire and VS Code are installed:
  ```bash
  systemctl --user status pipewire
  code-insiders --version
  ```
- **Automounting**: Check your `fstab` to ensure your external drives have the `x-systemd.automount` option:
  ```bash
  cat /etc/fstab
  ```
- **On-Boot Updates**: Check the status of the update service:
  ```bash
  systemctl status onboot-update.service
  ```
