#!/usr/bin/env bash
# Purpose: Run unattended apt updates at boot with a minimum interval.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

# Prevent apt from opening interactive prompts.
export DEBIAN_FRONTEND=noninteractive

# Define update state path and minimum interval between runs.
STAMP_DIR="/var/lib/local-updates"
STAMP_FILE="$STAMP_DIR/last-update.stamp"
TIMEOUT_MINUTES=720 # 12 hours

# Ensure the state directory exists for persistent run metadata.
mkdir -p "$STAMP_DIR"

# Skip when the previous successful run is still within the interval.
if [ -f "$STAMP_FILE" ]; then
    # find returns the file path when modification age is below timeout.
    RECENT_RUN=$(find "$STAMP_FILE" -mmin -"$TIMEOUT_MINUTES" 2>/dev/null)
    if [ -n "$RECENT_RUN" ]; then
        echo "Last update was performed less than 12 hours ago. Skipping update."
        exit 0
    fi
fi

echo "Initiating Stable system update..."

# Wait briefly for apt locks if another package manager process is active.
APT_OPTS="-o DPkg::Lock::Timeout=120"

# Refresh package metadata.
apt-get $APT_OPTS update

# Install all available updates.
apt-get $APT_OPTS full-upgrade -y

# Remove no-longer-needed packages and clean apt cache.
apt-get $APT_OPTS autoremove --purge -y
apt-get $APT_OPTS clean

# Record successful completion time.
touch "$STAMP_FILE"
echo "System update completed successfully."
