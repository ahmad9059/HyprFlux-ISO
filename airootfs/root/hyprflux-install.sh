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
tui_wait "Detecting hardware..." 2
INSTALL_BOOT_MODE=$(detect_boot_mode)
INSTALL_HAS_NVIDIA=$(detect_nvidia)
log_info "Boot mode: ${INSTALL_BOOT_MODE^^}"
log_info "NVIDIA GPU: ${INSTALL_HAS_NVIDIA}"
tui_wait "Ready" 1

# ============================================================================
# Step 0: Network Setup
# ============================================================================
setup_ethernet() {
    local ifaces
    ifaces=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep ethernet | cut -d: -f1 || true)

    if [[ -z "$ifaces" ]]; then
        return 1
    fi

    for iface in $ifaces; do
        nmcli device connect "$iface" 2>/dev/null && break || true
    done

    tui_wait "Waiting for DHCP lease..." 5
}

setup_wifi() {
    show_banner
    set_status "WiFi Setup"

    nmcli device wifi rescan 2>/dev/null || true
    tui_wait "Scanning WiFi networks..." 3

    local networks=()
    while IFS=: read -r ssid signal security; do
        [[ -z "$ssid" ]] && continue
        networks+=("${ssid} (${signal}% ${security})")
    done < <(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | \
        grep -v '^:' | sort -t: -k2 -rn | head -20)

    if [[ ${#networks[@]} -eq 0 ]]; then
        tui_error "No WiFi networks found."
        return 1
    fi

    show_banner
    set_status "WiFi Setup"

    local selection
    selection=$(tui_menu "Select WiFi Network:" "${networks[@]}") || return 1

    local ssid
    ssid=$(printf '%s' "$selection" | sed 's/ (.*$//')
    [[ -z "$ssid" ]] && return 1

    show_banner
    set_status "WiFi Setup"

    local password
    password=$(tui_password "WiFi Password") || return 1

    show_banner
    tui_spinner "Connecting to '$ssid'..." nmcli device wifi connect "$ssid" password "$password" || true
}

setup_network() {
    show_banner
    set_status "Network Setup"

    tui_spinner "Checking internet connection..." check_internet && {
        return 0
    }

    log_warn "No internet connection detected."
    tui_spinner "Starting NetworkManager..." systemctl start NetworkManager || true
    tui_wait "Waiting for NetworkManager..." 2

    while true; do
        show_banner
        set_status "Network Setup"

        local choice
        choice=$(tui_menu "Network Setup:" \
            "Ethernet (auto DHCP)" \
            "WiFi" \
            "Manual (drop to shell)" \
            "Skip (not recommended)") || choice="Skip"

        case "$choice" in
            "Ethernet"*)
                show_banner
                set_status "Connecting via Ethernet..."
                setup_ethernet
                ;;
            "WiFi"*)
                setup_wifi
                ;;
            "Manual"*)
                show_banner
                set_status "Manual Network Setup"
                tui_print "Use: nmcli, nmtui, or ip commands"
                tui_print "Type 'exit' when connected."
                tui_print ""
                bash || true
                ;;
            "Skip"*)
                return 0
                ;;
        esac

        show_banner
        if tui_spinner "Checking internet connection..." check_internet; then
            return 0
        fi

        show_banner
        tui_error "Still no internet connection."
    done
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
            if [[ -n "$pass1" ]]; then
                INSTALL_PASSWORD="$pass1"
                break
            fi
            tui_error "Password cannot be empty."
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

    local disk_list=()
    while IFS= read -r line; do
        local dev size model
        dev=$(printf '%s' "$line" | awk '{print $1}')
        size=$(printf '%s' "$line" | awk '{print $2}')
        model=$(printf '%s' "$line" | awk '{$1=$2=""; print $0}' | xargs)
        [[ -z "$dev" ]] && continue
        disk_list+=("$dev ($size) ${model:-Unknown}")
    done < <(lsblk -d -p -n -o NAME,SIZE,MODEL 2>/dev/null | grep -v -E 'loop|sr|rom|boot')

    if [[ ${#disk_list[@]} -eq 0 ]]; then
        die "No disks found!"
    fi

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
        SWAP_SIZE=$(tui_input "Swap size (GB)" "4")
        [[ -z "$SWAP_SIZE" ]] && SWAP_SIZE="4"
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
    show_banner
    set_status "Generating fstab..."
    genfstab -U "$MOUNT_POINT" >> "${MOUNT_POINT}/etc/fstab" 2>/dev/null
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
        arch-chroot "$MOUNT_POINT" hwclock --systohc

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

        # Root password
        printf '==> Setting root password\n'
        printf '%s:%s\n' "root" "${INSTALL_PASSWORD}" | arch-chroot "$MOUNT_POINT" chpasswd

        # User creation
        printf '==> Creating user: %s\n' "${INSTALL_USERNAME}"
        arch-chroot "$MOUNT_POINT" useradd -m -G wheel -s /bin/bash "${INSTALL_USERNAME}"
        printf '%s:%s\n' "${INSTALL_USERNAME}" "${INSTALL_PASSWORD}" | arch-chroot "$MOUNT_POINT" chpasswd

        # Sudo
        printf '==> Configuring sudo\n'
        arch-chroot "$MOUNT_POINT" sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

        # Pacman enhancements
        printf '==> Configuring pacman\n'
        arch-chroot "$MOUNT_POINT" sed -i 's/^#Color/Color/' /etc/pacman.conf
        arch-chroot "$MOUNT_POINT" sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
        arch-chroot "$MOUNT_POINT" sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
        arch-chroot "$MOUNT_POINT" sed -i '/\[multilib\]/,/Include/{s/^#//}' /etc/pacman.conf

        # GRUB -- most failure-prone step, log carefully
        printf '==> Installing GRUB bootloader\n'
        if [[ "${INSTALL_BOOT_MODE}" == "uefi" ]]; then
            arch-chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB 2>&1
        else
            arch-chroot "$MOUNT_POINT" grub-install --target=i386-pc "${INSTALL_DISK}" 2>&1
        fi
        local grub_rc=$?
        if [[ $grub_rc -ne 0 ]]; then
            printf 'WARNING: grub-install exited with code %d\n' "$grub_rc"
        fi
        arch-chroot "$MOUNT_POINT" grub-mkconfig -o /boot/grub/grub.cfg 2>&1

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
# Step 10: Prepare HyprFlux installation for first-boot
# ============================================================================
# Clones repos into the target system and creates a first-boot script that
# runs HyprFlux/install.sh on the user's first tty1 login after reboot.
# ============================================================================
step_install_hyprflux() {
    local user_home="${MOUNT_POINT}/home/${INSTALL_USERNAME}"

    # DNS for chroot (needed for git clone inside chroot)
    cp --remove-destination /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf"

    # Clone repositories with progress display
    start_progress "Cloning HyprFlux repositories..."

    set +e
    (
        arch_hypr_dir="${user_home}/Arch-Hyprland"
        [[ -d "${arch_hypr_dir}" ]] && rm -rf "${arch_hypr_dir}"

        printf '==> Cloning Arch-Hyprland repository...\n'
        if ! timeout 300 git clone --depth=1 https://github.com/ahmad9059/Arch-Hyprland.git "${arch_hypr_dir}" 2>&1; then
            printf 'ERROR: Failed to clone Arch-Hyprland\n'
            exit 1
        fi
        printf '==> Arch-Hyprland cloned successfully\n'

        [[ -d "${user_home}/HyprFlux" ]] && rm -rf "${user_home}/HyprFlux"

        printf '==> Cloning HyprFlux repository...\n'
        if ! timeout 300 git clone --depth=1 https://github.com/ahmad9059/HyprFlux.git "${user_home}/HyprFlux" 2>&1; then
            printf 'ERROR: Failed to clone HyprFlux\n'
            exit 1
        fi
        printf '==> HyprFlux cloned successfully\n'
    ) >> "$PROGRESS_LOG" 2>&1
    local clone_status=$?
    set -e

    stop_progress

    if [[ $clone_status -ne 0 ]]; then
        die "Failed to clone repositories. Check internet connection."
    fi

    show_banner
    tui_spinner "Setting file permissions..." arch-chroot "$MOUNT_POINT" chown -R \
        "${INSTALL_USERNAME}:${INSTALL_USERNAME}" \
        "/home/${INSTALL_USERNAME}" || true

    show_banner
    set_status "Configuring first-boot installer..."

    # Create first-boot installer script
    cat > "${user_home}/.hyprflux-firstboot.sh" << 'FIRSTBOOT_EOF'
#!/bin/bash
# HyprFlux First-Boot Installer
MARKER="$HOME/.hyprflux-install-done"
[[ -f "$MARKER" ]] && return 0
[[ "$(tty)" != "/dev/tty1" ]] && return 0

# Center output (same formula as the TUI: 66-col banner centered)
_cols=$(tput cols 2>/dev/null || echo 80)
_lpad=$(( (_cols - 66) / 2 ))
(( _lpad < 0 )) && _lpad=0
_pad=$(printf "%*s" "$_lpad" "")

echo ""
echo "${_pad}=============================================="
echo "${_pad}  Welcome to HyprFlux!"
echo "${_pad}=============================================="
echo ""
echo "${_pad}  Starting HyprFlux installation..."
echo "${_pad}  This will take 20-60 minutes."
echo "${_pad}  Please do NOT interrupt the process."
echo ""
sleep 3

cd "$HOME" || exit 1
if [[ -f "$HOME/HyprFlux/install.sh" ]]; then
    bash "$HOME/HyprFlux/install.sh"
    INSTALL_EXIT=$?

    if [[ $INSTALL_EXIT -eq 0 ]]; then
        touch "$MARKER"
        echo ""
        echo "${_pad}  Installation Complete!"
        echo "${_pad}  To start Hyprland desktop, type: Hyprland"
        echo "${_pad}  Or reboot and login again."
        echo ""
    else
        echo ""
        echo "${_pad}  Installation had errors. Try: bash ~/HyprFlux/install.sh"
        echo ""
    fi
else
    echo ""
    echo "${_pad}  ERROR: HyprFlux installer not found!"
    echo "${_pad}  Fix: git clone https://github.com/ahmad9059/HyprFlux.git"
    echo "${_pad}        then: bash ~/HyprFlux/install.sh"
    echo ""
fi

sed -i '/hyprflux-firstboot/d' "$HOME/.bash_profile" 2>/dev/null || true
FIRSTBOOT_EOF
    # Not marked executable -- always sourced from .bash_profile

    cat > "${user_home}/.bash_profile" << 'PROFILE_EOF'
[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"
if [[ -f "$HOME/.hyprflux-firstboot.sh" && ! -f "$HOME/.hyprflux-install-done" ]]; then
    [[ "$(tty)" == "/dev/tty1" ]] && source "$HOME/.hyprflux-firstboot.sh"
fi
PROFILE_EOF

    arch-chroot "$MOUNT_POINT" chown \
        "${INSTALL_USERNAME}:${INSTALL_USERNAME}" \
        "/home/${INSTALL_USERNAME}/.bash_profile" \
        "/home/${INSTALL_USERNAME}/.hyprflux-firstboot.sh" 2>/dev/null || true

    log_ok "HyprFlux configured for first-boot installation."
    tui_wait "" 1
}

# ============================================================================
# Step 11: Cleanup & Reboot
# ============================================================================
step_cleanup_reboot() {
    show_banner
    sync

    tui_success_box "Base Installation Complete!"

    tui_print "Base Arch Linux has been installed."
    tui_print ""
    tui_print "Please:"
    tui_print "  1. Remove the USB drive / ISO"
    tui_print "  2. Press Enter to reboot"
    tui_print ""
    printf '%s%sAfter reboot:%s\n' "$PAD" "${YELLOW}" "${RESET}"
    tui_print "  - Login with username: ${INSTALL_USERNAME}"
    tui_print "  - HyprFlux installer starts automatically on tty1"
    tui_print "  - Takes 20-60 minutes (downloads packages)"
    tui_print "  - Do NOT interrupt -- let it complete"
    tui_print "  - After completion, type 'Hyprland' to start desktop"
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
    setup_network          # Step 0
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
