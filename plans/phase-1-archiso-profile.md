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
| 8 | `airootfs/etc/passwd` | 1 | Root user entry (shell = zsh) |
| 9 | `airootfs/etc/shadow` | 1 | Empty root password for live env |
| 10 | `airootfs/etc/mkinitcpio.conf.d/archiso.conf` | ~5 | initramfs hooks for live ISO |
| 11 | `airootfs/etc/mkinitcpio.d/linux.preset` | ~8 | Override mkinitcpio preset (archiso-only) |
| 12 | `airootfs/etc/systemd/journal.conf.d/volatile-storage.conf` | ~3 | Volatile journal (no disk writes) |
| 13 | `airootfs/etc/systemd/logind.conf.d/do-not-suspend.conf` | ~3 | Prevent suspend on lid close |
| 14 | `airootfs/etc/systemd/system/pacman-init.service` | ~15 | Initialize pacman keyring at boot |
| 15 | `airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf` | ~5 | Auto-login root on tty1 |

**NOTE:** No `systemd-networkd` `.network` files. We use NetworkManager exclusively (needed for `nmcli`/`nmtui` in the installer). NetworkManager is enabled via a systemd preset.

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
- No manual `sed` replacements needed -- mkarchiso handles template variable substitution automatically (`%ARCHISO_UUID%`, `%INSTALL_DIR%`, `%ARCH%`)

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
- **Both UEFI and Legacy BIOS** boot support using the standard 2 bootmodes (matching releng)
- `uefi.systemd-boot` for UEFI (not GRUB — GRUB is the fallback, systemd-boot is primary)
- `bios.syslinux` for Legacy BIOS
- squashfs with xz compression for smaller ISO size
- `install_dir="hyprflux"` — unique per distro to avoid USB conflicts with other archiso-based ISOs
- File permissions set for shadow, installer script, and library files

```bash
#!/usr/bin/env bash
# profiledef.sh -- archiso profile definition for HyprFlux

iso_name="hyprflux"
iso_label="HYPRFLUX_$(date +%Y%m)"
iso_publisher="HyprFlux <https://github.com/ahmad9059/HyprFlux>"
iso_application="HyprFlux Arch Linux Installer"
iso_version="$(date +%Y.%m.%d)"
install_dir="hyprflux"
buildmodes=('iso')
bootmodes=(
  'bios.syslinux'
  'uefi.systemd-boot'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/hyprflux-install.sh"]="0:0:755"
  ["/root/lib"]="0:0:755"
  ["/root/lib/tui.sh"]="0:0:755"
  ["/root/lib/common.sh"]="0:0:755"
  ["/root/lib/hyprflux-chroot-wrapper.sh"]="0:0:755"
)
```

**Changes from original plan:**
- `bootmodes` reduced from 6 to 2 (matching releng profile)
- `install_dir` changed from `arch` to `hyprflux` (avoids USB conflicts)
- Added permission for `hyprflux-chroot-wrapper.sh` (Phase 5)

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

# Bootloader (for target system install, also needed for ISO EFI)
grub
efibootmgr

# Network (NetworkManager only — no systemd-networkd)
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
pciutils

# CPU microcode
amd-ucode
intel-ucode
sof-firmware

# Shell (root shell is zsh for .zlogin auto-launch)
zsh

# Filesystem tools
btrfs-progs
xfsprogs
ntfs-3g
```

**Changes from original plan:**
- Added `pciutils` (needed for `lspci` NVIDIA detection BEFORE entering chroot)
- Comment clarifying NetworkManager-only approach

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

### 5-9. Static Configuration Files

| File | Content |
|------|---------|
| `airootfs/etc/hostname` | `hyprflux` |
| `airootfs/etc/locale.conf` | `LANG=en_US.UTF-8` |
| `airootfs/etc/locale.gen` | `en_US.UTF-8 UTF-8` + `en_US ISO-8859-1` |
| `airootfs/etc/passwd` | `root:x:0:0:root:/root:/usr/bin/zsh` |
| `airootfs/etc/shadow` | `root::14871::::::` |

**CRITICAL:** The `passwd` file MUST set root's shell to `/usr/bin/zsh` so that `.zlogin` executes on auto-login, which triggers the TUI installer. Without this file, root's shell defaults to `/bin/bash` and `.zlogin` is never read.

---

### 10. `airootfs/etc/mkinitcpio.conf.d/archiso.conf`

Uses the full hook set from the releng profile (including microcode, PXE support, etc.):

```
HOOKS=(base udev microcode modconf kms memdisk archiso archiso_loop_mnt archiso_pxe_common archiso_pxe_nbd archiso_pxe_http archiso_pxe_nfs block filesystems keyboard)
COMPRESSION="xz"
```

**Changes from original plan:**
- Added `microcode`, `kms`, `memdisk`, PXE hooks (matching releng)

---

### 11. `airootfs/etc/mkinitcpio.d/linux.preset` (NEW)

Overrides the default mkinitcpio preset to only build the `archiso` image, avoiding unnecessary fallback initramfs generation:

```bash
PRESETS=('archiso')

archiso_kver="/boot/vmlinuz-linux"
archiso_image="/boot/initramfs-linux.img"
```

---

### 12. `airootfs/etc/systemd/journal.conf.d/volatile-storage.conf` (NEW)

Prevents journal from writing to disk (critical for live ISO — the root filesystem is a ramdisk):

```ini
[Journal]
Storage=volatile
```

---

### 13. `airootfs/etc/systemd/logind.conf.d/do-not-suspend.conf` (NEW)

Prevents the system from suspending when the laptop lid is closed (annoying during installation):

```ini
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

---

### 14. `airootfs/etc/systemd/system/pacman-init.service` (NEW)

Initializes the pacman keyring at boot. Without this, `pacstrap` will fail with GPG signature verification errors:

```ini
[Unit]
Description=Initializes Pacman Keyring
Before=sshd.service
ConditionDirectoryNotEmpty=!/etc/pacman.d/gnupg

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/pacman-key --init
ExecStart=/usr/bin/pacman-key --populate

[Install]
WantedBy=multi-user.target
```

Also need a systemd preset file to enable this and NetworkManager:

**`airootfs/etc/systemd/system/multi-user.target.wants/pacman-init.service`** → symlink to `../pacman-init.service`

**`airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service`** → symlink to `/usr/lib/systemd/system/NetworkManager.service`

These symlinks are created by archiso when the profile specifies them. In practice, we create the symlink directories in airootfs.

---

### 15. `airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf`

```ini
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I 38400 linux
```

---

## Validation Steps

1. `bash -n build.sh` -- syntax check
2. `sudo bash build.sh` -- should produce ISO in `out/`
3. `./test-qemu.sh --uefi` -- boots to auto-login root shell (zsh)
4. `./test-qemu.sh --bios` -- boots to auto-login root shell (zsh)
5. In live env: `dialog --version` and `git --version` both work
6. In live env: `lspci` works (needed for NVIDIA detection)
7. In live env: `pacman-key --list-keys` shows populated keyring
8. In live env: `systemctl status NetworkManager` shows active

---

## Dependencies on Other Phases

- Phase 2 adds systemd-boot and syslinux boot config files
- Phase 3 adds the TUI branding and installer framework
- Phase 4 builds the actual installer logic
- Phase 5 integrates HyprFlux repos via chroot wrapper

**Phase 1 produces a bootable ISO that drops to a root zsh shell. Later phases add the installer.**
