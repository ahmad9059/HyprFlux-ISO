#!/bin/bash
# ============================================================================
# hyprflux-install.sh -- HyprFlux Arch Linux Installer
# ============================================================================
# Main entry point for the HyprFlux installation.
#
# Installation Pipeline:
#   Step 0:  Network setup
#   Step 1:  Welcome prompt
#   Steps 2-6: Configuration (timezone, locale, keyboard, hostname, user)
#   Step 7:  Disk partitioning (auto/manual)
#   Step 8:  Install base system (pacstrap)
#   Step 9:  Configure base system (chroot: locale, bootloader, users)
#   Step 10: HyprFlux integration (Phase 5)
#   Step 11: Cleanup & reboot (Phase 5)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Source Libraries
# ============================================================================
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/common.sh"

# ============================================================================
# Configuration Variables (collected during installation)
# ============================================================================
INSTALL_TIMEZONE=""
INSTALL_LOCALE="en_US.UTF-8"
INSTALL_KEYMAP="us"
INSTALL_HOSTNAME="hyprflux"
INSTALL_USERNAME=""
INSTALL_PASSWORD=""
INSTALL_DISK=""
INSTALL_BOOT_MODE=""
INSTALL_HAS_NVIDIA="no"
USE_SWAP=false
SWAP_SIZE=0

# Partition variables (set during disk setup)
EFI_PART=""
BIOS_PART=""
SWAP_PART=""
ROOT_PART=""

# ============================================================================
# Initialize TUI
# ============================================================================
check_terminal_size

# Runtime dependency check: the TUI framework is built on gum + fzf, which
# must be present in the live environment (they are in packages.x86_64).
for _req in gum fzf; do
  if ! command -v "$_req" >/dev/null 2>&1; then
    printf '\n[ERROR] Required TUI dependency missing: %s\n' "$_req" >&2
    printf '        The live environment is broken — rebuild the ISO or install %s.\n' "$_req" >&2
    exit 1
  fi
done
unset _req

show_banner

# ============================================================================
# Error Trap
# ============================================================================
# ERR trap: clean up progress display, then die.
# die() also cleans up progress, but the trap fires first.
trap 'stop_progress 2>/dev/null || true; die "An unexpected error occurred on line $LINENO"' ERR

# ============================================================================
# Pre-flight: Detect hardware
# ============================================================================
set_status "Initializing..."

# Clean stale mounts from a previous (failed) install attempt so a re-run
# of the installer does not fail with "already mounted".
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    log_warn "Stale mount detected at $MOUNT_POINT — unmounting..."
    umount -R "$MOUNT_POINT" 2>/dev/null || true
fi
if mountpoint -q "${MOUNT_POINT}/boot" 2>/dev/null; then
    umount "${MOUNT_POINT}/boot" 2>/dev/null || true
fi
swapoff -a 2>/dev/null || true

tui_wait "Detecting hardware..." 2
INSTALL_BOOT_MODE=$(detect_boot_mode)
INSTALL_HAS_NVIDIA=$(detect_nvidia)
log_info "Boot mode: ${INSTALL_BOOT_MODE^^}"
log_info "NVIDIA GPU: ${INSTALL_HAS_NVIDIA}"
tui_wait "Ready" 1

# ============================================================================
# Step 0: Network Check
# ============================================================================
# Simple connectivity gate: ping 1.1.1.1. If it responds, proceed. No
# network configuration UI — the live ISO uses NetworkManager for Ethernet
# (DHCP) out of the box; WiFi users should connect via nmtui beforehand.
# ============================================================================
check_network() {
    show_banner
    set_status "Checking network connection..."

    if tui_spinner "Checking internet connection (ping 1.1.1.1)..." check_internet; then
        log_ok "Internet connection OK."
        return 0
    fi

    # NetworkManager may still be bringing up the link — retry briefly.
    local attempt
    for attempt in 1 2 3 4 5; do
        log_warn "No response from 1.1.1.1 (attempt ${attempt}/5). Retrying..."
        sleep 3
        if check_internet; then
            log_ok "Internet connection OK."
            return 0
        fi
    done

    show_banner
    tui_error "No internet connection (ping 1.1.1.1 failed)."
    tui_print "HyprFlux requires an internet connection to install."
    tui_print ""
    tui_print "If you are on WiFi, connect first with: nmtui"
    exit 1
}

# ============================================================================
# Step 1: Welcome
# ============================================================================
step_welcome() {
    show_banner

    tui_print ""
    tui_print_bold "Welcome to the HyprFlux Installer!"
    tui_print ""
    tui_print "This will install Arch Linux with the HyprFlux Hyprland desktop."
    tui_print ""
    tui_print "Requirements:"
    tui_print "  - Internet connection (repos are cloned during install)"
    tui_print "  - A disk to install to (will be formatted)"
    tui_print "  - At least 20GB free disk space"
    tui_print ""

    tui_yesno "Continue with installation?" || {
        show_banner
        log_warn "Installation cancelled by user."
        exit 0
    }
}

