#!/usr/bin/env bash
# Purpose: Install and enable the onboot-update systemd service.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

# Resolve repository root from hook location so cwd does not matter.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

UPDATE_SCRIPT_SOURCE="$REPO_DIR/scripts/onboot-update.sh"
SERVICE_SOURCE="$REPO_DIR/systemd/onboot-update.service"

if [[ ! -f "$UPDATE_SCRIPT_SOURCE" ]]; then
    echo "ERROR: Missing file: $UPDATE_SCRIPT_SOURCE"
    exit 1
fi

if [[ ! -f "$SERVICE_SOURCE" ]]; then
    echo "ERROR: Missing file: $SERVICE_SOURCE"
    exit 1
fi

# Install service files into system paths and enable startup.
install -Dm755 "$UPDATE_SCRIPT_SOURCE" /usr/local/sbin/onboot-update.sh
install -Dm644 "$SERVICE_SOURCE" /etc/systemd/system/onboot-update.service

systemctl daemon-reload
systemctl enable onboot-update.service

echo ">> onboot-update service installed and enabled."
