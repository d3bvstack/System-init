#!/usr/bin/env bash
# Purpose: Install Docker Engine from Docker's Debian repository.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

# Prevent apt from opening interactive prompts.
export DEBIAN_FRONTEND=noninteractive

# Require root privileges because this script modifies system package sources.
if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Please run this script with sudo or as root."
    exit 1
fi

# Read distro metadata to choose the correct Debian suite.
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

# Install tools required to add Docker's repository key and source.
echo ">> Installing prerequisites for Docker repository setup..."
apt-get update
apt-get install -y ca-certificates curl

# Create the standard apt keyring directory with expected permissions.
install -d -m 0755 "$KEYRING_DIR"

echo ">> Downloading Docker repository key..."
curl -fsSL https://download.docker.com/linux/debian/gpg -o "$KEYRING_PATH"
chmod a+r "$KEYRING_PATH"

# Write a deb822 source entry for this architecture and suite.
echo ">> Configuring Docker apt repository for suite: $VERSION_CODENAME"
cat > "$SOURCE_PATH" <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $VERSION_CODENAME
Components: stable
Architectures: $ARCHITECTURE
Signed-By: $KEYRING_PATH
EOF

# Refresh package metadata after adding the Docker repository.
apt-get update

echo ">> Installing Docker packages..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add the invoking non-root user to the docker group for rootless docker CLI usage.
TARGET_USER=""
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
elif [[ -n "${USER:-}" && "${USER}" != "root" ]]; then
    TARGET_USER="$USER"
fi

if ! getent group docker >/dev/null 2>&1; then
    groupadd --system docker
fi

if [[ -n "$TARGET_USER" ]] && id -u "$TARGET_USER" >/dev/null 2>&1; then
    if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
        echo ">> User '$TARGET_USER' is already in the docker group."
    else
        usermod -aG docker "$TARGET_USER"
        echo ">> Added user '$TARGET_USER' to docker group. Re-login (or run: newgrp docker) to apply."
    fi
else
    echo ">> Could not determine a non-root target user. Add a user manually with: usermod -aG docker <username>"
fi

# Report current Docker service state.
if systemctl is-active docker >/dev/null 2>&1; then
    echo ">> Docker service is active."
else
    echo ">> Docker service is installed and will start on boot if enabled by the package defaults."
fi

echo ">> Docker installation completed successfully."