# ============================================================================
# Step 2: Timezone
# ============================================================================
step_timezone() {
    show_banner
    set_status "Timezone Configuration"

    # Try auto-detect via IP geolocation
    local detected=""
    detected=$(curl -s --max-time 5 https://ipapi.co/timezone 2>/dev/null || true)

    if [[ -n "$detected" ]] && [[ -f "/usr/share/zoneinfo/$detected" ]]; then
        tui_print "Detected timezone: ${detected}"
        tui_print ""
        if tui_yesno "Use ${detected}?"; then
            INSTALL_TIMEZONE="$detected"
            return 0
        fi
    fi

    show_banner
    set_status "Timezone Configuration"

    # Build timezone list
    local timezones=()
    while IFS= read -r zone; do
        [[ -f "/usr/share/zoneinfo/$zone" ]] && timezones+=("$zone")
    done < <(find /usr/share/zoneinfo -type f -not -path "*posix*" -not -path "*right*" | sed 's|/usr/share/zoneinfo/||' | sort)

    local selection
    selection=$(printf '%s\n' "${timezones[@]}" | tui_search "Timezone") || {
        INSTALL_TIMEZONE="UTC"
        return 0
    }

    if [[ -n "$selection" ]] && [[ -f "/usr/share/zoneinfo/$selection" ]]; then
        INSTALL_TIMEZONE="$selection"
    else
        INSTALL_TIMEZONE="UTC"
    fi
}

# ============================================================================
# Step 3: Locale
# ============================================================================
step_locale() {
    show_banner
    set_status "Locale Configuration"

    # Build the locale list from /etc/locale.gen which is the authoritative
    # source for what locale-gen accepts.  Each entry in locale.gen is:
    #    <locale-name> <charmap>
    # e.g.  "#en_US.UTF-8 UTF-8"  or  "#ur_PK UTF-8"
    #
    # We extract every UTF-8 locale, keep the first column (the locale name)
    # exactly as-is, and present that to the user.  This guarantees the value
    # selected by the user matches a real locale.gen entry.
    local gen="/etc/locale.gen"

    # If the live ISO ships a tiny stub, use the full glibc file instead.
    if [[ -f /usr/share/i18n/SUPPORTED ]] \
        && [[ $(grep -c 'UTF-8' "$gen" 2>/dev/null) -lt 10 ]]; then
        gen="/usr/share/i18n/SUPPORTED"
    fi

    # Extract all UTF-8 locale names (first column) — both forms:
    #   en_US.UTF-8 UTF-8   →  en_US.UTF-8
    #   ur_PK UTF-8         →  ur_PK
    local locale_list
    locale_list=$(awk '/UTF-8/ && /^[a-z]/ { print $1 }' "$gen" | sort -u)

    INSTALL_LOCALE=$(printf '%s\n' "$locale_list" | tui_search "Locale") || {
        INSTALL_LOCALE="en_US.UTF-8"
    }
}

# ============================================================================
# Step 4: Keyboard Layout
# ============================================================================
step_keyboard() {
    show_banner
    set_status "Keyboard Layout"

    local common=(
        "us" "uk" "de" "fr" "es" "pt-latin1" "it" "br-abnt2"
        "ru" "jp106" "kr" "pl" "se" "nl" "dvorak" "colemak"
        "[Show all layouts...]"
    )

    local keymap
    keymap=$(tui_menu "Select keyboard layout:" "${common[@]}") || keymap="us"

    if [[ "$keymap" == "[Show all layouts...]" ]]; then
        show_banner
        set_status "Keyboard Layout"
        keymap=$(localectl list-keymaps 2>/dev/null | tui_search "Keyboard") || keymap="us"
    fi

    INSTALL_KEYMAP="$keymap"
    loadkeys "$INSTALL_KEYMAP" 2>/dev/null || true
}

# ============================================================================
# Step 5: Hostname
# ============================================================================
step_hostname() {
    while true; do
        show_banner
        set_status "Hostname"

        INSTALL_HOSTNAME=$(tui_input "Hostname" "hyprflux")

        # Strip leading/trailing whitespace (gum may add spaces)
        INSTALL_HOSTNAME="${INSTALL_HOSTNAME#"${INSTALL_HOSTNAME%%[![:space:]]*}"}"
        INSTALL_HOSTNAME="${INSTALL_HOSTNAME%"${INSTALL_HOSTNAME##*[![:space:]]}"}"

        [[ -z "$INSTALL_HOSTNAME" ]] && INSTALL_HOSTNAME="hyprflux"

        if validate_hostname "$INSTALL_HOSTNAME"; then
            break
        fi

        tui_error "Invalid hostname. Use only letters, numbers, and hyphens. Must start with a letter."
    done
}

# ============================================================================
# Step 6: User Account
# ============================================================================
step_user() {
    # Username
    while true; do
        show_banner
        set_status "User Account"

        INSTALL_USERNAME=$(tui_input "Username" "")

        if [[ -z "$INSTALL_USERNAME" ]]; then
            tui_error "Username cannot be empty."
            continue
        fi

        if validate_username "$INSTALL_USERNAME"; then
            break
        fi

        tui_error "Invalid username. Lowercase letters, numbers, underscores, hyphens only."
    done

    # Password
    while true; do
        show_banner
        set_status "Set your password"

        local pass1 pass2
        pass1=$(tui_password "Password")
        pass2=$(tui_password "Confirm")

        if [[ "$pass1" == "$pass2" ]]; then
            if validate_password "$pass1"; then
                INSTALL_PASSWORD="$pass1"
                break
            fi
            tui_error "Password cannot be empty or contain ':'."
        else
            tui_error "Passwords do not match. Try again."
        fi
    done
}

# ============================================================================
# Step 7: Disk Setup
# ============================================================================
step_disk_auto() {
    show_banner
    set_status "Disk Setup (Automatic)"

    # Never offer the device the live ISO is running from — wiping it would
    # kill the installer mid-flight. Derived from the archiso boot mount.
    local live_disk=""
    if findmnt -n -o SOURCE /run/archiso/bootmnt &>/dev/null; then
        live_disk=$(findmnt -n -o SOURCE /run/archiso/bootmnt | sed -E 's/[0-9]+$//; s/p$//')
    fi
    [[ -n "$live_disk" ]] && log_warn "Excluding live-ISO device ${live_disk} from disk list."

    local disk_list=()
    while IFS= read -r line; do
        local dev size model
        dev=$(printf '%s' "$line" | awk '{print $1}')
        size=$(printf '%s' "$line" | awk '{print $2}')
        model=$(printf '%s' "$line" | awk '{$1=$2=""; print $0}' | xargs)
        [[ -z "$dev" ]] && continue
        [[ -n "$live_disk" && "$dev" == "$live_disk" ]] && continue
        disk_list+=("$dev ($size) ${model:-Unknown}")
    done < <(lsblk -d -p -n -o NAME,SIZE,MODEL 2>/dev/null | grep -v -E 'loop|sr|rom|boot')

    if [[ ${#disk_list[@]} -eq 0 ]]; then
        die "No disks found!"
    fi

    # Warn (not abort) when the chosen disk looks too small for HyprFlux.
    # Parse size strings like "119.2G", "512M" down to GiB.
    local warn_dev disk_size_gib=0
    for line in "${disk_list[@]}"; do
        warn_dev=$(printf '%s' "$line" | awk '{print $1}')
        local dsz
        dsz=$(printf '%s' "$line" | awk '{print $2}')
        case "$dsz" in
            *T)  disk_size_gib=$(awk -v v="${dsz%T}" 'BEGIN { printf "%d", v*1024 }') ;;
            *G)  disk_size_gib=$(awk -v v="${dsz%G}" 'BEGIN { printf "%d", v }') ;;
            *M)  disk_size_gib=$(awk -v v="${dsz%M}" 'BEGIN { printf "%d", v/1024 }') ;;
        esac
        if (( disk_size_gib > 0 && disk_size_gib < 25 )); then
            log_warn "Disk ${warn_dev} is only ~${disk_size_gib} GiB — HyprFlux needs ~25 GiB+."
        fi
    done
    unset warn_dev disk_size_gib dsz

    printf '%s%sWARNING: The selected disk will be completely erased!%s\n\n' "$PAD" "${RED}" "${RESET}"

    local selection
    selection=$(tui_menu "Select disk:" "${disk_list[@]}") || return 1

    INSTALL_DISK=$(printf '%s' "$selection" | awk '{print $1}')

    # Confirmation
    show_banner
    set_status "Confirm Disk"
    printf '%s%sAll data on %s will be destroyed!%s\n\n' "$PAD" "${RED}" "$INSTALL_DISK" "${RESET}"
    local confirm
    confirm=$(tui_input "Type 'yes' to confirm" "")
    if [[ "$confirm" != "yes" ]]; then
        return 1
    fi

    # Swap
    show_banner
    set_status "Swap Configuration"
    USE_SWAP=false
    SWAP_SIZE=0
    tui_print "Swap is recommended for systems with less than 16GB RAM."
    tui_print ""
    if tui_yesno "Create a swap partition?"; then
        USE_SWAP=true
        # Validate: positive integer only (protects sgdisk from garbage input)
        while true; do
            SWAP_SIZE=$(tui_input "Swap size (GB)" "4")
            [[ -z "$SWAP_SIZE" ]] && SWAP_SIZE="4"
            if [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] && (( SWAP_SIZE > 0 )); then
                break
            fi
            tui_error "Invalid swap size '${SWAP_SIZE}' — enter a positive number (e.g. 4, 8, 16)."
        done
    fi

    # Partitioning -- use progress display for all disk ops
    local part_prefix
    part_prefix=$(get_part_prefix "$INSTALL_DISK")

    start_progress "Partitioning ${INSTALL_DISK}..."

    set +e
    (
        printf '==> Wiping disk %s\n' "$INSTALL_DISK"
        sgdisk -Z "$INSTALL_DISK" 2>&1 || true
        wipefs -a "$INSTALL_DISK" 2>&1 || true

        if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
            printf '==> Creating GPT partition table (UEFI)\n'
            sgdisk -o "$INSTALL_DISK"
            printf '==> Creating EFI partition (1024MB)\n'
            sgdisk -n 1:0:+1024M -t 1:ef00 -c 1:"EFI" "$INSTALL_DISK"

            local next_part=2
            if [[ "$USE_SWAP" == true ]]; then
                printf '==> Creating Swap partition (%sGB)\n' "$SWAP_SIZE"
                sgdisk -n 2:0:+${SWAP_SIZE}G -t 2:8200 -c 2:"Swap" "$INSTALL_DISK"
                next_part=3
            fi
            printf '==> Creating Root partition (remaining space)\n'
            sgdisk -n ${next_part}:0:0 -t ${next_part}:8300 -c ${next_part}:"Root" "$INSTALL_DISK"
        else
            printf '==> Creating GPT partition table (BIOS)\n'
            sgdisk -o "$INSTALL_DISK"
            printf '==> Creating BIOS boot partition (1MB)\n'
            sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS Boot" "$INSTALL_DISK"

            local next_part=2
            if [[ "$USE_SWAP" == true ]]; then
                printf '==> Creating Swap partition (%sGB)\n' "$SWAP_SIZE"
                sgdisk -n 2:0:+${SWAP_SIZE}G -t 2:8200 -c 2:"Swap" "$INSTALL_DISK"
                next_part=3
            fi
            printf '==> Creating Root partition (remaining space)\n'
            sgdisk -n ${next_part}:0:0 -t ${next_part}:8300 -c ${next_part}:"Root" "$INSTALL_DISK"
        fi

        printf '==> Notifying kernel of partition changes\n'
        partprobe "$INSTALL_DISK" 2>&1 || true
        udevadm settle 2>/dev/null || true
        sleep 2
    ) >> "$PROGRESS_LOG" 2>&1
    local part_status=$?
    set -e

    stop_progress

    if [[ $part_status -ne 0 ]]; then
        die "Disk partitioning failed on ${INSTALL_DISK}."
    fi

    # Set partition variables after partitioning
    if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
        EFI_PART="${part_prefix}1"
        if [[ "$USE_SWAP" == true ]]; then
            SWAP_PART="${part_prefix}2"
            ROOT_PART="${part_prefix}3"
        else
            ROOT_PART="${part_prefix}2"
        fi
    else
        BIOS_PART="${part_prefix}1"
        if [[ "$USE_SWAP" == true ]]; then
            SWAP_PART="${part_prefix}2"
            ROOT_PART="${part_prefix}3"
        else
            ROOT_PART="${part_prefix}2"
        fi
    fi

    # Wait for the kernel to expose the new partition nodes (partprobe is
    # async on USB/SATA; mkfs on a missing node would die confusingly).
    local _pdev
    for _pdev in "${EFI_PART}" "${SWAP_PART}" "${ROOT_PART}"; do
        [[ -z "$_pdev" ]] && continue
        local _w=0
        while [[ ! -b "$_pdev" ]]; do
            _w=$((_w + 1))
            (( _w > 30 )) && break
            sleep 1
        done
        if [[ ! -b "$_pdev" ]]; then
            die "Partition ${_pdev} never appeared after partitioning."
        fi
    done
    unset _pdev _w

    # Format partitions with progress
    start_progress "Formatting partitions..."

    set +e
    (
        if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
            printf '==> Formatting EFI partition: %s\n' "$EFI_PART"
            mkfs.vfat -F 32 "$EFI_PART" 2>&1
        fi

        if [[ "$USE_SWAP" == true ]]; then
            printf '==> Setting up swap: %s\n' "$SWAP_PART"
            mkswap "$SWAP_PART" 2>&1
        fi

        printf '==> Formatting root partition: %s\n' "$ROOT_PART"
        mkfs.ext4 -F "$ROOT_PART" 2>&1
    ) >> "$PROGRESS_LOG" 2>&1
    local fmt_status=$?
    set -e

    stop_progress

    if [[ $fmt_status -ne 0 ]]; then
        die "Partition formatting failed."
    fi

    # Mount partitions with progress
    start_progress "Mounting partitions..."

    set +e
    (
        printf '==> Mounting root at %s\n' "$MOUNT_POINT"
        mkdir -p "$MOUNT_POINT"
        mount "$ROOT_PART" "$MOUNT_POINT"

        if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
            printf '==> Mounting EFI at %s/boot\n' "$MOUNT_POINT"
            mkdir -p "${MOUNT_POINT}/boot"
            mount "$EFI_PART" "${MOUNT_POINT}/boot"
        fi

        if [[ "$USE_SWAP" == true ]]; then
            printf '==> Activating swap: %s\n' "$SWAP_PART"
            swapon "$SWAP_PART"
        fi

        printf '==> All partitions mounted successfully\n'
    ) >> "$PROGRESS_LOG" 2>&1
    local mnt_status=$?
    set -e

    stop_progress

    if [[ $mnt_status -ne 0 ]]; then
        die "Failed to mount partitions."
    fi

    show_banner
    log_ok "Disk setup complete. Partitions mounted at $MOUNT_POINT"
    tui_wait "" 1
}

step_disk_manual() {
    show_banner
    set_status "Disk Setup (Manual)"

    if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
        tui_print_bold "UEFI Mode Detected"
        tui_print ""
        tui_print "Please create and mount these partitions:"
        tui_print ""
        tui_print "  EFI:  >= 512MB  -> mkfs.vfat -F 32 /dev/XXX"
        tui_print "  Swap: optional  -> mkswap /dev/XXX && swapon /dev/XXX"
        tui_print "  Root: remaining -> mkfs.ext4 /dev/XXX"
        tui_print ""
        tui_print "Mount: Root -> $MOUNT_POINT, EFI -> $MOUNT_POINT/boot"
    else
        tui_print_bold "BIOS/Legacy Mode Detected"
        tui_print ""
        tui_print "Please create and mount these partitions:"
        tui_print ""
        tui_print "  BIOS boot: 1MB (GPT only)"
        tui_print "  Swap: optional  -> mkswap /dev/XXX && swapon /dev/XXX"
        tui_print "  Root: remaining -> mkfs.ext4 /dev/XXX"
        tui_print ""
        tui_print "Mount: Root -> $MOUNT_POINT"
    fi
    tui_print ""
    tui_print "Commands: lsblk, cfdisk, fdisk, parted"
    tui_print ""
    printf '%s%sPress Enter to drop to shell...%s' "$PAD" "${DIM}" "${RESET}"
    printf '%s' "${ANSI_SHOW_CURSOR}"
    read -r < /dev/tty

    mkdir -p "$MOUNT_POINT"

    bash || true
    printf '%s' "${ANSI_HIDE_CURSOR}"

    show_banner

    if ! mountpoint -q "$MOUNT_POINT"; then
        die "$MOUNT_POINT is not mounted! Cannot continue."
    fi

    if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
        if ! mountpoint -q "${MOUNT_POINT}/boot"; then
            die "${MOUNT_POINT}/boot is not mounted! EFI partition required for UEFI."
        fi
    fi

    INSTALL_DISK=$(findmnt -n -o SOURCE "$MOUNT_POINT" | sed 's/[0-9]*$//' | sed 's/p$//')
    ROOT_PART=$(findmnt -n -o SOURCE "$MOUNT_POINT")

    log_ok "Partitions verified."
}

step_disk() {
    show_banner
    set_status "Disk Setup"

    local mode
    mode=$(tui_menu "Disk Partitioning:" \
        "Automatic (wipe entire disk)" \
        "Manual (partition yourself)") || mode="Automatic (wipe entire disk)"

    case "$mode" in
        "Automatic"*)
            step_disk_auto || step_disk
            ;;
        "Manual"*)
            step_disk_manual
            ;;
    esac
}

