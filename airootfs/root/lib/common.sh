#!/bin/bash
# ============================================================================
# lib/common.sh -- Shared installer utilities
# ============================================================================
# Provides validation, detection, and error handling used throughout the
# installer. Requires tui.sh to be sourced first (for log_* functions).
# ============================================================================

# Guard against double-sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# ============================================================================
# Constants
# ============================================================================
MOUNT_POINT="/mnt/archinstall"

# Installer variables (set during config prompts in Phase 4)
INSTALL_TIMEZONE=""
INSTALL_LOCALE=""
INSTALL_KEYBOARD=""
INSTALL_HOSTNAME=""
INSTALL_USERNAME=""
INSTALL_PASSWORD=""
INSTALL_DISK=""
INSTALL_BOOT_MODE=""
INSTALL_PARTITION_MODE=""    # "auto" or "manual"
INSTALL_HAS_NVIDIA="no"

# ============================================================================
# Error Handling
# ============================================================================

# Fatal error -- log, reset terminal, drop to shell for debugging
die() {
    echo ""
    log_error "$@"
    echo ""
    log_error "Installation failed. Dropping to shell for debugging."
    log_error "To re-run: bash ~/hyprflux-install.sh"
    echo ""
    # Reset terminal attributes
    tput sgr0 2>/dev/null || true
    exec /bin/bash
}

# ============================================================================
# Validation
# ============================================================================

# Hostname: starts with letter, alphanumeric + hyphens, max 63 chars
validate_hostname() {
    local name="$1"
    [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,62}$ ]]
}

# Username: starts with lowercase letter, lowercase + digits + underscore/hyphen, max 32
validate_username() {
    local name="$1"
    [[ "$name" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]
}

# Password: at least 1 character (we don't enforce complexity -- user's choice)
validate_password() {
    local pass="$1"
    [[ -n "$pass" ]]
}

# ============================================================================
# Network
# ============================================================================

# Check internet connectivity (returns 0 if online)
check_internet() {
    ping -c 1 -W 5 archlinux.org &>/dev/null
}

# Wait for internet with retries
wait_for_internet() {
    local max_attempts="${1:-30}"
    local attempt=1

    while ! check_internet; do
        if [[ $attempt -ge $max_attempts ]]; then
            return 1
        fi
        log_info "Waiting for network... (attempt ${attempt}/${max_attempts})"
        sleep 2
        attempt=$((attempt + 1))
    done
    return 0
}

# ============================================================================
# Boot Mode Detection
# ============================================================================

detect_boot_mode() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        echo "uefi"
    else
        echo "bios"
    fi
}

# ============================================================================
# Hardware Detection
# ============================================================================

# NVIDIA detection -- MUST be called on the live ISO, NOT inside chroot.
# The chroot has no PCI bus access.
detect_nvidia() {
    if lspci 2>/dev/null | grep -qi 'nvidia'; then
        echo "yes"
    else
        echo "no"
    fi
}

# ============================================================================
# Disk Helpers
# ============================================================================

# Get partition prefix (nvme/mmcblk use "p" separator, sd* don't)
# Example: /dev/nvme0n1 -> /dev/nvme0n1p
#          /dev/sda     -> /dev/sda
get_part_prefix() {
    local disk="$1"
    if [[ "$disk" == *nvme* || "$disk" == *mmcblk* || "$disk" == *loop* ]]; then
        echo "${disk}p"
    else
        echo "${disk}"
    fi
}

# List available disks (excluding loop, sr, ram devices)
list_disks() {
    lsblk -dpno NAME,SIZE,TYPE 2>/dev/null \
        | awk '$3 == "disk" { print $1, $2 }' \
        | grep -v -E '(loop|sr[0-9]|ram[0-9])'
}

# ============================================================================
# Pacman Mirror Setup
# ============================================================================

# Use reflector to get fast mirrors (run in live env before pacstrap)
setup_mirrors() {
    log_step "Updating mirror list with reflector..."
    reflector \
        --latest 20 \
        --protocol https \
        --sort rate \
        --save /etc/pacman.d/mirrorlist 2>&1 | while IFS= read -r line; do
            log_cmd "$line"
        done
    log_ok "Mirror list updated"
}
