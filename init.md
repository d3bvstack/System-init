# Debian Minimal Setup Guide

A streamlined workflow for setting up a functional desktop environment on a minimal Debian installation.

---

## Table of contents
- [Prerequisites](#prerequisites)
- [1. Base System Update](#1-base-system-update)
- [2. Configure Repositories](#2-configure-repositories)
- [3. Hardware & Drivers](#3-hardware--drivers)
  - [Graphics (AMD RX 5600 XT)](#graphics-amd-rx-5600-xt)
  - [Networking (Realtek)](#networking-realtek)
  - [Finalize Hardware Setup](#finalize-hardware-setup)
- [4. Desktop Environment (Labwc)](#4-desktop-environment-labwc)
  - [Install core packages](#install-core-packages)
  - [Configure permissions & services](#configure-permissions--services)
  - [Configuration files](#configuration-files)
  - [Customization](#customization)
- [5. Audio Setup (Pipewire)](#5-audio-setup-pipewire)
- [Post-install checklist](#post-install-checklist)
- [Troubleshooting & tips](#troubleshooting--tips)

---

## Prerequisites
- A minimal Debian installation (Bookworm, or adjust mirror line for your release).
- A user account with sudo privileges.
- Internet access to download packages.

---

## 1. Base System Update
Begin by ensuring your package lists and existing system components are up to date.

```bash name=01-update-upgrade.sh
sudo apt update && sudo apt upgrade -y
```

---

## 2. Configure Repositories
To access proprietary drivers and firmware, enable the `contrib`, `non-free`, and `non-free-firmware` components. Edit `/etc/apt/sources.list` to match the following structure:

```text name=/etc/apt/sources.list
deb http://deb.debian.org bookworm main contrib non-free-firmware non-free
```

> **Note:** This configuration uses the Debian mirrors backed by Fastly CDN for optimized delivery. Adjust `bookworm` to your release codename if needed.

After editing, run:

```bash name=02-apt-update.sh
sudo apt update
```

---

## 3. Hardware & Drivers

### Graphics (AMD RX 5600 XT)
Install AMD firmware and Mesa/Vulkan drivers:

```bash name=03-amd-drivers.sh
sudo apt install firmware-amd-graphics libgl1-mesa-dri libglx-mesa0 \
mesa-vulkan-drivers xserver-xorg-video-amdgpu -y
```

### Networking (Realtek)
Install Realtek firmware:

```bash name=04-network-firmware.sh
sudo apt install firmware-realtek -y
```

### Finalize Hardware Setup
Apply changes to the initramfs and restart to ensure firmware/drivers load correctly:

```bash name=05-update-initramfs-and-reboot.sh
sudo update-initramfs -u
sudo reboot
```

---

## 4. Desktop Environment (Labwc)
This guide uses a Wayland-based stack (labwc, seatd, foot) and configures user permissions and example configs.

### Install core packages

```bash name=06-install-labwc.sh
sudo apt install labwc seatd foot bemenu -y
```

### Configure permissions & services

```bash name=07-permissions-services.sh
sudo usermod -aG video,render,seat $USER
sudo systemctl enable --now seatd
```

### Configuration files
Move the example configuration files to your local XDG config directory:

```bash name=08-copy-labwc-configs.sh
mkdir -p ${XDG_CONFIG_HOME:-$HOME/.config}/labwc
cp /usr/share/doc/labwc/examples/* ${XDG_CONFIG_HOME:-$HOME/.config}/labwc/
```

### Customization
- Keyboard layout: edit the appropriate config file in `~/.config/labwc/` to set your preferred layout.
- Apply changes: reload labwc without restarting by running:

```bash name=09-reload-labwc.sh
labwc -r
```

---

## 5. Audio Setup (Pipewire)
Install the modern Pipewire audio stack and enable user services:

```bash name=10-pipewire-install.sh
sudo apt update
sudo apt install pipewire pipewire-audio pipewire-pulse wireplumber -y
systemctl --user --now enable pipewire pipewire-pulse wireplumber
```

---

## Post-install checklist
- [ ] Confirm GPU is recognized: `lspci -k | grep -A3 -i vga`
- [ ] Confirm kernel modules/firmware loaded: `dmesg | grep -i firmware`
- [ ] Verify seatd is active: `systemctl status seatd`
- [ ] Verify Pipewire services: `systemctl --user status pipewire wireplumber`
- [ ] Verify you can start a Wayland session (login manager or manual start)

---

## Troubleshooting & tips
- If graphics are not working, check `journalctl -b` and `dmesg` for firmware errors.
- For missing firmware packages, enable the `non-free`/`contrib` sections and run `sudo apt update` again.
- If audio routes don’t appear, run `pactl info` and `pw-top` to inspect Pipewire state.
- To make seatd start automatically system-wide, check `/etc/systemd/system` unit overrides and logs: `journalctl -u seatd`.