# ============================================================================
# Step 8: Install Base System (pacstrap)
# ============================================================================
step_base_install() {
    # Prepare mirror list and vconsole before starting progress
    mkdir -p "${MOUNT_POINT}/etc/pacman.d"
    printf 'KEYMAP=%s\n' "${INSTALL_KEYMAP}" > "${MOUNT_POINT}/etc/vconsole.conf"

    local base_pkgs=(
        base linux linux-firmware
        grub efibootmgr
        networkmanager
        sudo vim nano git zsh
        base-devel
        amd-ucode intel-ucode
        libnewt pciutils
        curl wget
    )

    # --- Phase 1: Optimize mirrors ---
    start_progress "Finding fastest mirrors..."

    timeout 120 reflector --latest 10 --protocol https --sort rate --download-timeout 5 \
        --save /etc/pacman.d/mirrorlist >> "$PROGRESS_LOG" 2>&1 || {
        printf 'Reflector timed out or failed, using existing mirrors\n' >> "$PROGRESS_LOG"
    }

    # Guard: a zero-byte/empty mirrorlist would make every pacstrap retry
    # fail with a confusing error. Fall back to the ISO's default mirrors.
    if [[ ! -s /etc/pacman.d/mirrorlist ]]; then
        printf 'Reflector produced an empty mirrorlist — restoring default mirrors\n' >> "$PROGRESS_LOG"
        cp /etc/pacman.d/mirrorlist.pacnew /etc/pacman.d/mirrorlist 2>/dev/null \
            || cp /usr/share/pacman/mirrorlist /etc/pacman.d/mirrorlist 2>/dev/null || true
    fi
    cp /etc/pacman.d/mirrorlist "${MOUNT_POINT}/etc/pacman.d/mirrorlist" || true

    stop_progress

    # --- Phase 2: pacstrap with retries ---
    local max_retries=3
    local retry_count=0
    local pacstrap_success=false

    while [[ $retry_count -lt $max_retries ]]; do
        retry_count=$((retry_count + 1))

        if [[ $retry_count -gt 1 ]]; then
            # Refresh mirrors between retries
            start_progress "Refreshing mirrors (attempt ${retry_count}/${max_retries})..."
            timeout 60 reflector --latest 5 --protocol https --sort rate --download-timeout 5 \
                --save /etc/pacman.d/mirrorlist >> "$PROGRESS_LOG" 2>&1 || true
            cp /etc/pacman.d/mirrorlist "${MOUNT_POINT}/etc/pacman.d/mirrorlist" || true
            stop_progress
        fi

        start_progress "Installing base system (attempt ${retry_count}/${max_retries})..."

        set +e
        pacstrap -K "$MOUNT_POINT" "${base_pkgs[@]}" >> "$PROGRESS_LOG" 2>&1
        local pacstrap_status=$?
        set -e

        stop_progress

        if [[ $pacstrap_status -eq 0 ]]; then
            pacstrap_success=true
            break
        fi

        if [[ $retry_count -lt $max_retries ]]; then
            show_banner
            log_warn "pacstrap failed (attempt ${retry_count}/${max_retries})."
            tui_wait "Retrying in 5 seconds..." 5
        fi
    done

    if [[ "$pacstrap_success" != true ]]; then
        show_banner
        log_error "pacstrap failed after ${max_retries} attempts!"
        tui_print ""
        tui_print "Possible solutions:"
        tui_print "  1. Check your internet connection"
        tui_print "  2. Try again later (mirrors may be overloaded)"
        tui_print "  3. Run manually: pacstrap -K $MOUNT_POINT base linux linux-firmware"
        die "pacstrap failed! Check your internet connection and try again."
    fi

    # --- Phase 3: Generate fstab ---
    # Overwrite (not append): a stale fstab from a failed earlier run would
    # otherwise produce duplicate mount entries.
    show_banner
    set_status "Generating fstab..."
    rm -f "${MOUNT_POINT}/etc/fstab"
    genfstab -U "$MOUNT_POINT" > "${MOUNT_POINT}/etc/fstab" 2>/dev/null || true
    if [[ ! -s "${MOUNT_POINT}/etc/fstab" ]]; then
        die "fstab generation produced an empty file — cannot continue."
    fi
    log_ok "Base system installed successfully."
    tui_wait "" 1
}

