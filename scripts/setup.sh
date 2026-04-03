#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Debian Trixie Post-Installation Script
# -----------------------------------------------------------------------------

# Fail on error, fail on unset vars, fail on pipeline errors
set -Eeuo pipefail

# Force APT into non-interactive mode so it doesn't hang on prompts
export DEBIAN_FRONTEND=noninteractive

# 1. Determine User Execution Context
# Ensure we apply configurations to the actual human user, even if run via sudo
if [ -n "${SUDO_USER:-}" ]; then
    ACTUAL_USER="$SUDO_USER"
    ACTUAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    ACTUAL_UID=$(id -u "$SUDO_USER")
else
    ACTUAL_USER="$USER"
    ACTUAL_HOME="$HOME"
    ACTUAL_UID=$(id -u "$USER")
fi

echo ">> Applying user configurations for: $ACTUAL_USER"

# 2. Configure APT Sources (Trixie)
# Note: Enabling 'non-free' and 'non-free-firmware' violates strict DFSG, 
# but is required for AMD GPUs and certain Wi-Fi cards.
echo ">> Configuring Trixie Repositories..."
cat <<EOF | sudo tee /etc/apt/sources.list > /dev/null
# Trixie Main Repos
deb http://deb.debian.org/debian/ trixie main contrib non-free-firmware non-free
deb-src http://deb.debian.org/debian/ trixie main contrib non-free-firmware non-free

# Trixie Security
deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware non-free
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free-firmware non-free

# Trixie Updates
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free-firmware non-free
deb-src http://deb.debian.org/debian/ trixie-updates main contrib non-free-firmware non-free
EOF

# 3. System Upgrade
echo ">> Updating package cache and performing full upgrade..."
sudo apt-get update
sudo apt-get full-upgrade -y

# 4. Install Hardware, Firmware, and Core Packages
echo ">> Installing core packages..."
sudo apt-get install -y \
    firmware-amd-graphics libgl1-mesa-dri libglx-mesa0 mesa-utils mesa-vulkan-drivers \
    firmware-realtek \
    bluez bluetooth bluez-tools ddcutil playerctl git \
    seatd foot bemenu \
    pipewire pipewire-audio pipewire-pulse wireplumber \
    gnome-keyring libsecret-1-0 libsecret-tools libpam-gnome-keyring \
    wget gpg apt-transport-https

# 5. System Services and Group Management
echo ">> Enabling system services and configuring groups..."
sudo systemctl enable --now bluetooth seatd
sudo group add seat
sudo usermod -aG video,render,seat "$ACTUAL_USER"

# 6. Pipewire User Configuration
# Safely executing user-level systemctl commands by passing XDG_RUNTIME_DIR
echo ">> Enabling Pipewire for user $ACTUAL_USER..."
sudo -u "$ACTUAL_USER" XDG_RUNTIME_DIR="/run/user/$ACTUAL_UID" \
    systemctl --user enable --now pipewire pipewire-pulse wireplumber

# 7. PAM and Keyring Integration (The Debian Way)
echo ">> Configuring PAM for Gnome Keyring..."
# 'pam-auth-update' is the Debian-standard way to manage /etc/pam.d/ configurations
sudo pam-auth-update --enable gnome-keyring
# Keep shell profiles untouched here; keyring startup is delegated to PAM/session components.

# 8. Visual Studio Code Installation
echo ">> Installing VS Code..."
# Stream the key directly to the correct location without temporary files
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null

# Ensure strict FHS permissions on the GPG key
sudo chmod 644 /usr/share/keyrings/microsoft.gpg

cat <<EOF | sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64 arm64 armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

sudo apt-get update
sudo apt-get install code-insiders -y

# 9. Final Cleanup
echo ">> Cleaning up..."
sudo apt-get autoremove --purge -y
sudo apt-get clean

# WARNING: Destructive command ahead
echo "======================================================="
echo "Setup complete. The system requires a reboot."
echo "Rebooting in 5 seconds... Press Ctrl+C to abort."
echo "======================================================="
sleep 5
sudo systemctl reboot
