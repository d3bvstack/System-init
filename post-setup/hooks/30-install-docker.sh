#!/usr/bin/env bash
# Purpose: Run Docker installation from the shared script.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

# Resolve repository root from hook location so cwd does not matter.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
INSTALL_SCRIPT="$REPO_DIR/scripts/install-docker.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    echo "ERROR: Missing file: $INSTALL_SCRIPT"
    exit 1
fi

# Delegate Docker installation to the shared script.
bash "$INSTALL_SCRIPT"