# ============================================================================
# Step 9: Configure Base System (arch-chroot)
# ============================================================================
step_configure_system() {
    start_progress "Configuring system..."

    set +e
    (
        # Timezone
        printf '==> Configuring timezone: %s\n' "${INSTALL_TIMEZONE}"
        arch-chroot "$MOUNT_POINT" ln -sf "/usr/share/zoneinfo/${INSTALL_TIMEZONE}" /etc/localtime
        # hwclock can fail in VMs/containers without an RTC device — non-fatal.
        arch-chroot "$MOUNT_POINT" hwclock --systohc 2>/dev/null || true
        # CRITICAL: force the chroot clock from the live env. pacman PGP
        # signature windows (chaotic-aur, mirrors) fail instantly on a wrong
        # clock, and a broken hwclock leaves the target in the past.
        arch-chroot "$MOUNT_POINT" date -s "@$(date +%s)" 2>/dev/null || true

        # -------------------------------------------------------------------
        # Locale configuration
        # -------------------------------------------------------------------
        # Design:
        #   LANG     = en_US.UTF-8   (system UI, logs, tools — always English)
        #   LC_TIME  = <user locale>  (date/time in user's regional format)
        #
        # The target's /etc/locale.gen is the full glibc file (~500 entries,
        # installed by pacstrap).  Entries have two forms:
        #   #en_US.UTF-8 UTF-8      (locale name includes .UTF-8)
        #   #ur_PK UTF-8            (locale name is bare, charset follows)
        #
        # The user-selected INSTALL_LOCALE matches the first column exactly
        # because step_locale() parsed it from the same file format.
        # -------------------------------------------------------------------
        printf '==> Configuring locale: %s\n' "${INSTALL_LOCALE}"

        local target_gen="${MOUNT_POINT}/etc/locale.gen"

        # Uncomment a locale entry in the target's locale.gen.
        # $1 = locale name exactly as it appears in column 1 of locale.gen
        enable_locale() {
            local name="$1"
            local bare="${name%.UTF-8}"   # strip .UTF-8 if present

            # Try the name as given (e.g. "en_US.UTF-8")
            if grep -q "^#${name} " "$target_gen"; then
                sed -i "s/^#${name} /${name} /" "$target_gen"
                return 0
            fi

            # Try bare form (e.g. "ur_PK")
            if grep -q "^#${bare} " "$target_gen"; then
                sed -i "s/^#${bare} /${bare} /" "$target_gen"
                return 0
            fi

            # Already enabled — nothing to do
            if grep -q "^${name} \|^${bare} " "$target_gen"; then
                return 0
            fi

            # Not present at all — append it
            printf '%s UTF-8\n' "${name}" >> "$target_gen"
        }

        # Always enable en_US.UTF-8
        enable_locale "en_US.UTF-8"

        # Enable user's locale (no-op when same as en_US.UTF-8)
        if [[ "${INSTALL_LOCALE}" != "en_US.UTF-8" ]]; then
            enable_locale "${INSTALL_LOCALE}"
        fi

        # Generate enabled locales
        arch-chroot "$MOUNT_POINT" locale-gen

        # Resolve the canonical locale name that glibc generated.
        # If user picked "ur_PK" (bare), the actual usable name is "ur_PK"
        # not "ur_PK.UTF-8".  Verify with locale -a inside chroot.
        local resolved_locale="${INSTALL_LOCALE}"
        if [[ "${INSTALL_LOCALE}" != "en_US.UTF-8" ]]; then
            local bare="${INSTALL_LOCALE%.UTF-8}"
            # Check what locale -a actually reports for this locale
            local found
            found=$(arch-chroot "$MOUNT_POINT" locale -a 2>/dev/null \
                    | grep -i "^${bare}" | head -1) || true
            if [[ -n "$found" ]]; then
                resolved_locale="$found"
            fi
        fi

        # Write /etc/locale.conf
        {
            printf 'LANG=en_US.UTF-8\n'
            if [[ "${resolved_locale}" != "en_US.UTF-8" ]]; then
                printf 'LC_TIME=%s\n' "${resolved_locale}"
            fi
        } > "${MOUNT_POINT}/etc/locale.conf"
        
        printf '==> locale.conf written:\n'
        cat "${MOUNT_POINT}/etc/locale.conf"

        # Keyboard
        printf '==> Configuring keyboard: %s\n' "${INSTALL_KEYMAP}"
        printf 'KEYMAP=%s\n' "${INSTALL_KEYMAP}" > "${MOUNT_POINT}/etc/vconsole.conf"

        # Hostname
        printf '==> Configuring hostname: %s\n' "${INSTALL_HOSTNAME}"
        printf '%s\n' "${INSTALL_HOSTNAME}" > "${MOUNT_POINT}/etc/hostname"
        printf '127.0.0.1   localhost\n::1         localhost\n127.0.1.1   %s.localdomain %s\n' \
            "${INSTALL_HOSTNAME}" "${INSTALL_HOSTNAME}" > "${MOUNT_POINT}/etc/hosts"

        # -------------------------------------------------------------------
        # HyprFlux distribution branding
        # -------------------------------------------------------------------
        # /etc/os-release is the single source of truth for the distro name
        # shown by fastfetch/neofetch/lsb_release/motd and every tool that
        # reports "Arch Linux". ID=hyprflux follows the EndeavourOS/CachyOS
        # precedent (the live tooling already handles arbitrary IDs; the
        # fastfetch configs in the dots ship a custom HyprFlux logo).
        printf '==> Applying HyprFlux distribution branding\n'
        cat > "${MOUNT_POINT}/etc/os-release" << 'OS_RELEASE_EOF'
NAME="HyprFlux"
PRETTY_NAME="HyprFlux Linux"
ID=hyprflux
BUILD_ID=rolling
ANSI_COLOR="38;2;169;86;255"
HOME_URL="https://github.com/ahmad9059/HyprFlux"
DOCUMENTATION_URL="https://github.com/ahmad9059/HyprFlux"
SUPPORT_URL="https://github.com/ahmad9059/HyprFlux/issues"
BUG_REPORT_URL="https://github.com/ahmad9059/HyprFlux/issues"
PRIVACY_POLICY_URL="https://github.com/ahmad9059/HyprFlux"
LOGO=hyprflux-logo
OS_RELEASE_EOF
        cat > "${MOUNT_POINT}/etc/lsb-release" << 'LSB_RELEASE_EOF'
LSB_VERSION=1.4
DISTRIB_ID=HyprFlux
DISTRIB_RELEASE=rolling
DISTRIB_DESCRIPTION="HyprFlux Linux"
LSB_RELEASE_EOF
        # Login banner (tty consoles)
        printf 'HyprFlux Linux \\r (\\l)\\n\\n' > "${MOUNT_POINT}/etc/issue"
        # GRUB boot menu title (grub-mkconfig is regenerated by module 08)
        arch-chroot "$MOUNT_POINT" sed -i \
            's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="HyprFlux"/' /etc/default/grub 2>/dev/null || true

        # -------------------------------------------------------------------
        # Root password + disk modules
        # -------------------------------------------------------------------
        # The config subshell runs with set +e — a silent chpasswd failure
        # leaves pacstrap's LOCKED root shadow (root:! ...) and the user is
        # locked out of the emergency console. Verify and hard-fail.
        printf '==> Setting root password\n'
        if ! printf '%s:%s\n' "root" "${INSTALL_PASSWORD}" | arch-chroot "$MOUNT_POINT" chpasswd; then
            printf 'ERROR: root chpasswd failed — cannot continue.\n'
            exit 1
        fi
        arch-chroot "$MOUNT_POINT" passwd -u root 2>/dev/null || true

        # CRITICAL for VM installs: mkinitcpio's `autodetect` hook can miss
        # virtio/NVMe/SATA disk modules when the initramfs is rebuilt in the
        # chroot, leaving the kernel unable to find the root device at boot
        # ("Failed to start Cleaning Up and Shutting Down Daemons" +
        # emergency mode). Explicitly include the common disk stacks.
        printf '==> Ensuring disk modules in mkinitcpio\n'
        arch-chroot "$MOUNT_POINT" sed -i \
            's/^MODULES=.*/MODULES=(virtio_blk virtio_pci virtio_scsi nvme ahci)/' \
            /etc/mkinitcpio.conf 2>/dev/null || \
            printf 'MODULES=(virtio_blk virtio_pci virtio_scsi nvme ahci)\n' \
                >> "${MOUNT_POINT}/etc/mkinitcpio.conf"
        # Rebuild NOW with the explicit modules (module 09 rebuilds later too —
        # this guarantees the bootable initramfs exists even if Phase B skips it).
        arch-chroot "$MOUNT_POINT" mkinitcpio -P 2>/dev/null || true

        # User creation
        printf '==> Creating user: %s\n' "${INSTALL_USERNAME}"
        arch-chroot "$MOUNT_POINT" useradd -m -G wheel -s /bin/bash "${INSTALL_USERNAME}"
        if ! printf '%s:%s\n' "${INSTALL_USERNAME}" "${INSTALL_PASSWORD}" | arch-chroot "$MOUNT_POINT" chpasswd; then
            printf 'ERROR: user chpasswd failed — cannot continue.\n'
            exit 1
        fi

        # Sudo
        printf '==> Configuring sudo\n'
        arch-chroot "$MOUNT_POINT" sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

        # Pacman enhancements
        printf '==> Configuring pacman\n'
        arch-chroot "$MOUNT_POINT" sed -i 's/^#Color/Color/' /etc/pacman.conf
        arch-chroot "$MOUNT_POINT" sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
        arch-chroot "$MOUNT_POINT" sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
        arch-chroot "$MOUNT_POINT" sed -i '/\[multilib\]/,/Include/{s/^#//}' /etc/pacman.conf

        # GRUB -- most failure-prone step, log carefully.
        # A silent failure here ships a non-bootable system, so this is the
        # only step in Step 9 that FAILS the install (after one retry + a
        # --removable fallback which works on systems without NVRAM support).
        printf '==> Installing GRUB bootloader\n'
        local grub_ok=false
        if [[ "${INSTALL_BOOT_MODE}" == "uefi" ]]; then
            if arch-chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB 2>&1; then
                grub_ok=true
            else
                printf 'WARNING: first grub-install attempt failed — retrying...\n'
                if arch-chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB 2>&1; then
                    grub_ok=true
                elif arch-chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable 2>&1; then
                    printf 'NOTE: installed GRUB in removable-mode (no NVRAM entry) — still bootable.\n'
                    grub_ok=true
                fi
            fi
        else
            if arch-chroot "$MOUNT_POINT" grub-install --target=i386-pc "${INSTALL_DISK}" 2>&1; then
                grub_ok=true
            else
                printf 'WARNING: first grub-install attempt failed — retrying...\n'
                arch-chroot "$MOUNT_POINT" grub-install --target=i386-pc "${INSTALL_DISK}" 2>&1 \
                    && grub_ok=true
            fi
        fi

        if [[ "$grub_ok" != true ]]; then
            printf 'ERROR: grub-install failed on every attempt — target would not boot.\n'
            exit 1
        fi

        arch-chroot "$MOUNT_POINT" grub-mkconfig -o /boot/grub/grub.cfg 2>&1
        if [[ $? -ne 0 ]]; then
            printf 'ERROR: grub-mkconfig failed — target would not boot.\n'
            exit 1
        fi

        # Services
        printf '==> Enabling NetworkManager\n'
        arch-chroot "$MOUNT_POINT" systemctl enable NetworkManager

        printf '==> System configuration complete\n'
    ) >> "$PROGRESS_LOG" 2>&1
    local config_status=$?
    set -e

    stop_progress

    if [[ $config_status -ne 0 ]]; then
        die "System configuration failed. Check the log for details."
    fi

    show_banner
    log_ok "System configured successfully."
    tui_wait "" 1
}

