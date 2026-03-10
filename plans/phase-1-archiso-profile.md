# Phase 1: archiso Profile & Build Infrastructure

## Goal

Set up the foundational archiso profile that `mkarchiso` uses to build the HyprFlux ISO. This phase creates all the files that archiso requires: the profile definition, package list, pacman configuration, build script, and the live environment's filesystem structure.

After this phase, you should be able to run `sudo bash build.sh` and get a bootable ISO (with a blank TTY -- no installer yet).

---

## Prerequisites

- An Arch Linux host machine (or Arch container)
- `archiso` package installed (`sudo pacman -S archiso`)
- Root access (mkarchiso requires it)

---

## File List

| # | File | Lines | Description |
|---|------|-------|-------------|
| 1 | `build.sh` | ~90 | Master build script |
| 2 | `profiledef.sh` | ~30 | archiso profile definition |
| 3 | `packages.x86_64` | ~50 | Packages for the live environment |
| 4 | `pacman.conf` | ~70 | Pacman config used during ISO build |
| 5 | `airootfs/etc/hostname` | 1 | Live environment hostname |
| 6 | `airootfs/etc/locale.conf` | 1 | Live environment locale |
| 7 | `airootfs/etc/locale.gen` | 2 | Locale generation |
| 8 | `airootfs/etc/shadow` | 1 | Empty root password for live env |
| 9 | `airootfs/etc/mkinitcpio.conf.d/archiso.conf` | ~5 | initramfs hooks for live ISO |
| 10 | `airootfs/etc/systemd/network/20-ethernet.network` | ~8 | Auto DHCP for wired connections |
| 11 | `airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf` | ~5 | Auto-login root on tty1 |

---

## Detailed Specifications

### 1. `build.sh` (~90 lines)

The master build script. Run as root.

**Behavior:**
1. Verify running as root
2. Check `archiso` is installed -- offer to install if missing
3. Clean previous build artifacts (`work/` and `out/`)
4. Run `mkarchiso -v -w ./work -o ./out .`
5. Print ISO path, filename, and file size
6. Offer to clean `work/` directory (saves ~5-10GB)

**Key details:**
- Must be run from the repo root (where `profiledef.sh` lives)
- Uses `set -euo pipefail` for safety
- Passes all arguments through to mkarchiso
- The build takes ~5-15 minutes depending on internet speed and disk I/O

```bash
#!/bin/bash
# build.sh -- Build the HyprFlux ISO
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/work"
OUT_DIR="${SCRIPT_DIR}/out"

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (mkarchiso requires it)."
    echo "Usage: sudo bash build.sh"
    exit 1
fi

# Check archiso
if ! command -v mkarchiso &>/dev/null; then
    echo "Error: archiso is not installed."
    read -rp "Install it now? [y/N]: " ans
    if [[ "${ans,,}" == "y" ]]; then
        pacman -S --noconfirm archiso
    else
        exit 1
    fi
fi

# Clean previous builds
echo "Cleaning previous build artifacts..."
rm -rf "${WORK_DIR}" "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

# Build
echo "Building HyprFlux ISO..."
mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${SCRIPT_DIR}"

# Report
ISO_FILE=$(ls "${OUT_DIR}"/*.iso 2>/dev/null | head -1)
if [[ -n "$ISO_FILE" ]]; then
    ISO_SIZE=$(du -h "$ISO_FILE" | cut -f1)
    echo ""
    echo "=== Build Complete ==="
    echo "ISO: $ISO_FILE"
    echo "Size: $ISO_SIZE"
    
    sha256sum "$ISO_FILE" > "${ISO_FILE}.sha256"
    echo "SHA256: $(cat "${ISO_FILE}.sha256")"
else
    echo "Error: No ISO file found in ${OUT_DIR}/"
    exit 1
fi
```

---

### 2. `profiledef.sh` (~30 lines)

archiso profile metadata. This tells mkarchiso how to build the ISO.

**Key decisions:**
- **Both UEFI and Legacy BIOS** boot support
- squashfs with xz compression for smaller ISO size
- File permissions set for shadow and installer script

```bash
#!/usr/bin/env bash
# profiledef.sh -- archiso profile definition for HyprFlux

iso_name="hyprflux"
iso_label="HYPRFLUX_$(date +%Y%m)"
iso_publisher="HyprFlux <https://github.com/ahmad9059/HyprFlux>"
iso_application="HyprFlux Arch Linux Installer"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=(
  'bios.syslinux.mbr'
  'bios.syslinux.eltorito'
  'uefi-ia32.grub.esp'
  'uefi-x64.grub.esp'
  'uefi-ia32.grub.eltorito'
  'uefi-x64.grub.eltorito'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/hyprflux-install.sh"]="0:0:755"
)
```

---

### 3. `packages.x86_64` (~50 lines)

Packages for the **live ISO environment** (NOT the target installed system).

```
# Base system
base
linux
linux-firmware
mkinitcpio
mkinitcpio-archiso
syslinux

# Arch install tools
arch-install-scripts
gptfdisk
dosfstools
e2fsprogs
parted

# Bootloader
grub
efibootmgr

# Network
networkmanager
iwd
iw
wpa_supplicant
dhcpcd
openssh
curl
wget

# TUI
dialog

# Utilities
vim
nano
git
sudo
less
reflector

# CPU microcode
amd-ucode
intel-ucode
sof-firmware

# Shell
zsh

# Filesystem tools
btrfs-progs
xfsprogs
ntfs-3g
```

---

### 4. `pacman.conf` (~70 lines)

```ini
[options]
HoldPkg      = pacman glibc
Architecture = auto
SigLevel          = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5
Color
CheckSpace
VerbosePkgLists

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
```

---

### 5-8. Static Configuration Files

| File | Content |
|------|---------|
| `airootfs/etc/hostname` | `hyprflux` |
| `airootfs/etc/locale.conf` | `LANG=en_US.UTF-8` |
| `airootfs/etc/locale.gen` | `en_US.UTF-8 UTF-8` + `en_US ISO-8859-1` |
| `airootfs/etc/shadow` | `root::14871::::::` |

---

### 9. `airootfs/etc/mkinitcpio.conf.d/archiso.conf`

```
HOOKS=(base udev modconf archiso archiso_loop_mnt block filesystems keyboard)
COMPRESSION="xz"
```

---

### 10. `airootfs/etc/systemd/network/20-ethernet.network`

```ini
[Match]
Name=en*
Name=eth*

[Network]
DHCP=yes
IPv6PrivacyExtensions=yes
```

---

### 11. `airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf`

```ini
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 38400 linux
```

---

## Validation Steps

1. `bash -n build.sh` -- syntax check
2. `sudo bash build.sh` -- should produce ISO in `out/`
3. `./test-qemu.sh --uefi` -- boots to auto-login root shell
4. `./test-qemu.sh --bios` -- boots to auto-login root shell
5. In live env: `dialog --version` and `git --version` both work

---

## Dependencies on Other Phases

- Phase 2 adds GRUB and syslinux boot config files
- Phase 3 adds the TUI branding and installer framework
- Phase 4 builds the actual installer logic
- Phase 5 integrates HyprFlux repos

**Phase 1 produces a bootable ISO that drops to a root shell. Later phases add the installer.**
