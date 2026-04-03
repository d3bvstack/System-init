#!/usr/bin/env bash
# Purpose: Run disk automount configuration from the shared script.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

# Resolve repository root from hook location so cwd does not matter.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
AUTOMOUNT_SCRIPT="$REPO_DIR/scripts/automount-disks.sh"

if [[ ! -f "$AUTOMOUNT_SCRIPT" ]]; then
    echo "ERROR: Missing file: $AUTOMOUNT_SCRIPT"
    exit 1
fi

# Delegate disk discovery and fstab updates to the shared script.
bash "$AUTOMOUNT_SCRIPT"
