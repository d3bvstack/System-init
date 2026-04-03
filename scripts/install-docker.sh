#!/usr/bin/env bash

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Please run this script with sudo or as root."
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "ERROR: Cannot read /etc/os-release to determine the Debian codename."
    exit 1
fi

. /etc/os-release

if [[ -z "${VERSION_CODENAME:-}" ]]; then
    echo "ERROR: VERSION_CODENAME is not set in /etc/os-release."
    exit 1
fi

ARCHITECTURE="$(dpkg --print-architecture)"
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_PATH="$KEYRING_DIR/docker.asc"
SOURCE_PATH="/etc/apt/sources.list.d/docker.sources"

echo ">> Installing prerequisites for Docker repository setup..."
apt-get update
apt-get install -y ca-certificates curl

install -d -m 0755 "$KEYRING_DIR"

echo ">> Downloading Docker repository key..."
curl -fsSL https://download.docker.com/linux/debian/gpg -o "$KEYRING_PATH"
chmod a+r "$KEYRING_PATH"

echo ">> Configuring Docker apt repository for suite: $VERSION_CODENAME"
cat > "$SOURCE_PATH" <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $VERSION_CODENAME
Components: stable
Architectures: $ARCHITECTURE
Signed-By: $KEYRING_PATH
EOF

apt-get update

echo ">> Installing Docker packages..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if systemctl is-active docker >/dev/null 2>&1; then
    echo ">> Docker service is active."
else
    echo ">> Docker service is installed and will start on boot if enabled by the package defaults."
fi

echo ">> Docker installation completed successfully."