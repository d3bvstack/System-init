#!/usr/bin/env bash

# Runs post-reboot setup actions in a predictable order.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CORE_HOOK_DIR="$REPO_DIR/post-setup/hooks"
LOCAL_HOOK_DIR="/etc/post-setup.d"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Please run with sudo from your normal user account."
    exit 1
fi

if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
    echo "ERROR: Run this script via sudo from a non-root account so user mappings are preserved."
    exit 1
fi

run_hook() {
    local hook_path="$1"

    if [[ ! -f "$hook_path" ]]; then
        echo "ERROR: Hook not found: $hook_path"
        return 1
    fi

    echo ">> Running hook: $(basename "$hook_path")"
    bash "$hook_path"
}

echo ">> Starting post-setup tasks for user: ${SUDO_USER}"

core_hooks=(
    "$CORE_HOOK_DIR/10-install-onboot-update.sh"
    "$CORE_HOOK_DIR/20-run-automount-disks.sh"
    "$CORE_HOOK_DIR/30-install-labwc.sh"
)

for hook in "${core_hooks[@]}"; do
    run_hook "$hook"
done

if [[ -d "$LOCAL_HOOK_DIR" ]]; then
    echo ">> Loading extension hooks from $LOCAL_HOOK_DIR"
    while IFS= read -r -d '' hook; do
        run_hook "$hook"
    done < <(find "$LOCAL_HOOK_DIR" -maxdepth 1 -type f -name '*.sh' -print0 | sort -z)
fi

echo ">> Post-setup completed successfully."
