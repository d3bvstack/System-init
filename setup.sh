#!/bin/bash

# Overwrite sources.list with the full Trixie configuration
cat <<EOF | sudo tee /etc/apt/sources.list
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

# Perform the upgrade to Stable (Trixie)
sudo apt update && sudo apt full-upgrade -y

# Install Graphics, Firmware, and Bluetooth
sudo apt install firmware-amd-graphics libgl1-mesa-dri libglx-mesa0 \
mesa-vulkan-drivers xserver-xorg-video-amdgpu firmware-realtek \
bluez blueman ddcutil playerctl git -y

sudo systemctl enable --now bluetooth

# Update initramfs
sudo update-initramfs -u

# Install System Utilities
sudo apt install seatd foot bemenu -y
sudo usermod -aG video,render,seat $USER
sudo systemctl enable --now seatd

# Install Audio (Pipewire)
sudo apt install pipewire pipewire-audio pipewire-pulse wireplumber -y

# Enable Pipewire for the current user
# Note: This runs for the user executing the script
systemctl --user --now enable pipewire pipewire-pulse wireplumber

# Install Keyring and PAM integration
sudo apt install gnome-keyring libsecret-1-0 libsecret-tools libpam-gnome-keyring -y

# Configure PAM to unlock the keyring on login (for TTY/Console login)
# This adds the necessary lines to /etc/pam.d/login if they don't already exist
if ! grep -q "pam_gnome_keyring.so" /etc/pam.d/login; then
    sudo sed -i '/auth.*pam_unix.so/a auth optional pam_gnome_keyring.so' /etc/pam.d/login
    sudo sed -i '/session.*pam_unix.so/a session optional pam_gnome_keyring.so auto_start' /etc/pam.d/login
fi

# Ensure the Keyring Daemon starts with your session
# Add to your .bash_profile or .profile to export the environment variables
cat << 'EOF' >> ~/.profile
if [ -n "$IS_TTY" ] || [ -z "$GRAPHICAL_SESSION" ]; then
    eval $(gnome-keyring-daemon --start --components=secrets)
    export SSH_AUTH_SOCK
fi
EOF

# Install dependencies for VS Code
sudo apt install wget gpg apt-transport-https -y

# Download and install the Microsoft GPG key
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg
rm -f microsoft.gpg

# Create the VS Code repository file in the modern DEB822 format
cat <<EOF | sudo tee /etc/apt/sources.list.d/vscode.sources
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64 arm64 armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

# Update cache and install VS Code Insiders
sudo apt update
sudo apt install code-insiders -y

# Cleanup
sudo apt autoremove -y
echo "Setup complete. The system will reboot in 5 seconds..."
sleep 5
sudo reboot
