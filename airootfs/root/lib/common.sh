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

# Installer variables -- defaults only if not already set by the main script.
# The main installer (hyprflux-install.sh) declares these with proper defaults.
: "${INSTALL_TIMEZONE:=}"
: "${INSTALL_LOCALE:=en_US.UTF-8}"
: "${INSTALL_KEYMAP:=us}"
: "${INSTALL_HOSTNAME:=hyprflux}"
: "${INSTALL_USERNAME:=}"
: "${INSTALL_PASSWORD:=}"
: "${INSTALL_DISK:=}"
: "${INSTALL_BOOT_MODE:=}"
: "${INSTALL_HAS_NVIDIA:=no}"

# ============================================================================
# Error Handling
# ============================================================================

# Fatal error -- log, clean up, reset terminal, drop to shell for debugging
die() {
    # Stop any running progress display FIRST (before logging)
    if [[ -n "${_PROGRESS_PID:-}" ]]; then
        kill "$_PROGRESS_PID" 2>/dev/null || true
        wait "$_PROGRESS_PID" 2>/dev/null || true
        _PROGRESS_PID=""
    fi
    local failure_log="${INSTALL_LOG_DIR:-/var/log/hyprflux-installer}"
    stop_progress 2>/dev/null || true
    PROGRESS_LOG=""
    _PROGRESS_STATUS=""

    # Reset terminal: show cursor, clear attributes
    printf '%s' "${ANSI_SHOW_CURSOR:-$'\033[?25h'}"
    tput sgr0 2>/dev/null || true

    # Clear screen and show banner if available
    if [[ -n "${_BANNER_CACHE:-}" ]]; then
        printf '%s' "${ANSI_CLEAR_SCREEN:-$'\033[H\033[2J'}"
        printf '%s' "$_BANNER_CACHE"
    fi

    printf '\n'
    log_error "$@"
    printf '\n'
    log_error "Installation failed. Dropping to shell for debugging."
    log_error "To re-run: bash ~/hyprflux-install.sh"
    log_error "Logs: ${failure_log} (copy these before rebooting the live ISO)"
    printf '\n'

    # Drop to a subshell (not exec) so EXIT traps can still fire
    bash || true
    exit 1
}

# ============================================================================
# Validation
# ============================================================================

