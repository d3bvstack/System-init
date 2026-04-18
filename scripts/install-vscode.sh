#!/usr/bin/env bash
# Purpose: Install VS Code Insiders from Microsoft's apt repository.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

echo ">> Installing VS Code Insiders..."

# Stream the repository key directly to the target keyring file.
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null

# Ensure apt can read the repository key.
sudo chmod 644 /usr/share/keyrings/microsoft.gpg

# Add Microsoft's code repository source.
cat <<EOF | sudo tee /etc/apt/sources.list.d/vscode.sources > /dev/null
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64 arm64 armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

# Update package metadata and install code-insiders.
sudo apt-get update
sudo apt-get install code-insiders -y

echo ">> VS Code Insiders installed successfully."
