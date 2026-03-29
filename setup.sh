#!/bin/bash

# Update and Upgrade
sudo apt update && sudo apt upgrade -y

# Configure sources.list for Bookworm with all components
# This replaces the entire file to ensure the structure is exactly as requested
echo "deb http://deb.debian.org bookworm main contrib non-free-firmware non-free" | sudo tee /etc/apt/sources.list
echo "deb-src http://deb.debian.org bookworm main contrib non-free-firmware non-free" | sudo tee -a /etc/apt/sources.list

# Update after repository change
sudo apt update

# Install Graphics and Firmware
sudo apt install firmware-amd-graphics libgl1-mesa-dri libglx-mesa0 \
mesa-vulkan-drivers xserver-xorg-video-amdgpu firmware-realtek -y

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

echo "Setup complete. The system will reboot in 5 seconds..."
sleep 5
sudo reboot
