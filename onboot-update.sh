#!/usr/bin/env bash
# /usr/local/sbin/onboot-update.sh

# Strict error handling
set -Eeuo pipefail

# Non-interactive mode for APT
export DEBIAN_FRONTEND=noninteractive

# Configuration
STAMP_DIR="/var/lib/local-updates"
STAMP_FILE="$STAMP_DIR/last-update.stamp"
TIMEOUT_MINUTES=720 # 12 hours

# Ensure the state directory exists (FHS compliant for persistent state data)
mkdir -p "$STAMP_DIR"

# Check if the timestamp file exists and was modified within the last 12 hours
if[ -f "$STAMP_FILE" ]; then
    # Find will output the filename if it was modified less than TIMEOUT_MINUTES ago
    RECENT_RUN=$(find "$STAMP_FILE" -mmin -"$TIMEOUT_MINUTES" 2>/dev/null)
    if [ -n "$RECENT_RUN" ]; then
        echo "Last update was performed less than 12 hours ago. Skipping update."
        exit 0
    fi
fi

echo "Initiating Stable system update..."

# Add a lock timeout in case another APT process (like packagekit) is running
APT_OPTS="-o DPkg::Lock::Timeout=120"

# Execute updates
apt-get $APT_OPTS update

# Safe to use full-upgrade on Debian Stable
apt-get $APT_OPTS full-upgrade -y

# Cleanup
apt-get $APT_OPTS autoremove --purge -y
apt-get $APT_OPTS clean

# Update the timestamp file
touch "$STAMP_FILE"
echo "System update completed successfully."