# Hostname: starts with letter, alphanumeric + hyphens, max 63 chars.
# "localhost" is rejected — it would collide with the loopback hostname
# entry that the installer writes to /etc/hosts.
validate_hostname() {
    local name="$1"
    [[ "$name" =~ ^[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && [[ "${name,,}" != "localhost" ]]
}

# Username: starts with lowercase letter, lowercase + digits + underscore/hyphen, max 32.
# "root" and any existing system account are rejected — useradd would fail
# or hijack an existing account (nobody, dbus, uuidd, ...).
validate_username() {
    local name="$1"
    [[ "$name" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || return 1
    [[ "$name" == "root" ]] && return 1
    id "$name" &>/dev/null && return 1
    return 0
}

# Password: at least 1 character (we don't enforce complexity -- user's choice).
# Colons are rejected: chpasswd uses 'user:password' framing, so a ':' in the
# password would silently truncate it and the login would never work.
validate_password() {
    local pass="$1"
    [[ -n "$pass" && "$pass" != *:* && "$pass" != *$'\n'* && "$pass" != *$'\r'* ]]
}

list_utf8_locales() {
    awk '{sub(/^#[[:space:]]*/, "")} $2 == "UTF-8" && $1 ~ /^[a-z]+_[A-Z]+/ { print $1 }' "$1" | sort -u
}

# Reuse only an unmodified checkout of the exact release and expected origin.
# Allow the installer's logs/ directory even when upstream does not ignore it;
# changed, foreign or otherwise untracked checkouts must be preserved instead.
checkout_matches_release() {
    local repo="$1" revision="$2"
    local -a command=(git -c "safe.directory=$repo" -c core.fsmonitor=false -C "$repo")
    [[ -d "$repo/.git" ]] || return 1
    [[ "$("${command[@]}" rev-parse HEAD 2>/dev/null)" == "$revision" ]] || return 1
    [[ "$("${command[@]}" remote get-url origin 2>/dev/null)" == https://github.com/ahmad9059/HyprFlux.git ]] || return 1
    "${command[@]}" diff --no-ext-diff --no-textconv --quiet || return 1
    "${command[@]}" diff --cached --no-ext-diff --no-textconv --quiet || return 1
    local untracked path
    untracked=$("${command[@]}" ls-files --others --exclude-standard) || return 1
    while IFS= read -r path; do
        [[ -z "$path" || "$path" == logs/* ]] || return 1
    done <<< "$untracked"
    return 0
}

# ============================================================================
# Network
# ============================================================================

# Check internet connectivity (returns 0 if online)
# Check DNS, HTTPS and certificates, not ICMP (often blocked on usable networks).
check_internet() {
    local endpoint
    for endpoint in https://archlinux.org/ https://geo.mirror.pkgbuild.com/core/os/x86_64/core.db; do
        if curl --fail --silent --location --head --connect-timeout 4 --max-time 8 \
            "$endpoint" -o /dev/null; then
            return 0
        fi
    done
    return 1
}

cancel_installation() {
    INSTALL_PASSWORD=""
    show_banner
    log_warn "Installation cancelled."
    exit 0
}

network_received_bytes() {
    local path value total=0
    for path in /sys/class/net/*/statistics/rx_bytes; do
        [[ "$path" == */lo/* ]] && continue
        read -r value < "$path" 2>/dev/null || continue
        [[ "$value" =~ ^[0-9]+$ ]] || continue
        total=$((total + value))
    done
    printf '%s\n' "$total"
}

record_install_metrics() {
    local stage="$1" started="$2" received_before="$3" received_after
    received_after=$(network_received_bytes)
    mkdir -p "$MOUNT_POINT/var/log/hyprflux-installer"
    # Includes DNS/Git/NTP and other guest traffic, not just package payloads.
    # Paired with the seed report, this supports honest future A/B comparisons.
    printf '%s\telapsed_seconds=%s\tnetwork_rx_bytes=%s\n' "$stage" \
        "$((SECONDS - started))" "$((received_after >= received_before ? received_after - received_before : 0))" \
        >> "$MOUNT_POINT/var/log/hyprflux-installer/performance.tsv"
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
    if [[ -d /sys/firmware/efi ]]; then
        echo "uefi"
    else
        echo "bios"
    fi
}

check_platform() {
    [[ "$(uname -m)" == x86_64 ]] || { echo 'Only x86_64 CPUs are supported.' >&2; return 1; }
    if [[ -r /sys/firmware/efi/fw_platform_size ]] && [[ $(</sys/firmware/efi/fw_platform_size) != 64 ]]; then
        echo '32-bit UEFI is unsupported; use 64-bit UEFI or legacy BIOS.' >&2
        return 1
    fi
    local variable enabled
    for variable in /sys/firmware/efi/efivars/SecureBoot-*; do
        [[ -r "$variable" ]] || continue
        enabled=$(od -An -t u1 -j 4 -N 1 "$variable") || return 1
        if [[ "${enabled//[[:space:]]/}" == 1 ]]; then
            echo 'Disable Secure Boot before installing the unsigned target bootloader.' >&2
            return 1
        fi
    done
    return 0
}

# ============================================================================
# Hardware Detection
# ============================================================================

# NVIDIA detection -- MUST be called on the live ISO, NOT inside chroot.
# The chroot has no PCI bus access.
detect_nvidia() {
    if lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -qi 'nvidia'; then
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
    if [[ "$disk" =~ [0-9]$ ]]; then
        echo "${disk}p"
    else
        echo "${disk}"
    fi
}

# Never infer disk parents by trimming digits: that corrupts nvme/mmc names
# and cannot represent device-mapper stacks. Reject mounted, read-only and
# live-media disks before destructive operations.
disk_is_installable() {
    local disk="$1" source ancestor mountpoint mounts topology node kind ancestors
    [[ -b "$disk" ]] || return 1
    [[ "$(lsblk -dnro TYPE "$disk")" == disk ]] || return 1
    [[ "$(lsblk -dnro RO "$disk")" == 0 ]] || return 1
    mounts=$(lsblk -nr -o MOUNTPOINTS "$disk") || return 1
    [[ -z "${mounts//[[:space:]]/}" ]] || return 1
    topology=$(lsblk -nrpo NAME,TYPE "$disk") || return 1
    [[ -n "$topology" ]] || return 1
    while read -r node kind; do
        # Unmounted crypt/LVM/RAID holders are not an unused physical disk.
        [[ -n "$node" && ( "$kind" == disk || "$kind" == part ) ]] || return 1
    done <<< "$topology"
    for mountpoint in /run/archiso/bootmnt /run/archiso/img_dev; do
        if ! source=$(findmnt -nro SOURCE --mountpoint "$mountpoint" 2>/dev/null); then
            # A mounted live filesystem that cannot be inspected is unsafe.
            mountpoint -q "$mountpoint" && return 1
            continue
        fi
        ancestors=$(lsblk -snrpo NAME "${source%%\[*}" 2>/dev/null) || return 1
        [[ -n "$ancestors" ]] || return 1
        while IFS= read -r ancestor; do
            [[ "$ancestor" != "$disk" ]] || return 1
        done <<< "$ancestors"
    done
    return 0
}

parent_disk() {
    local source="${1%%\[*}" disks topology
    topology=$(lsblk -snrpo NAME,TYPE "$source") || return 1
    disks=$(awk '
        $2 != "disk" && $2 != "part" { invalid=1 }
        $2 == "disk" { print $1 }
        END { if (invalid) exit 1 }
    ' <<< "$topology") || return 1
    [[ -n "$disks" && "$disks" != *$'\n'* ]] || return 1
    printf '%s\n' "$disks"
}

write_os_release() {
    local root="$1" temporary
    temporary=$(mktemp "$root/etc/os-release.XXXXXX") || return 1
    cat > "$temporary" <<'EOF'
NAME="HyprFlux"
PRETTY_NAME="HyprFlux Linux"
ID=hyprflux
ID_LIKE=arch
BUILD_ID=rolling
ANSI_COLOR="38;2;169;86;255"
HOME_URL="https://github.com/ahmad9059/HyprFlux"
DOCUMENTATION_URL="https://github.com/ahmad9059/HyprFlux"
SUPPORT_URL="https://github.com/ahmad9059/HyprFlux/issues"
BUG_REPORT_URL="https://github.com/ahmad9059/HyprFlux/issues"
LOGO=hyprflux-logo
EOF
    chmod 644 "$temporary"
    # Replace the /etc entry, never follow it into the package-owned vendor file.
    mv -fT -- "$temporary" "$root/etc/os-release"
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

# Pacstrap uses the LIVE pacman configuration; the build-time profile config
# and later target configuration do not enable concurrent base downloads.
# Change only this option, leaving signatures, repositories and timeouts intact.
configure_parallel_downloads() {
    local configuration="$1" candidate
    candidate=$(mktemp "${configuration}.XXXXXX") || return 1
    if awk '
        function emit() {
            if (options && !written) { print "ParallelDownloads = 5"; written=1 }
        }
        /^[[:space:]]*\[/ { emit(); options=($0 ~ /^[[:space:]]*\[options\][[:space:]]*$/) }
        options && /^[[:space:]]*#?[[:space:]]*ParallelDownloads[[:space:]]*=/ { next }
        { print }
        END { emit(); if (!written) exit 1 }
    ' "$configuration" > "$candidate"; then
        chmod --reference="$configuration" "$candidate" \
            && mv -f -- "$candidate" "$configuration" || { rm -f -- "$candidate"; return 1; }
    else
        rm -f -- "$candidate"
        return 1
    fi
}

# Use reflector to get fast mirrors (run in live env before pacstrap)
setup_mirrors() {
    log_step "Updating mirror list with reflector..."
    timeout 120 reflector \
        --latest 20 \
        --protocol https \
        --sort rate \
        --download-timeout 5 \
        --save /etc/pacman.d/mirrorlist 2>&1 | while IFS= read -r line; do
            log_cmd "$line"
        done || log_warn "Reflector failed or timed out"
    log_ok "Mirror list updated"
}

# Reflector must not truncate the last working mirror list on a timeout.
refresh_mirrors() {
    local destination="${1:-/etc/pacman.d/mirrorlist}" candidate
    candidate=$(mktemp "${destination}.XXXXXX") || return 1
    if timeout 45 reflector --latest 20 --protocol https --sort rate \
        --download-timeout 3 --save "$candidate" \
        && grep -Eq '^[[:space:]]*Server[[:space:]]*=' "$candidate"; then
        chmod 644 "$candidate"
        mv -f "$candidate" "$destination"
    else
        rm -f "$candidate"
        printf 'Mirror ranking unavailable; keeping existing mirrors.\n'
    fi
    if ! grep -Eq '^[[:space:]]*Server[[:space:]]*=' "$destination"; then
        printf 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' > "$destination"
    fi
}
