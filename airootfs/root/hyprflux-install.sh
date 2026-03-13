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
setup_output_area
set_status "Initializing..."

# ============================================================================
# Error Trap
# ============================================================================
trap 'die "An unexpected error occurred on line $LINENO"' ERR

# ============================================================================
# Pre-flight: Detect hardware
# ============================================================================
INSTALL_BOOT_MODE=$(detect_boot_mode)
INSTALL_HAS_NVIDIA=$(detect_nvidia)
log_info "Boot mode: ${INSTALL_BOOT_MODE^^}"
log_info "NVIDIA GPU: ${INSTALL_HAS_NVIDIA}"

# ============================================================================
# Step 0: Network Setup
# ============================================================================
setup_ethernet() {
    log_step "Connecting via Ethernet..."
    local ifaces
    ifaces=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | grep ethernet | cut -d: -f1 || true)

    if [[ -z "$ifaces" ]]; then
        log_error "No Ethernet interfaces found."
        return 1
    fi

    for iface in $ifaces; do
        log_info "Trying $iface..."
        nmcli device connect "$iface" 2>/dev/null && break || true
    done

    sleep 5
}

setup_wifi() {
    log_step "Scanning for WiFi networks..."
    nmcli device wifi rescan 2>/dev/null || true
    sleep 3

    # Parse available networks into array
    local networks=()
    while IFS=: read -r ssid signal security; do
        [[ -z "$ssid" ]] && continue
        networks+=("${ssid} (${signal}% ${security})")
    done < <(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | \
        grep -v '^:' | sort -t: -k2 -rn | head -20)

    if [[ ${#networks[@]} -eq 0 ]]; then
        log_error "No WiFi networks found."
        return 1
    fi

    local selection
    selection=$(tui_menu "Select WiFi Network" "${networks[@]}") || return 1

    # Extract SSID from selection (remove signal/security info)
    local ssid
    ssid=$(echo "$selection" | sed 's/ ([^)]*%)$//')

    if [[ -z "$ssid" ]]; then
        return 1
    fi

    local password
    password=$(tui_password "Enter password for '$ssid'") || return 1

    log_step "Connecting to '$ssid'..."
    nmcli device wifi connect "$ssid" password "$password" 2>&1 || true
    sleep 5
}

setup_network() {
    set_status "Checking network..."

    if check_internet; then
        log_ok "Internet connection detected."
        return 0
    fi

    log_warn "No internet connection detected."

    # Start NetworkManager
    systemctl start NetworkManager 2>/dev/null || true
    sleep 2

    while true; do
        local choice
        choice=$(dlg_menu "Network Setup" \
            "Ethernet (auto DHCP)" \
            "WiFi" \
            "Manual (drop to shell)" \
            "Skip (not recommended)") || choice="Skip"

        case "$choice" in
            "Ethernet"*)
                setup_ethernet
                ;;
            "WiFi"*)
                setup_wifi
                ;;
            "Manual"*)
                log_step "Dropping to shell. Type 'exit' when connected."
                log_info "Use: nmcli, nmtui, or ip commands"
                bash || true
                show_banner
                setup_output_area
                ;;
            "Skip"*)
                log_warn "Proceeding without internet. Installation may fail."
                return 0
                ;;
        esac

        if check_internet; then
            log_ok "Internet connection established!"
            return 0
        fi

        log_error "Still no internet connection."
    done
}

# ============================================================================
# Step 1: Welcome
# ============================================================================
step_welcome() {
    set_status "Welcome"

    echo ""
    echo -e "  ${WHITE}Welcome to the HyprFlux Installer!${RESET}"
    echo ""
    echo "  This will install Arch Linux with the HyprFlux Hyprland desktop."
    echo ""
    echo "  Requirements:"
    echo "    - Internet connection (repos are cloned during install)"
    echo "    - A disk to install to (will be formatted)"
    echo "    - At least 20GB free disk space"
    echo ""

    tui_yesno "Continue with installation?" || {
        log_warn "Installation cancelled by user."
        exit 0
    }

    log_ok "Installation confirmed."
}

