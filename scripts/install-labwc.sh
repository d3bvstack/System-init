#!/usr/bin/env bash
# Purpose: Install labwc and initialize user configuration files.

# Exit on errors, unset variables, and pipeline failures.
set -Eeuo pipefail

# Prevent apt from opening interactive prompts.
export DEBIAN_FRONTEND=noninteractive

# Resolve repository-relative paths once and reuse across functions.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
LABWC_REPO_URL="https://github.com/labwc/labwc"
LABWC_REPO_CLONE_DIR="/usr/local/src/labwc"
LABWC_DOCKER_BUILD_ROOT="/usr/local/src/labwc-docker-build"
WLR_REPO_URL="https://gitlab.freedesktop.org/wlroots/wlroots"

DOCKER_BUILD_DEPS=(
    "ca-certificates"
    "git"
    "build-essential"
    "meson"
    "ninja-build"
    "pkg-config"
    "scdoc"
    "checkinstall"
    "libwayland-dev"
    "wayland-protocols"
    "libpixman-1-dev"
    "libxkbcommon-dev"
    "libxml2-dev"
    "libpango1.0-dev"
    "libcairo2-dev"
)

DOCKER_WLROOTS_SOURCE_DEPS=(
    "bison"
    "flex"
    "libdrm-dev"
    "libinput-dev"
    "libseat-dev"
    "libdisplay-info-dev"
    "libliftoff-dev"
    "hwdata"
    "libegl1-mesa-dev"
    "libgles2-mesa-dev"
    "libgbm-dev"
    "libxcb-ewmh-dev"
    "libxcb-icccm4-dev"
    "libxcb-errors-dev"
    "libxcb-render-util0-dev"
    "libxcb-composite0-dev"
    "libxcb-xfixes0-dev"
    "libxcb-randr0-dev"
    "libxcb-xinput-dev"
    "libxcb-res0-dev"
    "libxcb-dri3-dev"
)

# Require root privileges because this script installs packages and writes system paths.
if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Please run with sudo from your normal user account."
    exit 1
fi

# Require sudo user context so copied files have correct ownership.
if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
    echo "ERROR: Run this script via sudo from a non-root account so user mappings are preserved."
    exit 1
fi

TARGET_USER="$SUDO_USER"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
TARGET_XDG_CONFIG_HOME="$(sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" bash -c 'printf %s "${XDG_CONFIG_HOME:-$HOME/.config}"')"
TARGET_LABWC_CONFIG_DIR="$TARGET_XDG_CONFIG_HOME/labwc"
REPO_LABWC_CONFIG_DIR="$REPO_DIR/.config/labwc"
DEFAULT_LABWC_CONFIG_DIR="/usr/share/doc/labwc"

LABWC_CONFIG_FILES=(
    "rc.xml"
    "menu.xml"
    "autostart"
    "shutdown"
    "environment"
    "themerc-override"
)

BUILD_DEPS=(
    "build-essential"
    "git"
    "meson"
    "ninja-build"
    "pkg-config"
    "scdoc"
    "libwayland-dev"
    "wayland-protocols"
    "libwlroots-dev"
    "libpixman-1-dev"
    "libxkbcommon-dev"
    "libxml2-dev"
    "libpango1.0-dev"
    "libcairo2-dev"
)

prompt_install_mode() {
    # Prompt for installation mode when LABWC_INSTALL_MODE is unset.
    local mode=""

    while [[ -z "$mode" ]]; do
        echo
        echo "How should labwc be installed on this system?"
        echo "1) Install the Debian package from apt"
        echo "2) Build and install the latest upstream release from source"
        echo "3) Build a Debian package in Docker, then install it on the host"
        read -r -p "Choose an option [1-3]: " choice

        case "$choice" in
            1)
                mode="package"
                ;;
            2)
                mode="source"
                ;;
            3)
                mode="docker-package"
                ;;
            *)
                echo "Invalid selection. Please enter 1, 2, or 3."
                ;;
        esac
    done

    printf '%s\n' "$mode"
}

install_from_package() {
    # Install labwc from Debian repositories.
    echo ">> Installing labwc from Debian repositories..."

    apt-get update
    if ! apt-get install -y labwc; then
        echo "ERROR: Failed to install labwc from Debian repositories."
        echo "Hint: Ensure package 'labwc' exists for your configured Debian release."
        return 1
    fi
}

