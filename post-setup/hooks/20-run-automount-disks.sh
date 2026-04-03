#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
AUTOMOUNT_SCRIPT="$REPO_DIR/scripts/automount-disks.sh"

if [[ ! -f "$AUTOMOUNT_SCRIPT" ]]; then
    echo "ERROR: Missing file: $AUTOMOUNT_SCRIPT"
    exit 1
fi

bash "$AUTOMOUNT_SCRIPT"