# ============================================================================
# Step 2: Timezone
# ============================================================================
step_timezone() {
    set_status "Timezone Configuration"

    # Try auto-detect via IP geolocation
    local detected=""
    detected=$(curl -s --max-time 5 https://ipapi.co/timezone 2>/dev/null || true)

    if [[ -n "$detected" ]] && [[ -f "/usr/share/zoneinfo/$detected" ]]; then
        echo ""
        echo -e "  Detected timezone: ${CYAN}$detected${RESET}"
        if tui_yesno "Is this correct?"; then
            INSTALL_TIMEZONE="$detected"
            log_ok "Timezone: $INSTALL_TIMEZONE"
            return 0
        fi
    fi

    # Build list of all timezones (Region/City format)
    local timezones=()
    while IFS= read -r zone; do
        # Skip posix, right, and non-file entries
        [[ -f "/usr/share/zoneinfo/$zone" ]] && timezones+=("$zone")
    done < <(find /usr/share/zoneinfo -type f -not -path "*posix*" -not -path "*right*" | sed 's|/usr/share/zoneinfo/||' | sort)

    # Searchable timezone selection
    local selection
    selection=$(printf '%s\n' "${timezones[@]}" | tui_search "Search timezone (e.g., Asia/Karachi, America/New_York):") || {
        log_warn "Using default timezone: UTC"
        INSTALL_TIMEZONE="UTC"
        return 0
    }

    if [[ -n "$selection" ]] && [[ -f "/usr/share/zoneinfo/$selection" ]]; then
        INSTALL_TIMEZONE="$selection"
        log_ok "Timezone: $INSTALL_TIMEZONE"
    else
        log_warn "Invalid timezone selected, using UTC"
        INSTALL_TIMEZONE="UTC"
    fi
}

# ============================================================================
# Step 3: Locale
# ============================================================================
step_locale() {
    set_status "Locale Configuration"

    # Comprehensive list of common UTF-8 locales
    local locales=(
        "af_ZA.UTF-8" "ar_AE.UTF-8" "ar_BH.UTF-8" "ar_DZ.UTF-8" "ar_EG.UTF-8"
        "ar_IQ.UTF-8" "ar_JO.UTF-8" "ar_KW.UTF-8" "ar_LB.UTF-8" "ar_LY.UTF-8"
        "ar_MA.UTF-8" "ar_OM.UTF-8" "ar_QA.UTF-8" "ar_SA.UTF-8" "ar_SD.UTF-8"
        "ar_SY.UTF-8" "ar_TN.UTF-8" "ar_YE.UTF-8" "be_BY.UTF-8" "bg_BG.UTF-8"
        "br_FR.UTF-8" "bs_BA.UTF-8" "ca_ES.UTF-8" "cs_CZ.UTF-8" "cy_GB.UTF-8"
        "da_DK.UTF-8" "de_AT.UTF-8" "de_BE.UTF-8" "de_CH.UTF-8" "de_DE.UTF-8"
        "de_LU.UTF-8" "el_GR.UTF-8" "en_AU.UTF-8" "en_CA.UTF-8" "en_GB.UTF-8"
        "en_HK.UTF-8" "en_IE.UTF-8" "en_IN.UTF-8" "en_NZ.UTF-8" "en_PH.UTF-8"
        "en_SG.UTF-8" "en_US.UTF-8" "en_ZA.UTF-8" "es_AR.UTF-8" "es_BO.UTF-8"
        "es_CL.UTF-8" "es_CO.UTF-8" "es_CR.UTF-8" "es_DO.UTF-8" "es_EC.UTF-8"
        "es_ES.UTF-8" "es_GT.UTF-8" "es_HN.UTF-8" "es_MX.UTF-8" "es_NI.UTF-8"
        "es_PA.UTF-8" "es_PE.UTF-8" "es_PR.UTF-8" "es_PY.UTF-8" "es_SV.UTF-8"
        "es_US.UTF-8" "es_UY.UTF-8" "es_VE.UTF-8" "et_EE.UTF-8" "eu_ES.UTF-8"
        "fi_FI.UTF-8" "fo_FO.UTF-8" "fr_BE.UTF-8" "fr_CA.UTF-8" "fr_CH.UTF-8"
        "fr_FR.UTF-8" "fr_LU.UTF-8" "ga_IE.UTF-8" "gd_GB.UTF-8" "gl_ES.UTF-8"
        "gv_GB.UTF-8" "he_IL.UTF-8" "hi_IN.UTF-8" "hr_HR.UTF-8" "hsb_DE.UTF-8"
        "hu_HU.UTF-8" "hy_AM.UTF-8" "id_ID.UTF-8" "is_IS.UTF-8" "it_CH.UTF-8"
        "it_IT.UTF-8" "ja_JP.UTF-8" "ka_GE.UTF-8" "kk_KZ.UTF-8" "kl_GL.UTF-8"
        "ko_KR.UTF-8" "ku_TR.UTF-8" "kw_GB.UTF-8" "lt_LT.UTF-8" "lv_LV.UTF-8"
        "mg_MG.UTF-8" "mi_NZ.UTF-8" "mk_MK.UTF-8" "ml_IN.UTF-8" "mr_IN.UTF-8"
        "ms_MY.UTF-8" "mt_MT.UTF-8" "nb_NO.UTF-8" "nl_BE.UTF-8" "nl_NL.UTF-8"
        "nn_NO.UTF-8" "oc_FR.UTF-8" "om_ET.UTF-8" "pl_PL.UTF-8" "pt_BR.UTF-8"
        "pt_PT.UTF-8" "ro_RO.UTF-8" "ru_RU.UTF-8" "ru_UA.UTF-8" "sk_SK.UTF-8"
        "sl_SI.UTF-8" "so_DJ.UTF-8" "so_ET.UTF-8" "so_KE.UTF-8" "so_SO.UTF-8"
        "sq_AL.UTF-8" "sq_MK.UTF-8" "st_ZA.UTF-8" "sv_FI.UTF-8" "sv_SE.UTF-8"
        "ta_IN.UTF-8" "te_IN.UTF-8" "tg_TJ.UTF-8" "th_TH.UTF-8" "ti_ER.UTF-8"
        "ti_ET.UTF-8" "tr_TR.UTF-8" "tt_RU.UTF-8" "uk_UA.UTF-8" "ur_IN.UTF-8"
        "ur_PK.UTF-8" "uz_UZ.UTF-8" "vi_VN.UTF-8" "wa_BE.UTF-8" "xh_ZA.UTF-8"
        "yi_US.UTF-8" "zh_CN.UTF-8" "zh_HK.UTF-8" "zh_SG.UTF-8" "zh_TW.UTF-8"
        "zu_ZA.UTF-8"
    )

    INSTALL_LOCALE=$(printf '%s\n' "${locales[@]}" | tui_search "Select locale (search to filter, e.g., en_US, ur_PK):") || {
        INSTALL_LOCALE="en_US.UTF-8"
    }
    log_ok "Locale: $INSTALL_LOCALE"
}

# ============================================================================
# Step 4: Keyboard Layout
# ============================================================================
step_keyboard() {
    set_status "Keyboard Layout"

    # Common layouts first
    local common=(
        "us" "uk" "de" "fr" "es" "pt-latin1" "it" "br-abnt2"
        "ru" "jp106" "kr" "pl" "se" "nl" "dvorak" "colemak"
        "[Show all layouts...]"
    )

    local keymap
    keymap=$(tui_menu "Select keyboard layout:" "${common[@]}") || keymap="us"

    if [[ "$keymap" == "[Show all layouts...]" ]]; then
        # Full list from localectl
        keymap=$(localectl list-keymaps 2>/dev/null | tui_search "All keyboard layouts") || keymap="us"
    fi

    INSTALL_KEYMAP="$keymap"
    loadkeys "$INSTALL_KEYMAP" 2>/dev/null || true
    log_ok "Keyboard: $INSTALL_KEYMAP"
}

# ============================================================================
# Step 5: Hostname
# ============================================================================
step_hostname() {
    set_status "Hostname"

    while true; do
        INSTALL_HOSTNAME=$(tui_input "Enter hostname for this machine" "hyprflux")

        # Use default if empty
        [[ -z "$INSTALL_HOSTNAME" ]] && INSTALL_HOSTNAME="hyprflux"

        if validate_hostname "$INSTALL_HOSTNAME"; then
            break
        fi

        tui_error "Invalid hostname.

Use only letters, numbers, and hyphens.
Must start with a letter. Max 63 characters."
    done

    log_ok "Hostname: $INSTALL_HOSTNAME"
}

# ============================================================================
# Step 6: User Account
# ============================================================================
step_user() {
    set_status "User Account"

    # Username
    while true; do
        INSTALL_USERNAME=$(tui_input "Enter username" "")

        if [[ -z "$INSTALL_USERNAME" ]]; then
            tui_error "Username cannot be empty."
            continue
        fi

        if validate_username "$INSTALL_USERNAME"; then
            break
        fi

        tui_error "Invalid username.

Use lowercase letters, numbers, underscores, hyphens.
Must start with a letter. Max 32 characters."
    done

    # Password
    while true; do
        local pass1 pass2
        pass1=$(tui_password "Enter password for '$INSTALL_USERNAME'")
        pass2=$(tui_password "Confirm password")

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

    log_ok "User: $INSTALL_USERNAME"
}

# ============================================================================
# Step 7: Disk Setup
# ============================================================================
step_disk_auto() {
    set_status "Disk Setup (Automatic)"

    # List available disks
    local disk_list=()
    while IFS= read -r line; do
        local dev size model
        dev=$(echo "$line" | awk '{print $1}')
        size=$(echo "$line" | awk '{print $2}')
        model=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
        [[ -z "$dev" ]] && continue
        disk_list+=("$dev ($size) ${model:-Unknown}")
    done < <(lsblk -d -p -n -o NAME,SIZE,MODEL 2>/dev/null | grep -v -E 'loop|sr|rom|boot')

    if [[ ${#disk_list[@]} -eq 0 ]]; then
        die "No disks found!"
    fi

    echo ""
    echo -e "  ${RED}WARNING: The selected disk will be completely erased!${RESET}"
    
    local selection
    selection=$(tui_menu "Select disk to install to:" "${disk_list[@]}") || return 1

    # Extract device path from selection
    INSTALL_DISK=$(echo "$selection" | awk '{print $1}')

    # Double confirmation
    echo ""
    echo -e "  ${RED}All data on ${INSTALL_DISK} will be destroyed!${RESET}"
    local confirm
    confirm=$(tui_input "Type 'yes' to confirm" "")
    if [[ "$confirm" != "yes" ]]; then
        log_warn "Disk setup cancelled."
        return 1
    fi

    # Swap question
    USE_SWAP=false
    SWAP_SIZE=0
    echo ""
    echo "  Swap is recommended for systems with less than 16GB RAM."
    if tui_yesno "Create a swap partition?"; then
        USE_SWAP=true
        SWAP_SIZE=$(tui_input "Swap size in GB" "4")
        [[ -z "$SWAP_SIZE" ]] && SWAP_SIZE="4"
    fi

    log_step "Boot mode: ${INSTALL_BOOT_MODE^^}"

    # Partition the disk
    log_step "Partitioning $INSTALL_DISK..."

    local part_prefix
    part_prefix=$(get_part_prefix "$INSTALL_DISK")

    # Wipe existing partitions
    sgdisk -Z "$INSTALL_DISK" 2>/dev/null || true
    wipefs -a "$INSTALL_DISK" 2>/dev/null || true

    if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
        # GPT + EFI partition
        sgdisk -o "$INSTALL_DISK"
        sgdisk -n 1:0:+1024M -t 1:ef00 -c 1:"EFI" "$INSTALL_DISK"

        local next_part=2
        if [[ "$USE_SWAP" == true ]]; then
            sgdisk -n 2:0:+${SWAP_SIZE}G -t 2:8200 -c 2:"Swap" "$INSTALL_DISK"
            next_part=3
        fi
        sgdisk -n ${next_part}:0:0 -t ${next_part}:8300 -c ${next_part}:"Root" "$INSTALL_DISK"

        EFI_PART="${part_prefix}1"
        if [[ "$USE_SWAP" == true ]]; then
            SWAP_PART="${part_prefix}2"
            ROOT_PART="${part_prefix}3"
        else
            ROOT_PART="${part_prefix}2"
        fi

    else
        # BIOS: GPT with BIOS boot partition
        sgdisk -o "$INSTALL_DISK"
        sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS Boot" "$INSTALL_DISK"

        local next_part=2
        if [[ "$USE_SWAP" == true ]]; then
            sgdisk -n 2:0:+${SWAP_SIZE}G -t 2:8200 -c 2:"Swap" "$INSTALL_DISK"
            next_part=3
        fi
        sgdisk -n ${next_part}:0:0 -t ${next_part}:8300 -c ${next_part}:"Root" "$INSTALL_DISK"

        BIOS_PART="${part_prefix}1"
        if [[ "$USE_SWAP" == true ]]; then
            SWAP_PART="${part_prefix}2"
            ROOT_PART="${part_prefix}3"
        else
            ROOT_PART="${part_prefix}2"
        fi
    fi

    # Let kernel re-read partition table
    partprobe "$INSTALL_DISK" 2>/dev/null || true
    sleep 2

    # Format partitions
    log_step "Formatting partitions..."

    if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
        mkfs.vfat -F 32 "$EFI_PART"
        log_ok "EFI partition formatted: $EFI_PART"
    fi

    if [[ "$USE_SWAP" == true ]]; then
        mkswap "$SWAP_PART"
        log_ok "Swap formatted: $SWAP_PART"
    fi

    mkfs.ext4 -F "$ROOT_PART"
    log_ok "Root partition formatted: $ROOT_PART"

    # Mount partitions
    log_step "Mounting partitions..."
    mkdir -p "$MOUNT_POINT"
    mount "$ROOT_PART" "$MOUNT_POINT"

    if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
        mkdir -p "${MOUNT_POINT}/boot"
        mount "$EFI_PART" "${MOUNT_POINT}/boot"
    fi

    if [[ "$USE_SWAP" == true ]]; then
        swapon "$SWAP_PART"
    fi

    log_ok "Partitions mounted at $MOUNT_POINT"
}

step_disk_manual() {
    set_status "Disk Setup (Manual)"

    echo ""
    if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
        echo -e "  ${WHITE}UEFI Mode Detected${RESET}"
        echo ""
        echo "  Please create and mount these partitions:"
        echo ""
        echo "    - EFI:  >= 512MB, type 'EFI System'"
        echo "            Format: mkfs.vfat -F 32 /dev/XXX"
        echo "    - Swap: (optional), type 'Linux swap'"
        echo "            Format: mkswap /dev/XXX && swapon /dev/XXX"
        echo "    - Root: remaining space, type 'Linux filesystem'"
        echo "            Format: mkfs.ext4 /dev/XXX"
        echo ""
        echo "  Mount points:"
        echo "    - Root -> $MOUNT_POINT"
        echo "    - EFI  -> $MOUNT_POINT/boot"
    else
        echo -e "  ${WHITE}BIOS/Legacy Mode Detected${RESET}"
        echo ""
        echo "  Please create and mount these partitions:"
        echo ""
        echo "    - BIOS boot: 1MB, type 'BIOS boot' (GPT only)"
        echo "    - Swap: (optional), type 'Linux swap'"
        echo "            Format: mkswap /dev/XXX && swapon /dev/XXX"
        echo "    - Root: remaining space, type 'Linux filesystem'"
        echo "            Format: mkfs.ext4 /dev/XXX"
        echo ""
        echo "  Mount point:"
        echo "    - Root -> $MOUNT_POINT"
    fi
    echo ""
    echo "  Commands: lsblk, cfdisk, fdisk, parted"
    echo ""
    echo -ne "  ${DIM}Press Enter to drop to shell...${RESET}"
    read -r < /dev/tty

    # Create mount point
    mkdir -p "$MOUNT_POINT"

    # Drop to shell
    log_step "Dropping to shell for manual partitioning..."
    log_info "Type 'exit' when done."
    bash || true

    show_banner

    # Verify mounts
    if ! mountpoint -q "$MOUNT_POINT"; then
        die "$MOUNT_POINT is not mounted! Cannot continue."
    fi

    if [[ "$INSTALL_BOOT_MODE" == "uefi" ]]; then
        if ! mountpoint -q "${MOUNT_POINT}/boot"; then
            die "${MOUNT_POINT}/boot is not mounted! EFI partition required for UEFI."
        fi
    fi

    # Try to detect which disk was used
    INSTALL_DISK=$(findmnt -n -o SOURCE "$MOUNT_POINT" | sed 's/[0-9]*$//' | sed 's/p$//')
    ROOT_PART=$(findmnt -n -o SOURCE "$MOUNT_POINT")

    log_ok "Partitions verified."
}

step_disk() {
    set_status "Disk Setup"

    local mode
    mode=$(tui_menu "Disk Partitioning:" \
        "Automatic (wipe entire disk)" \
        "Manual (partition yourself)") || mode="Automatic (wipe entire disk)"

    case "$mode" in
        "Automatic"*)
            step_disk_auto || step_disk  # Retry on cancel
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
    set_status "Installing Base System..."

    # Optimize mirrors - get fastest mirrors for better download speeds
    log_step "Finding fastest mirrors with reflector..."
    reflector --latest 10 --protocol https --sort rate --download-timeout 5 \
        --save /etc/pacman.d/mirrorlist 2>&1 | while IFS= read -r line; do
        log_cmd "$line"
    done || log_warn "Reflector failed, using existing mirrors"

    # Copy mirrorlist to target
    mkdir -p "${MOUNT_POINT}/etc/pacman.d"
    cp /etc/pacman.d/mirrorlist "${MOUNT_POINT}/etc/pacman.d/mirrorlist"

    # Create vconsole.conf before pacstrap (needed by mkinitcpio sd-vconsole hook)
    echo "KEYMAP=${INSTALL_KEYMAP}" > "${MOUNT_POINT}/etc/vconsole.conf"

    # Base packages to install
    local base_pkgs=(
        base linux linux-firmware
        grub efibootmgr
        networkmanager
        sudo vim nano git zsh
        base-devel
        amd-ucode intel-ucode
        libnewt            # whiptail for dialogs
        pciutils           # lspci for GPU detection
        curl wget          # for downloading scripts
    )

    # Retry logic for pacstrap
    local max_retries=3
    local retry_count=0
    local pacstrap_success=false

    while [[ $retry_count -lt $max_retries ]]; do
        retry_count=$((retry_count + 1))
        
        if [[ $retry_count -gt 1 ]]; then
            log_warn "Retrying pacstrap (attempt ${retry_count}/${max_retries})..."
            # Refresh mirrors on retry
            log_step "Refreshing mirror list..."
            reflector --latest 5 --protocol https --sort rate --download-timeout 5 \
                --save /etc/pacman.d/mirrorlist 2>&1 | while IFS= read -r line; do
                log_cmd "$line"
            done || true
            cp /etc/pacman.d/mirrorlist "${MOUNT_POINT}/etc/pacman.d/mirrorlist"
            sleep 2
        fi

        log_step "Running pacstrap (attempt ${retry_count}/${max_retries})..."
        log_info "This may take 5-15 minutes depending on your internet speed..."

        # Temporarily disable errexit for pacstrap pipeline
        set +e
        pacstrap -K "$MOUNT_POINT" "${base_pkgs[@]}" 2>&1 | while IFS= read -r line; do
            log_cmd "$line"
        done
        local pacstrap_status=${PIPESTATUS[0]}
        set -e

        if [[ $pacstrap_status -eq 0 ]]; then
            pacstrap_success=true
            break
        fi

        log_error "pacstrap failed (attempt ${retry_count}/${max_retries})"
        
        if [[ $retry_count -lt $max_retries ]]; then
            log_info "Waiting 5 seconds before retry..."
            sleep 5
        fi
    done

    if [[ "$pacstrap_success" != true ]]; then
        echo ""
        log_error "pacstrap failed after ${max_retries} attempts!"
        echo ""
        echo -e "  ${YELLOW}Possible solutions:${RESET}"
        echo "    1. Check your internet connection"
        echo "    2. Try again later (mirrors may be overloaded)"
        echo "    3. Run manually: pacstrap -K $MOUNT_POINT base linux linux-firmware"
        echo ""
        die "pacstrap failed! Check your internet connection and try again."
    fi

    # Generate fstab
    log_step "Generating fstab..."
    genfstab -U "$MOUNT_POINT" >> "${MOUNT_POINT}/etc/fstab"
    log_ok "fstab generated."

    log_ok "Base system installed."
}

# ============================================================================
# Step 9: Configure Base System (arch-chroot)
# ============================================================================
step_configure_system() {
    set_status "Configuring System..."

    log_step "Configuring timezone..."
    arch-chroot "$MOUNT_POINT" ln -sf "/usr/share/zoneinfo/${INSTALL_TIMEZONE}" /etc/localtime
    arch-chroot "$MOUNT_POINT" hwclock --systohc
    log_ok "Timezone set to ${INSTALL_TIMEZONE}"

    log_step "Configuring locale..."
    arch-chroot "$MOUNT_POINT" sed -i "s/^#${INSTALL_LOCALE}/${INSTALL_LOCALE}/" /etc/locale.gen
    arch-chroot "$MOUNT_POINT" locale-gen
    echo "LANG=${INSTALL_LOCALE}" > "${MOUNT_POINT}/etc/locale.conf"
    log_ok "Locale set to ${INSTALL_LOCALE}"

    log_step "Configuring keyboard..."
    echo "KEYMAP=${INSTALL_KEYMAP}" > "${MOUNT_POINT}/etc/vconsole.conf"
    log_ok "Keyboard set to ${INSTALL_KEYMAP}"

    log_step "Configuring hostname..."
    echo "${INSTALL_HOSTNAME}" > "${MOUNT_POINT}/etc/hostname"
    cat > "${MOUNT_POINT}/etc/hosts" << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${INSTALL_HOSTNAME}.localdomain ${INSTALL_HOSTNAME}
EOF
    log_ok "Hostname set to ${INSTALL_HOSTNAME}"

    log_step "Setting root password..."
    echo "root:${INSTALL_PASSWORD}" | arch-chroot "$MOUNT_POINT" chpasswd
    log_ok "Root password set"

    log_step "Creating user '${INSTALL_USERNAME}'..."
    # Use /bin/bash here -- zsh is not installed yet at this stage.
    # The chroot wrapper will run usermod to switch to zsh after zsh is installed.
    arch-chroot "$MOUNT_POINT" useradd -m -G wheel -s /bin/bash "${INSTALL_USERNAME}"
    echo "${INSTALL_USERNAME}:${INSTALL_PASSWORD}" | arch-chroot "$MOUNT_POINT" chpasswd
    log_ok "User ${INSTALL_USERNAME} created"

    log_step "Configuring sudo..."
    arch-chroot "$MOUNT_POINT" sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    log_ok "Sudo configured"

    log_step "Configuring pacman..."
    arch-chroot "$MOUNT_POINT" sed -i 's/^#Color/Color/' /etc/pacman.conf
    arch-chroot "$MOUNT_POINT" sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
    arch-chroot "$MOUNT_POINT" sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    # Enable multilib
    arch-chroot "$MOUNT_POINT" sed -i '/\[multilib\]/,/Include/{s/^#//}' /etc/pacman.conf
    log_ok "Pacman configured"

    log_step "Installing GRUB bootloader..."
    if [[ "${INSTALL_BOOT_MODE}" == "uefi" ]]; then
        arch-chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    else
        arch-chroot "$MOUNT_POINT" grub-install --target=i386-pc "${INSTALL_DISK}"
    fi
    arch-chroot "$MOUNT_POINT" grub-mkconfig -o /boot/grub/grub.cfg
    log_ok "GRUB installed"

    log_step "Enabling essential services..."
    arch-chroot "$MOUNT_POINT" systemctl enable NetworkManager
    log_ok "Services enabled"

    log_ok "System configured."
}

# ============================================================================
# Step 10: Prepare HyprFlux installation for first-boot
# ============================================================================
# Strategy: Clone the repos during ISO install, then run the actual
# HyprFlux install.sh on first login (after reboot). This avoids chroot
# limitations and allows the installer to run with full system access.
# ============================================================================
step_install_hyprflux() {
    set_status "Preparing HyprFlux Installation..."

    local user_home="${MOUNT_POINT}/home/${INSTALL_USERNAME}"

    # ====== DNS for chroot git operations ======
    log_step "Configuring DNS for chroot..."
    cp --remove-destination /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf"

    # ====== Clone Arch-Hyprland repo ======
    log_step "Cloning Arch-Hyprland repository..."
    local arch_hypr_dir="${user_home}/Arch-Hyprland"
    if [[ -d "${arch_hypr_dir}" ]]; then
        rm -rf "${arch_hypr_dir}"
    fi
    
    set +e
    git clone --depth=1 https://github.com/ahmad9059/Arch-Hyprland.git \
        "${arch_hypr_dir}" \
        2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    local git_status=${PIPESTATUS[0]}
    set -e
    
    if [[ $git_status -ne 0 ]]; then
        die "Failed to clone Arch-Hyprland repository. Check internet connection."
    fi
    log_ok "Arch-Hyprland repository cloned."

    # ====== Clone HyprFlux repo ======
    log_step "Cloning HyprFlux repository..."
    if [[ -d "${user_home}/HyprFlux" ]]; then
        rm -rf "${user_home}/HyprFlux"
    fi
    
    set +e
    git clone --depth=1 https://github.com/ahmad9059/HyprFlux.git \
        "${user_home}/HyprFlux" \
        2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    git_status=${PIPESTATUS[0]}
    set -e
    
    if [[ $git_status -ne 0 ]]; then
        die "Failed to clone HyprFlux repository. Check internet connection."
    fi
    log_ok "HyprFlux repository cloned."

    # ====== Fix ownership ======
    log_step "Setting up permissions..."
    arch-chroot "$MOUNT_POINT" chown -R \
        "${INSTALL_USERNAME}:${INSTALL_USERNAME}" \
        "/home/${INSTALL_USERNAME}" 2>/dev/null || true
    log_ok "Permissions set."

    # ====== Create first-boot installer script ======
    log_step "Setting up first-boot installer..."
    cat > "${user_home}/.hyprflux-firstboot.sh" << 'FIRSTBOOT_EOF'
#!/bin/bash
# HyprFlux First-Boot Installer
# Runs automatically on first login to complete installation

MARKER="$HOME/.hyprflux-install-done"

# Only run once
[[ -f "$MARKER" ]] && return 0

# Only run on tty1
if [[ "$(tty)" != "/dev/tty1" ]]; then
    return 0
fi

echo ""
echo "=============================================="
echo "  Welcome to HyprFlux!"
echo "=============================================="
echo ""
echo "  Starting HyprFlux installation..."
echo "  This will take 20-60 minutes."
echo "  Please do NOT interrupt the process."
echo ""
sleep 3

# Run the HyprFlux installer
cd "$HOME"
if [[ -f "$HOME/HyprFlux/install.sh" ]]; then
    bash "$HOME/HyprFlux/install.sh"
    INSTALL_EXIT=$?
    
    if [[ $INSTALL_EXIT -eq 0 ]]; then
        touch "$MARKER"
        echo ""
        echo "=============================================="
        echo "  Installation Complete!"
        echo "=============================================="
        echo ""
        echo "  HyprFlux has been installed successfully."
        echo ""
        echo "  To start Hyprland desktop, type:"
        echo "    Hyprland"
        echo ""
        echo "  Or reboot and login again."
        echo ""
    else
        echo ""
        echo "=============================================="
        echo "  Installation Issue Detected"
        echo "=============================================="
        echo ""
        echo "  The installer exited with errors."
        echo "  You can try running it again:"
        echo "    bash ~/HyprFlux/install.sh"
        echo ""
    fi
else
    echo ""
    echo "  ERROR: HyprFlux installer not found!"
    echo "  Expected: $HOME/HyprFlux/install.sh"
    echo ""
    echo "  To fix, run:"
    echo "    git clone https://github.com/ahmad9059/HyprFlux.git"
    echo "    bash ~/HyprFlux/install.sh"
    echo ""
fi

# Self-remove from .bash_profile
sed -i '/hyprflux-firstboot/d' "$HOME/.bash_profile" 2>/dev/null || true
FIRSTBOOT_EOF
    chmod +x "${user_home}/.hyprflux-firstboot.sh"

    # Hook into .bash_profile
    cat > "${user_home}/.bash_profile" << 'PROFILE_EOF'
# Load .bashrc if it exists
[[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"

# Run HyprFlux installer on first boot (only on tty1)
if [[ -f "$HOME/.hyprflux-firstboot.sh" && ! -f "$HOME/.hyprflux-install-done" ]]; then
    if [[ "$(tty)" == "/dev/tty1" ]]; then
        source "$HOME/.hyprflux-firstboot.sh"
    fi
fi
PROFILE_EOF

    # Fix ownership
    arch-chroot "$MOUNT_POINT" chown \
        "${INSTALL_USERNAME}:${INSTALL_USERNAME}" \
        "/home/${INSTALL_USERNAME}/.bash_profile" \
        "/home/${INSTALL_USERNAME}/.hyprflux-firstboot.sh" 2>/dev/null || true

    log_ok "First-boot installer configured."
    log_ok "HyprFlux will install automatically on first login."
}

# ============================================================================
# Step 11: Cleanup & Reboot
# ============================================================================
step_cleanup_reboot() {
    set_status "Installation Complete!"

    echo ""
    log_ok "Base Arch Linux installed. HyprFlux ready for first-boot install."
    echo ""

    # Sync filesystem
    sync

    # Show completion message
    echo ""
    echo -e "  ${GREEN}╔════════════════════════════════════════════════════════╗${RESET}"
    echo -e "  ${GREEN}║     Base Installation Complete!                        ║${RESET}"
    echo -e "  ${GREEN}╚════════════════════════════════════════════════════════╝${RESET}"
    echo ""
    echo "  Base Arch Linux has been installed."
    echo ""
    echo "  Please:"
    echo "    1. Remove the USB drive / ISO"
    echo "    2. Press Enter to reboot"
    echo ""
    echo -e "  ${YELLOW}After reboot (Phase 2 - HyprFlux Installation):${RESET}"
    echo "    - Login with username: ${INSTALL_USERNAME}"
    echo "    - HyprFlux installer will start automatically on tty1"
    echo "    - This takes 20-60 minutes (downloads packages)"
    echo "    - Do NOT interrupt -- let it complete"
    echo "    - After completion, type 'Hyprland' to start desktop"
    echo ""
    echo -ne "  ${DIM}Press Enter to reboot...${RESET}"
    read -r < /dev/tty

    # Unmount
    log_step "Unmounting partitions..."
    umount -R "$MOUNT_POINT" 2>/dev/null || true
    swapoff -a 2>/dev/null || true
    log_ok "Partitions unmounted."

    # Reboot
    set_status "Rebooting..."
    log_step "Rebooting in 5 seconds..."
    log_info "Remove installation media now!"
    sleep 5
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

# Run main
main