install_from_source() {
    # Build and install the latest upstream labwc tag directly on host.
    local latest_tag=""
    local dep=""
    local pre_manual_list=()
    local -A pre_manual_map=()

    mapfile -t pre_manual_list < <(apt-mark showmanual)
    for dep in "${pre_manual_list[@]}"; do
        pre_manual_map["$dep"]=1
    done

    echo ">> Installing labwc build dependencies..."
    apt-get update
    apt-get install -y --no-install-recommends "${BUILD_DEPS[@]}"

    # Mark newly introduced build dependencies as auto for cleanup.
    for dep in "${BUILD_DEPS[@]}"; do
        if [[ -z "${pre_manual_map[$dep]:-}" ]]; then
            apt-mark auto "$dep" >/dev/null || true
        fi
    done

    echo ">> Preparing source tree at $LABWC_REPO_CLONE_DIR..."
    if [[ -d "$LABWC_REPO_CLONE_DIR/.git" ]]; then
        git -C "$LABWC_REPO_CLONE_DIR" fetch --tags --force
    else
        rm -rf "$LABWC_REPO_CLONE_DIR"
        git clone "$LABWC_REPO_URL" "$LABWC_REPO_CLONE_DIR"
    fi

    latest_tag="$(git -C "$LABWC_REPO_CLONE_DIR" tag --sort=-v:refname | head -n1)"
    if [[ -z "$latest_tag" ]]; then
        echo "ERROR: Could not resolve latest labwc tag from upstream repository."
        return 1
    fi

    echo ">> Building labwc tag: $latest_tag"
    git -C "$LABWC_REPO_CLONE_DIR" checkout -f "$latest_tag"

    # Configure, compile, and install labwc to the host filesystem.
    rm -rf "$LABWC_REPO_CLONE_DIR/build"
    meson setup "$LABWC_REPO_CLONE_DIR/build" "$LABWC_REPO_CLONE_DIR" --buildtype=release -Dxwayland=disabled
    ninja -C "$LABWC_REPO_CLONE_DIR/build"
    ninja -C "$LABWC_REPO_CLONE_DIR/build" install

    ldconfig

    echo ">> Cleaning up no-longer-needed build dependencies..."
    apt-get autoremove --purge -y
    apt-get clean
}

install_from_docker_package() {
    # Build a .deb in an isolated Debian container, then install it on host.
    local codename=""
    local docker_image=""
    local build_stamp=""
    local build_dir=""
    local package_path=""

    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: Docker CLI not found. Install Docker first or choose another labwc installation mode."
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: Docker daemon is not reachable. Ensure the docker service is running and this user can access it."
        return 1
    fi

    codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
    if [[ -z "$codename" ]]; then
        echo "ERROR: Could not determine VERSION_CODENAME from /etc/os-release."
        return 1
    fi

    docker_image="${LABWC_DOCKER_IMAGE:-debian:${codename}}"
    if [[ -z "$docker_image" ]]; then
        echo "ERROR: LABWC_DOCKER_IMAGE is set but empty."
        return 1
    fi

    build_stamp="$(date +%Y%m%d-%H%M%S)"
    build_dir="$LABWC_DOCKER_BUILD_ROOT/$build_stamp"

    mkdir -p "$build_dir"

    echo ">> Building labwc package in container image: $docker_image"
    docker run --rm \
        -e DEBIAN_FRONTEND=noninteractive \
        -e LABWC_REPO_URL="$LABWC_REPO_URL" \
        -e WLR_REPO_URL="$WLR_REPO_URL" \
        -e DOCKER_BUILD_DEPS="${DOCKER_BUILD_DEPS[*]}" \
        -e DOCKER_WLROOTS_SOURCE_DEPS="${DOCKER_WLROOTS_SOURCE_DEPS[*]}" \
        -v "$build_dir:/artifacts" \
        "$docker_image" \
        bash -lc '
            set -Eeuo pipefail
            apt-get update
            apt-get install -y --no-install-recommends $DOCKER_BUILD_DEPS

            git clone "$LABWC_REPO_URL" /tmp/labwc
            latest_tag="$(git -C /tmp/labwc tag --sort=-v:refname | head -n1)"
            if [[ -z "$latest_tag" ]]; then
                echo "ERROR: Could not resolve latest labwc tag from upstream repository."
                exit 1
            fi

            git -C /tmp/labwc checkout -f "$latest_tag"

            required_wlroots_dep="$(grep -o "wlroots-[0-9.]*" -m1 /tmp/labwc/meson.build || true)"
            if [[ -z "$required_wlroots_dep" ]]; then
                echo "ERROR: Could not determine required wlroots ABI from /tmp/labwc/meson.build."
                exit 1
            fi

            required_wlroots_pkg="lib${required_wlroots_dep}-dev"
            if apt-cache show "$required_wlroots_pkg" >/dev/null 2>&1; then
                echo ">> Installing distro wlroots package: $required_wlroots_pkg"
                apt-get install -y --no-install-recommends "$required_wlroots_pkg"
            else
                wlroots_ref="${required_wlroots_dep#wlroots-}"
                echo ">> Distro package $required_wlroots_pkg is unavailable. Building wlroots from source (ref: $wlroots_ref)."
                apt-get install -y --no-install-recommends $DOCKER_WLROOTS_SOURCE_DEPS

                git clone "$WLR_REPO_URL" /tmp/wlroots
                if ! git -C /tmp/wlroots checkout -f "$wlroots_ref"; then
                    if ! git -C /tmp/wlroots checkout -f "${wlroots_ref}.0"; then
                        echo "ERROR: Could not checkout wlroots ref $wlroots_ref or ${wlroots_ref}.0"
                        exit 1
                    fi
                fi

                meson setup /tmp/wlroots/build /tmp/wlroots -Dexamples=false -Dxwayland=disabled
                ninja -C /tmp/wlroots/build
                ninja -C /tmp/wlroots/build install
                ldconfig

                if ! pkg-config --exists "$required_wlroots_dep"; then
                    echo "ERROR: wlroots build/install succeeded but pkg-config cannot find $required_wlroots_dep"
                    exit 1
                fi
            fi

            meson setup /tmp/labwc/build /tmp/labwc --buildtype=release -Dxwayland=disabled
            ninja -C /tmp/labwc/build

            pkg_version="${latest_tag#v}"
            checkinstall --type=debian --install=no --fstrans=no --default --nodoc \
                --pkgname=labwc --pkgversion="$pkg_version" --pakdir=/artifacts \
                ninja -C /tmp/labwc/build install
        '

    package_path="$(find "$build_dir" -maxdepth 1 -type f -name 'labwc*.deb' | sort | tail -n1 || true)"
    if [[ -z "$package_path" ]]; then
        echo "ERROR: Docker build completed but no labwc .deb package was found in $build_dir."
        return 1
    fi

    # Install with apt so runtime dependencies are resolved consistently.
    echo ">> Installing built package: $package_path"
    apt-get update
    apt-get install -y "$package_path"

    echo ">> Installed labwc package built in Docker. Artifact retained at: $package_path"
}

