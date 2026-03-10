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

    # Manual selection: Region first
    local regions=()
    for dir in /usr/share/zoneinfo/*/; do
        local name
        name=$(basename "$dir")
        # Skip non-region directories
        [[ "$name" == "posix" || "$name" == "right" ]] && continue
        regions+=("$name")
    done

    local region
    region=$(tui_menu "Select timezone region:" "${regions[@]}") || {
        log_warn "Using default timezone: UTC"
        INSTALL_TIMEZONE="UTC"
        return 0
    }

    # Then city within region
    local cities=()
    for zone in /usr/share/zoneinfo/"$region"/*; do
        [[ -f "$zone" ]] && cities+=("$(basename "$zone")")
    done

    local city
    city=$(tui_menu "Select timezone city:" "${cities[@]}") || {
        log_warn "Using region default"
        INSTALL_TIMEZONE="$region"
        return 0
    }

    INSTALL_TIMEZONE="${region}/${city}"
    log_ok "Timezone: $INSTALL_TIMEZONE"
}

# ============================================================================
# Step 3: Locale
# ============================================================================
step_locale() {
    set_status "Locale Configuration"

    local locales=(
        "en_US.UTF-8"
        "en_GB.UTF-8"
        "de_DE.UTF-8"
        "fr_FR.UTF-8"
        "es_ES.UTF-8"
        "pt_BR.UTF-8"
        "it_IT.UTF-8"
        "ja_JP.UTF-8"
        "ko_KR.UTF-8"
        "zh_CN.UTF-8"
        "zh_TW.UTF-8"
        "ru_RU.UTF-8"
        "ar_EG.UTF-8"
        "hi_IN.UTF-8"
        "pl_PL.UTF-8"
        "nl_NL.UTF-8"
        "sv_SE.UTF-8"
        "tr_TR.UTF-8"
    )

    INSTALL_LOCALE=$(tui_menu "Select locale:" "${locales[@]}") || {
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

    # Optimize mirrors
    log_step "Updating mirror list with reflector..."
    reflector --latest 20 --protocol https --sort rate \
        --save /etc/pacman.d/mirrorlist 2>&1 | while IFS= read -r line; do
        log_cmd "$line"
    done || log_warn "Reflector failed, using existing mirrors"

    # Copy mirrorlist to target
    mkdir -p "${MOUNT_POINT}/etc/pacman.d"
    cp /etc/pacman.d/mirrorlist "${MOUNT_POINT}/etc/pacman.d/mirrorlist"

    # Base packages to install
    local base_pkgs=(
        base linux linux-firmware
        grub efibootmgr
        networkmanager
        sudo vim nano git zsh
        base-devel
        amd-ucode intel-ucode
    )

    log_step "Running pacstrap (this may take 5-15 minutes)..."

    # Temporarily disable errexit for pacstrap pipeline
    set +e
    pacstrap -K "$MOUNT_POINT" "${base_pkgs[@]}" 2>&1 | while IFS= read -r line; do
        log_cmd "$line"
    done
    local pacstrap_status=${PIPESTATUS[0]}
    set -e

    if [[ $pacstrap_status -ne 0 ]]; then
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

    # Write configuration script to run inside chroot
    cat > "${MOUNT_POINT}/tmp/hyprflux-configure.sh" << CHROOT_EOF
#!/bin/bash
set -e

echo "==> Setting timezone..."
ln -sf /usr/share/zoneinfo/${INSTALL_TIMEZONE} /etc/localtime
hwclock --systohc

echo "==> Generating locales..."
sed -i "s/^#${INSTALL_LOCALE}/${INSTALL_LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${INSTALL_LOCALE}" > /etc/locale.conf

echo "==> Setting keyboard layout..."
echo "KEYMAP=${INSTALL_KEYMAP}" > /etc/vconsole.conf

echo "==> Setting hostname..."
echo "${INSTALL_HOSTNAME}" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${INSTALL_HOSTNAME}.localdomain ${INSTALL_HOSTNAME}
HOSTS_EOF

echo "==> Setting root password..."
echo "root:${INSTALL_PASSWORD}" | chpasswd

echo "==> Creating user '${INSTALL_USERNAME}'..."
useradd -m -G wheel -s /bin/bash "${INSTALL_USERNAME}"
echo "${INSTALL_USERNAME}:${INSTALL_PASSWORD}" | chpasswd

echo "==> Configuring sudo..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "==> Configuring pacman..."
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
# Enable multilib
sed -i '/\[multilib\]/,/Include/{s/^#//}' /etc/pacman.conf

echo "==> Installing GRUB bootloader..."
if [[ "${INSTALL_BOOT_MODE}" == "uefi" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    grub-install --target=i386-pc "${INSTALL_DISK}"
fi
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Enabling essential services..."
systemctl enable NetworkManager

echo "==> Base system configuration complete."
CHROOT_EOF

    chmod +x "${MOUNT_POINT}/tmp/hyprflux-configure.sh"

    log_step "Running system configuration in chroot..."

    # Run chroot script
    set +e
    arch-chroot "$MOUNT_POINT" /bin/bash /tmp/hyprflux-configure.sh 2>&1 | \
        while IFS= read -r line; do
            log_cmd "$line"
        done
    local chroot_status=${PIPESTATUS[0]}
    set -e

    if [[ $chroot_status -ne 0 ]]; then
        die "System configuration failed in chroot!"
    fi

    # Clean up
    rm -f "${MOUNT_POINT}/tmp/hyprflux-configure.sh"

    log_ok "System configured."
}

# ============================================================================
# Step 10: Install HyprFlux (Chroot Wrapper)
# ============================================================================
step_install_hyprflux() {
    set_status "Installing HyprFlux Desktop (20-60 minutes)..."

    # ====== Prepare chroot environment ======

    # DNS resolution in chroot
    log_step "Configuring DNS for chroot..."
    cp /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf"

    # ====== Clone repos as target user ======
    log_step "Cloning HyprFlux repository..."
    set +e
    arch-chroot "$MOUNT_POINT" su - "${INSTALL_USERNAME}" -c \
        "git clone --depth=1 https://github.com/ahmad9059/HyprFlux.git ~/HyprFlux" \
        2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    set -e

    log_step "Cloning Arch-Hyprland repository..."
    set +e
    arch-chroot "$MOUNT_POINT" su - "${INSTALL_USERNAME}" -c \
        "git clone --depth=1 https://github.com/ahmad9059/Arch-Hyprland.git ~/Arch-Hyprland" \
        2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    set -e

    # ====== Copy wrapper script into chroot ======
    log_step "Preparing chroot wrapper..."
    cp "${SCRIPT_DIR}/lib/hyprflux-chroot-wrapper.sh" \
        "${MOUNT_POINT}/tmp/hyprflux-chroot-wrapper.sh"
    chmod +x "${MOUNT_POINT}/tmp/hyprflux-chroot-wrapper.sh"

    # ====== Run wrapper inside chroot ======
    log_step "Running HyprFlux installation pipeline..."
    log_info "This will take 20-60 minutes depending on your internet speed."
    echo ""

    set +e
    arch-chroot "$MOUNT_POINT" /bin/bash /tmp/hyprflux-chroot-wrapper.sh \
        "${INSTALL_USERNAME}" \
        "${INSTALL_HAS_NVIDIA}" \
        2>&1 | while IFS= read -r line; do
            log_cmd "$line"
        done
    local wrapper_status=${PIPESTATUS[0]}
    set -e

    if [[ $wrapper_status -ne 0 ]]; then
        log_warn "HyprFlux installation had some errors (exit code: $wrapper_status)"
        log_warn "Some packages may have failed. The system should still be usable."
    else
        log_ok "HyprFlux installation completed successfully."
    fi

    # Clean up
    rm -f "${MOUNT_POINT}/tmp/hyprflux-chroot-wrapper.sh"
}

# ============================================================================
# Step 11: Cleanup & Reboot
# ============================================================================
step_cleanup_reboot() {
    set_status "Installation Complete!"

    echo ""
    log_ok "HyprFlux has been installed successfully!"
    echo ""

    # Sync filesystem
    sync

    # Show completion message
    echo ""
    echo -e "  ${GREEN}Installation Complete!${RESET}"
    echo ""
    echo "  HyprFlux has been installed successfully."
    echo ""
    echo "  Please:"
    echo "    1. Remove the USB drive / ISO"
    echo "    2. Press Enter to reboot"
    echo ""
    echo "  After reboot:"
    echo "    - SDDM login screen will appear"
    echo "    - Login with: ${INSTALL_USERNAME}"
    echo "    - First login takes ~10 seconds (applying theme)"
    echo ""
    echo "  Enjoy HyprFlux!"
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
