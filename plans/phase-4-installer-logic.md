# Phase 4: Installer Logic (Network, Config, Partitioning, Base System)

## Goal

Implement all the interactive installer steps: network setup, timezone/locale/keyboard selection, hostname/user creation, disk partitioning (automatic + manual), and base system installation via pacstrap. This is the largest phase -- the "meat" of the installer.

After this phase, the installer can take a bare machine from boot to a working base Arch Linux system (without HyprFlux yet -- that's Phase 5).

---

## Installer Step Overview

| Step | Name | Interactive? | Description |
|------|------|-------------|-------------|
| 0 | Network | Yes (if no internet) | Ensure internet connectivity |
| 1 | Welcome | Yes | Confirm installation start |
| 2 | Timezone | Yes | Auto-detect + manual override |
| 3 | Locale | Yes | Select locale (default: en_US.UTF-8) |
| 4 | Keyboard | Yes | Select keyboard layout |
| 5 | Hostname | Yes | Enter hostname |
| 6 | User Account | Yes | Create username + password |
| 7 | Disk Setup | Yes | Auto or manual partitioning |
| 8 | Base Install | No (automated) | pacstrap + fstab + basic config |
| 9 | System Config | No (automated) | chroot: locale, timezone, GRUB, users |

---

## Step 0: Network Setup

The installer requires internet (repos are cloned online). This must be the first step.

### Flow

```
check_internet()
  │
  ├── SUCCESS → log_ok "Internet connected" → continue
  │
  └── FAIL → show network menu:
       │
       ├── [1] Ethernet (auto DHCP)
       │    → systemctl start NetworkManager
       │    → Detect wired interfaces
       │    → nmcli device connect <iface>
       │    → Wait + re-check
       │
       ├── [2] WiFi
       │    → systemctl start NetworkManager
       │    → nmcli device wifi rescan
       │    → Parse: nmcli -t -f SSID,SIGNAL,SECURITY device wifi list
       │    → dialog --menu with SSIDs + signal strength
       │    → dialog --passwordbox for password
       │    → nmcli device wifi connect "$SSID" password "$PASS"
       │    → Wait + re-check
       │
       ├── [3] Manual (drop to shell)
       │    → Show hint: "Use nmcli, iwctl, or ip commands"
       │    → Drop to shell, resume on 'exit'
       │    → Re-check internet
       │
       └── [4] Skip (offline, will fail later)
            → Warn and continue
```

### Implementation Details

```bash
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
            "Skip (not recommended)")
        
        case "$choice" in
            "Ethernet"*)
                setup_ethernet
                ;;
            "WiFi"*)
                setup_wifi
                ;;
            "Manual"*)
                log_step "Dropping to shell. Type 'exit' when connected."
                bash
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
        
        log_error "Still no internet. Try again?"
    done
}

setup_ethernet() {
    log_step "Connecting via Ethernet..."
    local ifaces
    ifaces=$(nmcli -t -f DEVICE,TYPE device | grep ethernet | cut -d: -f1)
    
    if [[ -z "$ifaces" ]]; then
        log_error "No Ethernet interfaces found."
        return 1
    fi
    
    for iface in $ifaces; do
        nmcli device connect "$iface" 2>/dev/null && break
    done
    
    sleep 5
}

setup_wifi() {
    log_step "Scanning for WiFi networks..."
    nmcli device wifi rescan 2>/dev/null
    sleep 3
    
    # Parse available networks
    local networks
    networks=$(nmcli -t -f SSID,SIGNAL,SECURITY device wifi list | \
        grep -v '^$' | sort -t: -k2 -rn | head -20)
    
    if [[ -z "$networks" ]]; then
        log_error "No WiFi networks found."
        return 1
    fi
    
    # Build dialog menu items
    local items=()
    while IFS=: read -r ssid signal security; do
        [[ -z "$ssid" ]] && continue
        items+=("$ssid" "${signal}% ${security}")
    done <<< "$networks"
    
    local ssid
    ssid=$(dialog --clear --title "Select WiFi Network" \
        --menu "" 20 60 14 "${items[@]}" 2>&1 >/dev/tty)
    
    show_banner
    setup_output_area
    
    if [[ -z "$ssid" ]]; then
        return 1
    fi
    
    local password
    password=$(dlg_password "Enter password for '$ssid'")
    
    log_step "Connecting to '$ssid'..."
    nmcli device wifi connect "$ssid" password "$password" 2>&1 || true
    sleep 5
}
```

---

## Step 1: Welcome

Simple welcome dialog with confirmation.

```bash
step_welcome() {
    set_status "Welcome"
    
    dlg_yesno "Welcome to the HyprFlux Installer!\n\n\
This will install Arch Linux with the HyprFlux Hyprland desktop.\n\n\
Requirements:\n\
  - Internet connection (repos are cloned during install)\n\
  - A disk to install to (will be formatted)\n\
  - At least 20GB free disk space\n\n\
Continue with installation?" || {
        log_warn "Installation cancelled."
        exit 0
    }
}
```

---

## Step 2: Timezone

Auto-detect timezone, allow manual override.

```bash
step_timezone() {
    set_status "Timezone Configuration"
    
    # Try auto-detect
    local detected=""
    detected=$(curl -s --max-time 5 https://ipapi.co/timezone 2>/dev/null || true)
    
    if [[ -n "$detected" ]] && [[ -f "/usr/share/zoneinfo/$detected" ]]; then
        if dlg_yesno "Detected timezone: $detected\n\nIs this correct?"; then
            INSTALL_TIMEZONE="$detected"
            log_ok "Timezone: $INSTALL_TIMEZONE"
            return 0
        fi
    fi
    
    # Manual selection: Region first
    local regions=()
    for dir in /usr/share/zoneinfo/*/; do
        local name=$(basename "$dir")
        # Skip non-region directories
        [[ "$name" == "posix" || "$name" == "right" ]] && continue
        regions+=("$name")
    done
    
    local region
    region=$(dlg_menu "Select timezone region" "${regions[@]}")
    
    # Then city within region
    local cities=()
    for zone in /usr/share/zoneinfo/"$region"/*; do
        cities+=("$(basename "$zone")")
    done
    
    local city
    city=$(dlg_menu "Select timezone city" "${cities[@]}")
    
    INSTALL_TIMEZONE="${region}/${city}"
    log_ok "Timezone: $INSTALL_TIMEZONE"
}
```

---

## Step 3: Locale

Select locale from common options.

```bash
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
    
    INSTALL_LOCALE=$(dlg_menu "Select locale" "${locales[@]}")
    log_ok "Locale: $INSTALL_LOCALE"
}
```

---

## Step 4: Keyboard Layout

Select from available keymaps.

```bash
step_keyboard() {
    set_status "Keyboard Layout"
    
    # Common layouts first, then offer full list
    local common=(
        "us" "uk" "de" "fr" "es" "pt-latin1" "it" "br-abnt2"
        "ru" "jp106" "kr" "pl" "se" "nl" "dvorak" "colemak"
    )
    
    # Add "More..." option to show full list
    common+=("MORE_LAYOUTS")
    
    local keymap
    keymap=$(dlg_menu "Select keyboard layout" "${common[@]}")
    
    if [[ "$keymap" == "MORE_LAYOUTS" ]]; then
        # Full list from localectl
        local all_keymaps
        mapfile -t all_keymaps < <(localectl list-keymaps)
        keymap=$(dlg_menu "All keyboard layouts" "${all_keymaps[@]}")
    fi
    
    INSTALL_KEYMAP="$keymap"
    loadkeys "$INSTALL_KEYMAP" 2>/dev/null || true
    log_ok "Keyboard: $INSTALL_KEYMAP"
}
```

---

## Step 5: Hostname

```bash
step_hostname() {
    set_status "Hostname"
    
    while true; do
        INSTALL_HOSTNAME=$(dlg_input "Enter hostname for this machine" "hyprflux")
        
        if validate_hostname "$INSTALL_HOSTNAME"; then
            break
        fi
        
        dialog --msgbox "Invalid hostname. Use only letters, numbers, and hyphens.\nMust start with a letter. Max 63 characters." 8 50
        show_banner && setup_output_area
    done
    
    log_ok "Hostname: $INSTALL_HOSTNAME"
}
```

**Change from original plan:** Variable renamed from `HOSTNAME` to `INSTALL_HOSTNAME` to avoid shadowing the bash builtin `$HOSTNAME`.

---

## Step 6: User Account

```bash
step_user() {
    set_status "User Account"
    
    # Username
    while true; do
        INSTALL_USERNAME=$(dlg_input "Enter username" "")
        
        if validate_username "$INSTALL_USERNAME"; then
            break
        fi
        
        dialog --msgbox "Invalid username. Use lowercase letters, numbers, hyphens.\nMust start with a letter. Max 32 characters." 8 55
        show_banner && setup_output_area
    done
    
    # Password
    while true; do
        local pass1 pass2
        pass1=$(dlg_password "Enter password for '$INSTALL_USERNAME'")
        pass2=$(dlg_password "Confirm password")
        
        if [[ "$pass1" == "$pass2" ]]; then
            if [[ -n "$pass1" ]]; then
                INSTALL_PASSWORD="$pass1"
                break
            fi
            dialog --msgbox "Password cannot be empty." 6 40
        else
            dialog --msgbox "Passwords do not match. Try again." 6 40
        fi
        show_banner && setup_output_area
    done
    
    log_ok "User: $INSTALL_USERNAME"
}
```

**Change from original plan:** Variables renamed from `USERNAME`/`PASSWORD` to `INSTALL_USERNAME`/`INSTALL_PASSWORD` for clarity and to avoid conflicts.

---

## Step 7: Disk Setup

The most complex step. Two modes: Automatic and Manual.

### Automatic Mode

```bash
step_disk_auto() {
    set_status "Disk Setup (Automatic)"
    
    # List available disks
    local disks=()
    while IFS= read -r line; do
        local dev=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $2}')
        local model=$(echo "$line" | awk '{$1=$2=""; print $0}' | xargs)
        disks+=("$dev" "${size} ${model}")
    done < <(lsblk -d -p -n -o NAME,SIZE,MODEL | grep -v -E 'loop|sr|rom|boot')
    
    if [[ ${#disks[@]} -eq 0 ]]; then
        die "No disks found!"
    fi
    
    INSTALL_DISK=$(dialog --clear --title "Select Disk" \
        --menu "Choose a disk to install to.\nWARNING: The selected disk will be completely erased!" \
        20 70 10 "${disks[@]}" 2>&1 >/dev/tty)
    show_banner && setup_output_area
    
    # Double confirmation
    local confirm
    confirm=$(dlg_input "Type 'yes' to confirm erasing ALL data on $INSTALL_DISK" "")
    if [[ "$confirm" != "yes" ]]; then
        log_warn "Disk setup cancelled."
        return 1
    fi
    
    # Swap question
    USE_SWAP=false
    SWAP_SIZE=0
    if dlg_yesno "Create a swap partition?\n(Recommended for systems with <16GB RAM)"; then
        USE_SWAP=true
        SWAP_SIZE=$(dlg_input "Swap size in GB" "4")
    fi
    
    # Detect boot mode
    BOOT_MODE=$(detect_boot_mode)
    log_step "Boot mode: ${BOOT_MODE^^}"
    
    # Partition
    log_step "Partitioning $INSTALL_DISK..."
    
    local part_prefix
    part_prefix=$(get_part_prefix "$INSTALL_DISK")
    
    # Wipe
    sgdisk -Z "$INSTALL_DISK" 2>/dev/null || true
    wipefs -a "$INSTALL_DISK" 2>/dev/null || true
    
    if [[ "$BOOT_MODE" == "uefi" ]]; then
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
    
    # Format
    log_step "Formatting partitions..."
    
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        mkfs.vfat -F 32 "$EFI_PART"
        log_ok "EFI partition formatted: $EFI_PART"
    fi
    
    if [[ "$USE_SWAP" == true ]]; then
        mkswap "$SWAP_PART"
        log_ok "Swap formatted: $SWAP_PART"
    fi
    
    mkfs.ext4 -F "$ROOT_PART"
    log_ok "Root partition formatted: $ROOT_PART"
    
    # Mount
    log_step "Mounting partitions..."
    mount "$ROOT_PART" "$MOUNT_POINT"
    
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        mkdir -p "${MOUNT_POINT}/boot"
        mount "$EFI_PART" "${MOUNT_POINT}/boot"
    fi
    
    if [[ "$USE_SWAP" == true ]]; then
        swapon "$SWAP_PART"
    fi
    
    log_ok "Partitions mounted at $MOUNT_POINT"
}
```

### Manual Mode

```bash
step_disk_manual() {
    set_status "Disk Setup (Manual)"
    
    BOOT_MODE=$(detect_boot_mode)
    
    local instructions
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        instructions="Please create and mount these partitions:

  UEFI Mode Detected:
  - EFI:  >= 512MB, type 'EFI System', format: mkfs.vfat -F 32
  - Swap: (optional), type 'Linux swap', format: mkswap + swapon
  - Root: remaining space, type 'Linux filesystem', format: mkfs.ext4

  Mount points:
  - Root -> $MOUNT_POINT
  - EFI  -> $MOUNT_POINT/boot

  Useful commands: lsblk, cfdisk /dev/sdX, fdisk /dev/sdX

  Type 'exit' when done."
    else
        instructions="Please create and mount these partitions:

  BIOS/Legacy Mode Detected:
  - BIOS boot: 1MB, type 'BIOS boot' (for GPT) -- OR use MBR
  - Swap: (optional), type 'Linux swap', format: mkswap + swapon
  - Root: remaining space, type 'Linux filesystem', format: mkfs.ext4

  Mount points:
  - Root -> $MOUNT_POINT

  Useful commands: lsblk, cfdisk /dev/sdX, fdisk /dev/sdX

  Type 'exit' when done."
    fi
    
    dialog --clear --title "Manual Partitioning" --msgbox "$instructions" 22 70
    show_banner && setup_output_area
    
    # Drop to shell
    log_step "Dropping to shell for manual partitioning..."
    log_step "Type 'exit' when you're done."
    bash
    
    # Verify mounts
    if ! mountpoint -q "$MOUNT_POINT"; then
        die "$MOUNT_POINT is not mounted! Cannot continue."
    fi
    
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        if ! mountpoint -q "${MOUNT_POINT}/boot"; then
            die "${MOUNT_POINT}/boot is not mounted! EFI partition required for UEFI."
        fi
    fi
    
    log_ok "Partitions verified."
}

# Main disk step dispatcher
step_disk() {
    set_status "Disk Setup"
    
    local mode
    mode=$(dlg_menu "Disk Partitioning" \
        "Automatic (wipe entire disk)" \
        "Manual (partition yourself)")
    
    case "$mode" in
        "Automatic"*)
            step_disk_auto
            ;;
        "Manual"*)
            step_disk_manual
            ;;
    esac
}
```

---

## Step 8: Install Base System

Non-interactive. Installs base Arch Linux to the mounted disk.

```bash
step_base_install() {
    set_status "Installing Base System..."
    
    # Optimize mirrors
    log_step "Optimizing mirror list..."
    reflector --latest 20 --protocol https --sort rate \
        --save /etc/pacman.d/mirrorlist 2>&1 | while IFS= read -r line; do
        log_cmd "$line"
    done
    
    # Copy mirrorlist to target
    mkdir -p "${MOUNT_POINT}/etc/pacman.d"
    cp /etc/pacman.d/mirrorlist "${MOUNT_POINT}/etc/pacman.d/mirrorlist"
    
    # Base packages to install
    local base_pkgs=(
        base linux linux-firmware
        grub efibootmgr
        networkmanager
        sudo vim git nano
        base-devel
        amd-ucode intel-ucode
    )
    
    log_step "Running pacstrap (this may take 5-15 minutes)..."
    pacstrap -K "$MOUNT_POINT" "${base_pkgs[@]}" 2>&1 | while IFS= read -r line; do
        log_cmd "$line"
    done
    
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        die "pacstrap failed! Check your internet connection and try again."
    fi
    
    # Generate fstab
    log_step "Generating fstab..."
    genfstab -U "$MOUNT_POINT" >> "${MOUNT_POINT}/etc/fstab"
    log_ok "fstab generated."
    
    log_ok "Base system installed."
}
```

**Change from original plan:** `reflector --latest 20` instead of `--latest 10` (less aggressive, more reliable mirror selection).

---

## Step 9: Configure Base System (arch-chroot)

Configure the installed system from within chroot.

```bash
step_configure_system() {
    set_status "Configuring System..."
    
    BOOT_MODE=$(detect_boot_mode)
    
    # Detect NVIDIA BEFORE entering chroot (needs live PCI bus)
    HAS_NVIDIA=$(detect_nvidia)
    log_step "NVIDIA GPU detected: $HAS_NVIDIA"
    
    # Write a configuration script to run inside chroot
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
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "==> Configuring pacman..."
sed -i 's/^#Color/Color/' /etc/pacman.conf
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
# Enable multilib
sed -i '/\[multilib\]/,/Include/{s/^#//}' /etc/pacman.conf

echo "==> Installing GRUB bootloader..."
if [[ "${BOOT_MODE}" == "uefi" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    grub-install --target=i386-pc ${INSTALL_DISK}
fi
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Enabling essential services..."
systemctl enable NetworkManager

echo "==> System configuration complete."
CHROOT_EOF
    
    chmod +x "${MOUNT_POINT}/tmp/hyprflux-configure.sh"
    
    log_step "Running system configuration in chroot..."
    arch-chroot "$MOUNT_POINT" /bin/bash /tmp/hyprflux-configure.sh 2>&1 | \
        while IFS= read -r line; do
            log_cmd "$line"
        done
    
    # Clean up
    rm -f "${MOUNT_POINT}/tmp/hyprflux-configure.sh"
    
    log_ok "System configured."
}
```

**Changes from original plan:**
- All variables renamed: `TIMEZONE` -> `INSTALL_TIMEZONE`, `HOSTNAME` -> `INSTALL_HOSTNAME`, etc.
- NVIDIA detection done HERE (before chroot) using `detect_nvidia()` from common.sh
- `HAS_NVIDIA` variable is set here and passed to Phase 5's chroot wrapper as an env var

---

## Main Flow (assembling all steps)

This goes into `hyprflux-install.sh`, replacing the skeleton from Phase 3:

```bash
# ====== Collected configuration ======
INSTALL_TIMEZONE=""
INSTALL_LOCALE="en_US.UTF-8"
INSTALL_KEYMAP="us"
INSTALL_HOSTNAME="hyprflux"
INSTALL_USERNAME=""
INSTALL_PASSWORD=""
INSTALL_DISK=""
BOOT_MODE=""
MOUNT_POINT="/mnt/archinstall"
USE_SWAP=false
SWAP_SIZE=0
HAS_NVIDIA="no"

# ====== Run Steps ======
setup_network          # Step 0
step_welcome           # Step 1
step_timezone          # Step 2
step_locale            # Step 3
step_keyboard          # Step 4
step_hostname          # Step 5
step_user              # Step 6

mkdir -p "$MOUNT_POINT"
step_disk              # Step 7
step_base_install      # Step 8
step_configure_system  # Step 9

# Steps 10-11 are in Phase 5
```

---

## Edge Cases & Error Handling

| Edge Case | Handling |
|-----------|----------|
| No disks found | `die "No disks found!"` |
| Disk too small (<20GB) | Warn but allow (user's choice) |
| NVMe vs SATA partition naming | `get_part_prefix()` in common.sh |
| pacstrap fails (network drop) | `die` with re-run instructions |
| Invalid hostname/username | Validation loop, re-prompt |
| Password mismatch | Re-prompt (no limit) |
| Manual mode: user forgets to mount | Verify after shell exit, offer retry |
| BIOS without GPT BIOS boot partition | Create 1MB ef02 partition automatically |
| User presses Ctrl+C | Trapped in installer, drops to shell |

---

## Directory Structure After Phase 4

No new files -- Phase 4 fills in the skeleton installer from Phase 3:

```
airootfs/root/
├── .zlogin
├── hyprflux-install.sh    # Now ~400 lines (Steps 0-9)
└── lib/
    ├── tui.sh
    └── common.sh
```

---

## Validation Steps

1. Build ISO and boot in QEMU
2. Installer auto-launches with banner
3. Network step: test both "already connected" and WiFi flow
4. All prompts work: timezone, locale, keyboard, hostname, user
5. **Automatic disk**: select QEMU disk, partition, format, mount
6. **Manual disk**: drop to shell, manually partition, verify on return
7. pacstrap completes successfully
8. chroot configuration applies: check timezone, locale, user exists
9. GRUB installed correctly (UEFI and BIOS)
10. Test with `--bios` flag in QEMU for Legacy BIOS path

---

## Estimated Implementation Time

~2-4 hours. This is the largest phase.

---

## Dependencies

- **Requires Phase 1-3**: bootable ISO with TUI framework
- **Required by Phase 5**: base system must be installed before HyprFlux can be layered on top