# ============================================================================
# Step 10: HyprFlux integration (runs INSIDE chroot during installation)
# ============================================================================
# Clones the HyprFlux repo (base-installer/ + base-dots/ are merged subdirs)
# into the target system, then runs the chroot wrapper (Phase A: base-installer
# scripts, Phase B: dotfiles modules, Phase C: services, Phase D: first-boot
# fixup). Everything except dbus-dependent settings is configured NOW; the
# Phase D autostart entry applies gsettings/nwg-look/pipewire-user on first
# login to the desktop.
# ============================================================================
step_install_hyprflux() {
    local user_home="${MOUNT_POINT}/home/${INSTALL_USERNAME}"
    local wrapper_log="${user_home}/HyprFlux/logs/iso-wrapper.log"

    # DNS for chroot (needed for git clone + package downloads inside chroot).
    # The live env always has a resolv.conf; if it is missing, skip — the
    # chroot install would fail later and surface a clear error then.
    if [[ -f /etc/resolv.conf ]]; then
        cp --remove-destination /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf" 2>/dev/null || true
    fi

    # Clone the merged HyprFlux repository (base-installer + base-dots inside)
    start_progress "Cloning HyprFlux repository..."

    set +e
    (
        [[ -d "${user_home}/HyprFlux" ]] && rm -rf "${user_home}/HyprFlux"

        local _clone_attempt=0
        local _clone_ok=false
        while (( _clone_attempt < 3 )); do
            _clone_attempt=$((_clone_attempt + 1))
            printf '==> Cloning HyprFlux repository (attempt %d/3)...\n' "$_clone_attempt"
            if timeout 300 git clone --depth=1 https://github.com/ahmad9059/HyprFlux.git "${user_home}/HyprFlux" 2>&1; then
                _clone_ok=true
                break
            fi
            [[ -d "${user_home}/HyprFlux" ]] && rm -rf "${user_home}/HyprFlux"
            sleep 5
        done

        if [[ "$_clone_ok" != true ]]; then
            printf 'ERROR: Failed to clone HyprFlux after 3 attempts\n'
            exit 1
        fi
        printf '==> HyprFlux cloned successfully\n'
    ) >> "$PROGRESS_LOG" 2>&1
    local clone_status=$?
    set -e

    stop_progress

    if [[ $clone_status -ne 0 ]]; then
        die "Failed to clone HyprFlux repository. Check internet connection."
    fi

    show_banner
    tui_spinner "Setting file permissions..." arch-chroot "$MOUNT_POINT" chown -R         "${INSTALL_USERNAME}:${INSTALL_USERNAME}"         "/home/${INSTALL_USERNAME}" || true

    # Copy the chroot wrapper into the target and run it. It orchestrates:
    #   Phase A: base-installer install scripts (packages, yay, AUR, zsh...)
    #   Phase B: HyprFlux dotfiles modules 01-16
    #   Phase C: enable sddm/bluetooth/NetworkManager + graphical.target
    #   Phase D: first-boot autostart fixup (gsettings/nwg-look/pipewire)
    #
    # NOTE: the wrapper goes to /root, NOT /tmp — arch-chroot mounts a fresh
    # tmpfs over the target's /tmp (arch-install-scripts chroot_add_mount
    # "tmp $1/tmp"), so anything copied to ${MOUNT_POINT}/tmp is invisible
    # inside the chroot (bash exits 127 "No such file or directory").
    mkdir -p "${user_home}/HyprFlux/logs"
    cp "${SCRIPT_DIR}/lib/hyprflux-chroot-wrapper.sh" \
        "${MOUNT_POINT}/root/hyprflux-chroot-wrapper.sh"
    chmod 755 "${MOUNT_POINT}/root/hyprflux-chroot-wrapper.sh"

    show_banner
    set_status "Installing HyprFlux (packages, config, themes)..."
    tui_print "This takes 20-60 minutes depending on internet speed."
    tui_print "Live progress is shown below; full log saved to ~/HyprFlux/logs/iso-wrapper.log"
    tui_print ""

    start_progress "Installing HyprFlux..."

    set +e
    (
        arch-chroot "$MOUNT_POINT" /bin/bash /root/hyprflux-chroot-wrapper.sh \
            "${INSTALL_USERNAME}" "${INSTALL_HAS_NVIDIA}"
    ) | tee "${wrapper_log}" >> "$PROGRESS_LOG" 2>&1
    local wrapper_status=${PIPESTATUS[0]}
    set -e

    stop_progress

    rm -f "${MOUNT_POINT}/root/hyprflux-chroot-wrapper.sh"
    chown "${INSTALL_USERNAME}:${INSTALL_USERNAME}" "${wrapper_log}" 2>/dev/null || true

    if [[ $wrapper_status -ne 0 ]]; then
        show_banner
        tui_error "HyprFlux installation failed (exit ${wrapper_status})."
        tui_print "Full log: ${wrapper_log}"
        die "HyprFlux installation failed. See ${wrapper_log}"
    fi

    # Bootability verification BEFORE the user reboots — the #1 cause of the
    # post-install emergency mode is a root device the kernel can't find.
    # Check all three links in the chain: grub.cfg root= UUID, the real
    # partition UUID, and the disk modules inside the initramfs.
    show_banner
    set_status "Verifying bootability..."
    _boot_ok=true

    _root_uuid=$(blkid -s UUID -o value "$ROOT_PART" 2>/dev/null)
    _grub_root=$(grep -oE 'root=UUID=[a-fA-F0-9-]+' "${MOUNT_POINT}/boot/grub/grub.cfg" 2>/dev/null | head -1 | cut -d= -f3)

    if [[ -n "$_grub_root" ]] && [[ "$_grub_root" == "$_root_uuid" ]]; then
        log_ok "GRUB root=UUID matches the root partition ($_root_uuid)."
    else
        _boot_ok=false
        log_warn "GRUB root=UUID ($_grub_root) does NOT match root partition ($_root_uuid)."
        log_warn "Fix in chroot: grub-mkconfig -o /boot/grub/grub.cfg"
    fi

    if lsinitcpio "${MOUNT_POINT}/boot/initramfs-linux.img" 2>/dev/null \
        | grep -qE 'virtio_blk|nvme|ahci|sd_mod'; then
        log_ok "Initramfs contains disk modules."
    else
        _boot_ok=false
        log_warn "Initramfs MISSING disk modules (virtio/nvme/ahci) — root device may not appear at boot."
        log_warn "Fix in chroot: MODULES=(virtio_blk virtio_pci virtio_scsi nvme ahci) in mkinitcpio.conf + mkinitcpio -P"
    fi

    if [[ "$_boot_ok" == true ]]; then
        log_ok "Bootability verified — safe to reboot."
    else
        tui_error "Bootability issues found — the system may drop to emergency mode."
        tui_print "The debug shell is available: exit it to continue to reboot anyway."
    fi
    unset _boot_ok _root_uuid _grub_root

    # Leave a boot-debug cheat-sheet in the installed system: if the first
    # boot still lands in emergency mode, these commands (run from the live
    # ISO, which auto-mounts to /mnt/archinstall) reveal the broken link.
    cat > "${MOUNT_POINT}/root/boot-debug.txt" << 'DEBUG_EOF'
If the installed system drops to emergency mode, boot the live ISO and run:

  arch-chroot /mnt/archinstall /bin/bash -c "
    grep -oE 'root=UUID=[a-f0-9-]+' /boot/grub/grub.cfg | head -2
    blkid | grep -E 'ext4|swap'
    cat /etc/fstab
    grep '^MODULES' /etc/mkinitcpio.conf
    lsinitcpio /boot/initramfs-linux.img | grep -oE 'virtio_blk|nvme|ahci' | sort -u
    passwd -S root
  "

Common causes:
- grub.cfg root=UUID != real UUID  -> chroot: grub-mkconfig -o /boot/grub/grub.cfg
- initramfs missing disk modules   -> MODULES=(virtio_blk virtio_pci virtio_scsi nvme ahci) + mkinitcpio -P
- root locked                      -> chroot: passwd root
DEBUG_EOF
    tui_wait "" 1
}

