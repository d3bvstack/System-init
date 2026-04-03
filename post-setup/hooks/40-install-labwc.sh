#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
INSTALL_SCRIPT="$REPO_DIR/scripts/install-labwc.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    echo "ERROR: Missing file: $INSTALL_SCRIPT"
    exit 1
fi

bash "$INSTALL_SCRIPT"