copy_if_missing() {
    # Copy a config file only when the destination does not already exist.
    local src_file="$1"
    local dest_file="$2"

    if [[ -e "$dest_file" ]]; then
        echo ">> Keeping existing file: $dest_file"
        return 0
    fi

    install -Dm644 "$src_file" "$dest_file"
    if [[ "$dest_file" == *"/autostart" || "$dest_file" == *"/shutdown" || "$dest_file" == *"/environment" ]]; then
        chmod 755 "$dest_file"
    fi

    chown "$TARGET_USER:$TARGET_USER" "$dest_file"
    echo ">> Installed config file: $dest_file"
}

labwc_package_is_installed() {
    # Check the installed package database before using package-provided defaults.
    dpkg-query -W -f='${Status}' labwc 2>/dev/null | grep -q '^install ok installed$'
}

copy_labwc_configs() {
    # Prefer repository config overrides, then fall back to distro defaults.
    local copied=0
    local found_repo_files=0

    mkdir -p "$TARGET_LABWC_CONFIG_DIR"
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_LABWC_CONFIG_DIR"

    if [[ -d "$REPO_LABWC_CONFIG_DIR" ]]; then
        for file_name in "${LABWC_CONFIG_FILES[@]}"; do
            if [[ -f "$REPO_LABWC_CONFIG_DIR/$file_name" ]]; then
                found_repo_files=1
                copy_if_missing "$REPO_LABWC_CONFIG_DIR/$file_name" "$TARGET_LABWC_CONFIG_DIR/$file_name"
                copied=1
            fi
        done
    fi

    if [[ "$found_repo_files" -eq 0 ]]; then
        if labwc_package_is_installed && [[ -d "$DEFAULT_LABWC_CONFIG_DIR" ]]; then
            echo ">> No labwc config files found in repo .config/labwc, using defaults from $DEFAULT_LABWC_CONFIG_DIR"
            for file_name in "${LABWC_CONFIG_FILES[@]}"; do
                if [[ -f "$DEFAULT_LABWC_CONFIG_DIR/$file_name" ]]; then
                    copy_if_missing "$DEFAULT_LABWC_CONFIG_DIR/$file_name" "$TARGET_LABWC_CONFIG_DIR/$file_name"
                    copied=1
                fi
            done
        else
            echo ">> No labwc config files found in repo .config/labwc, and package defaults are unavailable until labwc is installed."
        fi
    fi

    if [[ "$copied" -eq 0 ]]; then
        echo ">> No labwc config files were copied (no matching source files found)."
    fi
}

main() {
    # Resolve installation mode, perform install, then initialize user config files.
    local install_mode="${LABWC_INSTALL_MODE:-}"

    case "$install_mode" in
        package|source|docker-package)
            ;;
        "")
            install_mode="$(prompt_install_mode)"
            ;;
        *)
            echo "ERROR: LABWC_INSTALL_MODE must be 'package', 'source', or 'docker-package' when set."
            exit 1
            ;;
    esac

    case "$install_mode" in
        package)
            install_from_package
            ;;
        source)
            install_from_source
            ;;
        docker-package)
            install_from_docker_package
            ;;
    esac

    copy_labwc_configs
    echo ">> labwc installation flow completed successfully."
}

main "$@"