# ============================================================================
# Step 11: Cleanup & Reboot
# ============================================================================
step_cleanup_reboot() {
    show_banner
    sync

    tui_success_box "HyprFlux Installation Complete!"

    tui_print "Arch Linux + HyprFlux desktop have been installed."
    tui_print ""
    tui_print "Please:"
    tui_print "  1. Remove the USB drive / ISO"
    tui_print "  2. Press Enter to reboot"
    tui_print ""
    printf '%s%sAfter reboot:%s\n' "$PAD" "${YELLOW}" "${RESET}"
    tui_print "  - Login with username: ${INSTALL_USERNAME}"
    tui_print "  - SDDM starts automatically and launches Hyprland"
    tui_print "  - First-boot setup (GTK theme, pipewire) runs automatically"
    tui_print "  - If anything is missing, re-run: bash ~/HyprFlux/install.sh"
    tui_print ""
    printf '%s%sPress Enter to reboot...%s' "$PAD" "${DIM}" "${RESET}"
    printf '%s' "${ANSI_SHOW_CURSOR}"
    read -r < /dev/tty
    printf '%s' "${ANSI_HIDE_CURSOR}"

    show_banner
    tui_spinner "Unmounting partitions..." umount -R "$MOUNT_POINT" || true
    swapoff -a 2>/dev/null || true

    show_banner
    set_status "Rebooting..."
    log_info "Remove installation media now!"
    tui_wait "Rebooting in 5 seconds..." 5
    reboot
}

# ============================================================================
# Main Installation Flow
# ============================================================================
main() {
    check_network          # Step 0
    step_welcome           # Step 1
    step_timezone          # Step 2
    step_locale            # Step 3
    step_keyboard          # Step 4
    step_hostname          # Step 5
    step_user              # Step 6
    step_disk              # Step 7
    step_base_install      # Step 8
    step_configure_system  # Step 9
    step_install_hyprflux  # Step 10
    step_cleanup_reboot    # Step 11
}

main
