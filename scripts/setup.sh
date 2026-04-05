#!/usr/bin/env bash
# Purpose: Configure a Debian Trixie workstation with core packages and services.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

# Prevent apt from opening interactive prompts.
export DEBIAN_FRONTEND=noninteractive

# Resolve the target non-root user, even when the script is run via sudo.
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

# Configure Debian Trixie apt sources.
# Note: non-free sections are required for some GPU and Wi-Fi firmware.
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

# Update package metadata and apply a full upgrade.
echo ">> Updating package cache and performing full upgrade..."
sudo apt-get update
sudo apt-get full-upgrade -y

# Install core firmware, desktop, audio, and utility packages.
echo ">> Installing core packages..."
sudo apt-get install -y \
    firmware-amd-graphics libgl1-mesa-dri libglx-mesa0 mesa-utils mesa-vulkan-drivers \
    build-essential clang valgrind \
    firmware-realtek \
    bluez bluetooth bluez-tools ddcutil playerctl git \
    initramfs-tools \
    seatd foot bemenu \
    ntfs-3g \
    pipewire pipewire-audio pipewire-pulse wireplumber \
    gnome-keyring libsecret-1-0 libsecret-tools libpam-gnome-keyring \
    wget gpg apt-transport-https

# Enable required services and add user group memberships.
echo ">> Enabling system services and configuring groups..."
sudo systemctl enable --now bluetooth seatd
sudo groupadd seat
sudo usermod -aG video,render,seat "$ACTUAL_USER"

# Apply the boot-time fixes before the first reboot.
echo ">> Applying boot-time stability fixes..."
cat <<'EOF' | sudo tee /etc/modprobe.d/btusb.conf > /dev/null
options btusb enable_autosuspend=n
EOF

if [ -w /sys/module/btusb/parameters/enable_autosuspend ]; then
    echo N | sudo tee /sys/module/btusb/parameters/enable_autosuspend > /dev/null
fi

if grep -Eq '^[#[:space:]]*MODULES=' /etc/initramfs-tools/initramfs.conf; then
    sudo sed -i 's/^[#[:space:]]*MODULES=.*/MODULES=dep/' /etc/initramfs-tools/initramfs.conf
else
    echo 'MODULES=dep' | sudo tee -a /etc/initramfs-tools/initramfs.conf > /dev/null
fi

sudo update-initramfs -u -k "$(uname -r)"

# Enable user-level PipeWire services by setting the user's runtime directory.
echo ">> Enabling Pipewire for user $ACTUAL_USER..."
sudo -u "$ACTUAL_USER" XDG_RUNTIME_DIR="/run/user/$ACTUAL_UID" \
    systemctl --user enable --now pipewire pipewire-pulse wireplumber

# Enable GNOME Keyring integration through Debian PAM tooling.
echo ">> Configuring PAM for Gnome Keyring..."
# Use Debian's managed PAM interface instead of editing /etc/pam.d files directly.
sudo pam-auth-update --enable gnome-keyring
# Keep shell profiles unchanged; keyring startup is handled by PAM sessions.

# Install VS Code Insiders from Microsoft's apt repository.
echo ">> Installing VS Code..."
# Stream the repository key directly to the target keyring file.
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null

# Ensure apt can read the repository key.
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

# Remove no-longer-needed packages and clean apt cache.
echo ">> Cleaning up..."
sudo apt-get autoremove --purge -y
sudo apt-get clean

# Reboot after a short delay so the new system state is applied.
echo "======================================================="
echo "Setup complete. The system requires a reboot."
echo "Rebooting in 5 seconds... Press Ctrl+C to abort."
echo "======================================================="
sleep 5
sudo systemctl reboot
