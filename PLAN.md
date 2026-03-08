# Hyprflux-ISO — Implementation Plan

> **Created**: 2026-03-08
> **Status**: Approved, pending implementation

---

## Table of Contents

1. [Overview](#overview)
2. [User Decisions](#user-decisions)
3. [Architecture](#architecture)
4. [Reference Repositories Summary](#reference-repositories-summary)
5. [Phase 1: Foundation](#phase-1-foundation-profile--packages)
6. [Phase 2: AUR Package Infrastructure](#phase-2-aur-package-infrastructure)
7. [Phase 3: Airootfs Overlay](#phase-3-airootfs-overlay)
8. [Phase 4: Boot Configuration](#phase-4-boot-configuration)
9. [Phase 5: Custom TUI Installer](#phase-5-custom-tui-installer)
10. [Phase 6: Build Infrastructure](#phase-6-build-infrastructure)
11. [Phase 7: CI/CD](#phase-7-cicd)
12. [Key Technical Decisions](#key-technical-decisions)
13. [Consolidated Package List](#consolidated-package-list)
14. [Execution Order](#execution-order)

---

## Overview

Build a custom Arch Linux ISO using `archiso`/`mkarchiso` that ships a fully pre-configured **HyprFlux** Hyprland desktop. The ISO:

- **Supports both Legacy BIOS and UEFI boot** (Syslinux for BIOS, GRUB for UEFI, isohybrid for USB/optical)
- Boots directly into Hyprland via SDDM auto-login
- Includes a custom TUI installer for disk installation
- Pre-bakes all dotfiles, themes, and configurations
- Auto-detects NVIDIA GPUs at boot time
- Ships AUR packages via a custom local repo
- Is built and released via GitHub Actions

### Boot Compatibility Matrix

| Boot Mode | Firmware | Boot Loader | Medium | Supported |
|-----------|----------|-------------|--------|-----------|
| Legacy BIOS | MBR/CSM | Syslinux (isolinux) | USB, CD/DVD | Yes |
| UEFI x64 | GPT/UEFI | GRUB | USB, CD/DVD | Yes |
| UEFI IA32 (mixed-mode) | GPT/UEFI | GRUB (ia32) | USB, CD/DVD | Yes |
| UEFI Secure Boot | GPT/UEFI | Requires signed shim | USB | Not initially (future) |

The ISO is built as an **isohybrid** image via El Torito, meaning the same `.iso` file can be:
- Burned to optical disc (CD/DVD) for both BIOS and UEFI boot
- Written to USB flash drive via `dd` for both BIOS and UEFI boot

---

## User Decisions

| Question | Decision |
|----------|----------|
| Disk installer | Custom TUI installer (dialog/whiptail) |
| Live session | Auto-login to Hyprland via SDDM |
| CI/CD | GitHub Actions (auto-build on push/tag) |
| AUR packages | Pre-built custom local repo included in ISO |
| ISO scope | Full-featured (all optional packages from module 17) |
| Web apps (PWAs) | Include all 28 Chromium PWA desktop entries |
| NVIDIA support | Auto-detect at boot (Mesa + NVIDIA drivers both included) |
| Neovim config | Pre-baked in /etc/skel/.config/nvim/ |

---

## Architecture

```
Hyprflux-ISO/
├── profiledef.sh                 # archiso profile definition
├── packages.x86_64               # all official repo packages
├── pacman.conf                   # pacman config for build (includes custom repo)
├── airootfs/                     # root filesystem overlay
│   ├── etc/
│   │   ├── hostname              # "hyprflux"
│   │   ├── locale.conf           # LANG=en_US.UTF-8
│   │   ├── locale.gen
│   │   ├── os-release            # HyprFlux branding
│   │   ├── passwd                # root + live user "hyprflux"
│   │   ├── shadow
│   │   ├── group
│   │   ├── gshadow
│   │   ├── pacman.conf           # live system pacman.conf (with multilib)
│   │   ├── pacman.d/hooks/       # locale-gen + cleanup hooks
│   │   ├── sddm.conf             # SDDM with simple-sddm-2 theme
│   │   ├── default/grub          # GRUB config with Vimix theme
│   │   ├── mkinitcpio.conf.d/    # archiso + plymouth hooks
│   │   ├── mkinitcpio.d/         # kernel preset
│   │   ├── modprobe.d/           # broadcom-wl blacklist
│   │   ├── skel/                 # <-- all HyprFlux dotfiles live here
│   │   │   └── .config/
│   │   │       ├── hypr/         # Hyprland config (merged KooL + HyprFlux)
│   │   │       ├── waybar/
│   │   │       ├── kitty/
│   │   │       ├── rofi/
│   │   │       ├── swaync/
│   │   │       ├── foot/
│   │   │       ├── cava/
│   │   │       ├── fastfetch/
│   │   │       ├── btop/
│   │   │       ├── wlogout/
│   │   │       ├── Kvantum/
│   │   │       ├── qt5ct/
│   │   │       ├── qt6ct/
│   │   │       ├── yazi/
│   │   │       ├── ghostty/
│   │   │       ├── quickshell/
│   │   │       ├── swappy/
│   │   │       ├── nvim/         # Pre-baked neovim config
│   │   │       ├── wallust/
│   │   │       └── mimeapps.list
│   │   ├── systemd/system/       # Service enable symlinks
│   │   │   ├── display-manager.service -> sddm.service
│   │   │   ├── multi-user.target.wants/
│   │   │   │   ├── bluetooth.service -> ...
│   │   │   │   ├── NetworkManager.service -> ...
│   │   │   │   └── sshd.service -> ...
│   │   │   ├── getty@tty1.service.d/autologin.conf
│   │   │   └── ...
│   │   └── xdg/autostart/        # Desktop autostart entries
│   ├── usr/
│   │   ├── share/
│   │   │   ├── sddm/themes/simple-sddm-2/
│   │   │   ├── plymouth/themes/hyprland-mac-style/
│   │   │   ├── grub/themes/Vimix/
│   │   │   ├── themes/HyprFlux-Compact/      # GTK theme
│   │   │   ├── icons/Papirus-Dark/            # Icon theme (cyan)
│   │   │   ├── icons/Future-black-cursors/    # Cursor theme
│   │   │   ├── icons/Bibata-Modern-Classic/   # Hyprcursor
│   │   │   ├── applications/                  # 28 PWA .desktop entries
│   │   │   └── wallpapers/                    # Bundled wallpapers
│   │   └── local/bin/
│   │       ├── hyprflux-install  # Custom TUI disk installer
│   │       └── hyprflux-welcome  # Welcome/first-run app
│   └── root/                     # Root user home (for live TTY fallback)
├── efiboot/                      # systemd-boot config for UEFI
│   └── loader/
│       ├── loader.conf
│       └── entries/
│           ├── 01-archiso-x86_64-linux.conf
│           └── 02-archiso-x86_64-linux-nvidia.conf
├── syslinux/                     # BIOS boot config
│   ├── archiso_head.cfg
│   ├── archiso_sys-linux.cfg
│   └── syslinux.cfg
├── grub/                         # GRUB UEFI boot config (with Vimix theme)
│   └── grub.cfg
├── aur/                          # AUR package build infrastructure
│   ├── build-aur.sh              # Script to build AUR packages
│   ├── repo/                     # Generated local repo (gitignored)
│   └── PKGBUILDS/                # Tracked PKGBUILDs for reproducibility
├── build.sh                      # Main build script (wraps mkarchiso)
├── .github/workflows/
│   └── build-iso.yml             # GitHub Actions CI/CD
├── .gitignore
└── references/                   # (gitignored) reference repos
```

---

## Reference Repositories Summary

### 1. HyprFlux (`references/HyprFlux/`)

Ahmad's custom dotfiles + installer project. Primary source of truth for the ISO.

- **Website**: https://hyprflux.dev
- **Install flow**: `install.sh` → clones Arch-Hyprland → runs it → then runs `dotsSetup.sh`
- **`dotsSetup.sh`**: Modular orchestrator with 17 modules:

| Module | Purpose |
|--------|---------|
| `01-backup.sh` | Backs up existing configs |
| `02-dotfiles.sh` | Copies HyprFlux `.config/` to `~/.config/` |
| `03-packages.sh` | Installs foot, lsd, bat, neovim, firefox, tmux, yazi, zoxide, chromium, npm, plymouth, rclone, gh |
| `04-neovim.sh` | Clones custom nvim config |
| `05-themes.sh` | GTK themes, Papirus icons (cyan), Future Black cursors |
| `06-waybar.sh` | Symlinks custom waybar style/layout |
| `07-sddm.sh` | Installs simple-sddm-2 SDDM theme |
| `08-gtk.sh` | Sets GTK/icon/cursor/font via gsettings |
| `09-grub.sh` | Installs Vimix GRUB theme |
| `10-plymouth.sh` | Installs hyprland-mac-style Plymouth theme + mkinitcpio hook |
| `11-tmux.sh` | Copies `.tmux.conf` + tmuxifier |
| `12-zsh.sh` | Zsh + Oh-My-Zsh setup |
| `13-wallpapers.sh` | Clones wallpapers-bank |
| `14-webapps.sh` | Creates 28 Chromium PWA desktop entries with icons |
| `15-quickshell.sh` | Enables QuickShell overview if installed |
| `16-bibata.sh` | Installs Bibata-Modern-Classic hyprcursor |
| `17-optional-packages.sh` | Interactive install of VS Code, obs-studio, vlc, vesktop, etc. |

- **Lib system**: `lib/common.sh`, `lib/packages.sh`, `lib/git.sh` with retry logic, logging, skip mechanism
- **Key customizations over KooL base**:
  - Custom GTK theme (`HyprFlux-Compact`)
  - Future Black cursors + Bibata-Modern-Classic hyprcursor
  - Papirus-Dark icons with cyan folders
  - Vimix GRUB theme + hyprland-mac-style Plymouth
  - 28 pre-configured web app PWAs
  - Custom neovim config, tmux/tmuxifier
  - Own wallpaper bank repository

### 2. Arch-Hyprland (`references/Arch-Hyprland/`)

Ahmad's fork of JaKooLit's installer. Provides base Hyprland package installation.

- **30 scripts** in `install-scripts/`
- **Execution flow**: 8 mandatory scripts → user-selected optional scripts → dotfiles → final check
- **`Global_functions.sh`**: Defines `install_package` (uses yay/paru), `install_package_pacman` (direct pacman)
- **Ahmad's customizations**: HyprFlux branding, custom curl scripts from `ahmad9059/Scripts`, GTK themes option commented out, monitor scripts ported from Fedora-Hyprland

**Mandatory scripts (always run)**:
1. `00-base.sh` — base-devel, archlinux-keyring, findutils
2. `pacman.sh` — pacman.conf tweaks (Color, ParallelDownloads, ILoveCandy)
3. Custom curl scripts (Ahmad's personal)
4. `paru.sh` or `yay.sh` — AUR helper
5. `01-hypr-pkgs.sh` — 53 core Hyprland packages
6. `pipewire.sh` — PipeWire audio stack
7. `fonts.sh` — 10 font packages
8. `hyprland.sh` — hyprland + hypridle + hyprlock

**Optional scripts**:
- `sddm.sh` + `sddm_theme.sh` — SDDM display manager
- `nvidia.sh` — NVIDIA drivers
- `bluetooth.sh` — Bluetooth stack
- `thunar.sh` — File manager
- `xdph.sh` — XDG desktop portals
- `quickshell.sh` — Desktop overview
- `zsh.sh` — Zsh + Oh-My-Zsh
- `rog.sh` — ASUS ROG support
- `dotfiles-main.sh` — Clone and deploy KooL dots

### 3. Hyprland-Dots (`references/Hyprland-Dots/`)

Ahmad's fork of JaKooLit's dotfiles (v2.3.20). Base config layer.

- **18 app config directories**: hypr, waybar, rofi, kitty, swaync, wallust, wlogout, fastfetch, btop, cava, swappy, Kvantum, qt5ct, qt6ct, ghostty, wezterm, ags, quickshell
- **`copy.sh`** (655 lines): Orchestrates install/upgrade using 7 helper libraries
- **40+ scripts**: Theme switching, wallpaper management, waybar/rofi customization, system controls, wallust color pipeline
- **Hyprland config**: Thin `hyprland.conf` sourcing from `configs/` (system defaults) and `UserConfigs/` (user overrides); dwindle layout, 237-line keybinds
- **Wallpapers**: 4 static (~37MB) + optional 1GB bank download
- **Near-exact upstream mirror**: Only README archiving notice differs

---

## Phase 1: Foundation (Profile + Packages)

### 1.1 Initialize git repo

```bash
git init
```

### 1.2 Create `profiledef.sh`

Based on releng profile, customized for HyprFlux:

```bash
iso_name="hyprflux"
iso_label="HYPRFLUX_$(date +%Y%m)"
iso_publisher="HyprFlux <https://hyprflux.dev>"
iso_application="HyprFlux Live/Installer"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux' 'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/hyprflux-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/home/hyprflux"]="1000:1000:750"
  ["/usr/local/bin/hyprflux-install"]="0:0:755"
  ["/usr/local/bin/hyprflux-welcome"]="0:0:755"
  ["/usr/local/bin/hyprflux-nvidia-detect"]="0:0:755"
)
```

### 1.3 Create `packages.x86_64`

Full consolidated list from all three references (see [Consolidated Package List](#consolidated-package-list)).

### 1.4 Create `pacman.conf`

Based on releng, additions:
- `[multilib]` enabled
- `[hyprflux]` custom local repo (for AUR packages)
- `Color`, `ParallelDownloads = 5`

---

## Phase 2: AUR Package Infrastructure

### 2.1 Create `aur/build-aur.sh`

Script that:
1. Creates a clean build environment
2. Clones each AUR PKGBUILD
3. Builds with `makepkg -s`
4. Adds `.pkg.tar.zst` files to `aur/repo/`
5. Generates `hyprflux.db.tar.gz` local repo database

### 2.2 AUR packages to build

| Package | Purpose |
|---------|---------|
| `yay-bin` | AUR helper for post-install |
| `quickshell` | Desktop overview shell |
| `ttf-fantasque-nerd` | Nerd font variant |
| `visual-studio-code-bin` | Code editor |
| `64gram-desktop-bin` | Telegram client |
| `vesktop` | Discord client |
| `stacer-bin` | System optimizer |
| `localsend-bin` | Local file sharing |

### 2.3 Track PKGBUILDs in `aur/PKGBUILDS/` for reproducibility

---

## Phase 3: Airootfs Overlay

### 3.1 User accounts

**`airootfs/etc/passwd`**:
```
root:x:0:0:root:/root:/usr/bin/zsh
hyprflux:x:1000:1000:HyprFlux Live User:/home/hyprflux:/usr/bin/zsh
```

**`airootfs/etc/group`**:
```
root:x:0:root
wheel:x:10:hyprflux
video:x:12:hyprflux
audio:x:17:hyprflux
input:x:97:hyprflux
storage:x:98:hyprflux
optical:x:93:hyprflux
network:x:90:hyprflux
lp:x:7:hyprflux
hyprflux:x:1000:
```

**`airootfs/etc/shadow`**:
```
root::14871::::::
hyprflux::14871::::::
```

**Sudoers** (`airootfs/etc/sudoers.d/hyprflux-live`):
```
hyprflux ALL=(ALL) NOPASSWD: ALL
```

### 3.2 Dotfiles in `/etc/skel/`

**Source priority** (HyprFlux overrides KooL):
1. Copy all KooL Hyprland-Dots `.config/` as base
2. Overlay HyprFlux `.config/` on top (overrides where both exist)
3. Include `.zshrc`, `.tmux.conf`, tmuxifier config
4. Pre-bake neovim config in `.config/nvim/`

### 3.3 System configuration

| File | Content |
|------|---------|
| `/etc/hostname` | `hyprflux` |
| `/etc/locale.conf` | `LANG=en_US.UTF-8` |
| `/etc/locale.gen` | `en_US.UTF-8 UTF-8` |
| `/etc/os-release` | HyprFlux-branded Arch Linux |
| `/etc/sddm.conf` | simple-sddm-2 theme, autologin user hyprflux |
| `/etc/default/grub` | Vimix theme, plymouth args |
| `/etc/pacman.conf` (live) | Color, ILoveCandy, ParallelDownloads, multilib |
| `/etc/modprobe.d/broadcom-wl.conf` | Blacklist b43/ssb |

### 3.4 Theme assets

| Asset | Target Path |
|-------|-------------|
| simple-sddm-2 SDDM theme | `/usr/share/sddm/themes/simple-sddm-2/` |
| hyprland-mac-style Plymouth | `/usr/share/plymouth/themes/hyprland-mac-style/` |
| Vimix GRUB theme | `/usr/share/grub/themes/Vimix/` |
| HyprFlux-Compact GTK theme | `/usr/share/themes/HyprFlux-Compact/` |
| Future Black cursors | `/usr/share/icons/Future-black-cursors/` |
| Bibata-Modern-Classic hyprcursor | `/usr/share/icons/Bibata-Modern-Classic/` |
| Bundled wallpapers (select set) | `/usr/share/wallpapers/` |

### 3.5 Systemd service symlinks

```
display-manager.service -> /usr/lib/systemd/system/sddm.service
multi-user.target.wants/bluetooth.service -> /usr/lib/systemd/system/bluetooth.service
multi-user.target.wants/NetworkManager.service -> /usr/lib/systemd/system/NetworkManager.service
multi-user.target.wants/sshd.service -> /usr/lib/systemd/system/sshd.service
```

PipeWire user services via preset in `/etc/systemd/user/default.target.wants/`:
```
pipewire.service -> /usr/lib/systemd/user/pipewire.service
pipewire-pulse.service -> /usr/lib/systemd/user/pipewire-pulse.service
wireplumber.service -> /usr/lib/systemd/user/wireplumber.service
```

### 3.6 Web apps

- 28 `.desktop` files in `/usr/share/applications/`
- Pre-downloaded icons in `/usr/share/icons/hicolor/256x256/apps/`
- Apps: Netflix, YouTube, GitHub, ChatGPT, Claude, Spotify, Gmail, etc.

### 3.7 NVIDIA auto-detection

Script at `/usr/local/bin/hyprflux-nvidia-detect`:
- Checks `lspci` for NVIDIA GPU
- If found: loads nvidia modules, sets env vars (`GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, etc.)
- Integrates with Hyprland's env config
- Two boot entries: default (auto-detect) and explicit NVIDIA

---

## Phase 4: Boot Configuration (BIOS + UEFI)

Both boot paths present identical menu entries — the only difference is the boot loader rendering them.

**Boot menu entries** (shared across BIOS and UEFI):
1. **"Boot HyprFlux"** — Default, auto-detect GPU, launch SDDM → Hyprland
2. **"Boot HyprFlux (NVIDIA)"** — Force `nvidia-drm.modeset=1` kernel parameter
3. **"Boot HyprFlux (Safe Graphics)"** — `nomodeset` for troubleshooting
4. **"Boot existing OS"** — Chainload local disk (BIOS) / exit to firmware (UEFI)

**Common kernel parameters** (all entries):
```
archisobasedir=%INSTALL_DIR% archisolabel=%ARCHISO_LABEL%
cow_spacesize=4G quiet splash loglevel=3
```

### 4.1 Syslinux — Legacy BIOS Boot

- **Directory**: `syslinux/`
- **Boot loader**: isolinux (El Torito no-emulation for CD) + isohybrid MBR for USB
- **Files**:
  - `syslinux.cfg` — Main config, includes sub-configs
  - `archiso_sys-linux.cfg` — Linux boot entries (normal, NVIDIA, safe)
  - `archiso_pxe-linux.cfg` — PXE netboot entry (optional)
  - `archiso_head.cfg` — Menu header with HyprFlux branding
  - `archiso_tail.cfg` — "Boot existing OS" + reboot/poweroff
  - `splash.png` — HyprFlux boot splash (640x480 for syslinux)
- **Mechanism**: Syslinux is embedded via `isohybrid` into the ISO's MBR. BIOS firmware reads the MBR, chainloads isolinux, which presents the text/graphical menu.

### 4.2 GRUB — UEFI Boot

- **Directory**: `grub/`
- **Boot loader**: GRUB with Vimix theme
- **Files**:
  - `grub.cfg` — Main GRUB config with menu entries, Vimix theme path
  - `loopback.cfg` — For booting ISO from GRUB loopback (Ventoy, etc.)
- **Theme**: Vimix GRUB theme files are placed in `airootfs/usr/share/grub/themes/Vimix/` and referenced in `grub.cfg`
- **Mechanism**: mkarchiso creates a FAT ESP image containing GRUB EFI binaries (`BOOTX64.EFI`, `grubia32.efi` for mixed-mode IA32 UEFI). The UEFI firmware reads the ESP, launches GRUB, which presents the themed graphical menu.
- **Mixed-mode IA32**: When `bootmodes` includes `uefi.grub` on x86_64, archiso automatically adds IA32 UEFI support for older UEFI systems that only have 32-bit firmware.

### 4.3 Template Identifiers

Both syslinux and GRUB configs use archiso template identifiers that mkarchiso replaces at build time:
- `%ARCHISO_LABEL%` → `HYPRFLUX_YYYYMM` (ISO volume label)
- `%INSTALL_DIR%` → `arch` (directory on ISO containing squashfs)
- `%ARCH%` → `x86_64`
- `%ARCHISO_UUID%` → ISO 9660 modification date (GRUB only)
- `%ARCHISO_SEARCH_FILENAME%` → search file for GRUB volume detection (GRUB only)

### 4.4 How `dd` to USB Works (Both Firmware Types)

When the ISO is written to USB via `dd`:
- **BIOS path**: Firmware reads MBR → isohybrid boot code → Syslinux
- **UEFI path**: Firmware reads GPT/ESP → FAT partition with GRUB EFI → GRUB
- Both coexist in the same ISO image thanks to isohybrid + El Torito

---

## Phase 5: Custom TUI Installer

### 5.1 `hyprflux-install`

A comprehensive bash TUI installer using `dialog`:

**Steps**:
1. Welcome screen with HyprFlux ASCII art
2. Keyboard layout selection
3. Disk selection (list available disks)
4. **Boot mode detection** (auto-detect UEFI vs BIOS via `/sys/firmware/efi`):
   - **UEFI detected**: Create GPT partition table, ESP (512MB FAT32) + root
   - **BIOS detected**: Create MBR partition table, boot (512MB ext4) + root
5. Partition scheme:
   - Auto (layout based on detected firmware, see above)
   - Auto with encryption (LUKS on root partition)
   - Manual (launch cfdisk/fdisk)
6. Filesystem choice (ext4 / btrfs) for root partition
7. Timezone selection
8. Locale selection
9. Hostname input
10. User creation (username + password)
11. Bootloader selection:
    - **UEFI**: GRUB (with Vimix theme) or systemd-boot
    - **BIOS**: GRUB only (MBR install)
12. Review summary
13. Execute installation:
    - Partition and format
    - Mount filesystems
    - `pacstrap` base system + all HyprFlux packages
    - Generate `/etc/fstab`
    - Copy configs from live system
    - `arch-chroot` to configure: locale, timezone, hostname, users, mkinitcpio, bootloader
    - **UEFI**: `grub-install --target=x86_64-efi` or `bootctl install`
    - **BIOS**: `grub-install --target=i386-pc /dev/sdX`
    - Enable services
    - Deploy dotfiles to new user via `/etc/skel/`
14. Reboot prompt

### 5.2 Desktop shortcut

`/usr/share/applications/hyprflux-install.desktop`:
```ini
[Desktop Entry]
Name=Install HyprFlux
Comment=Install HyprFlux to your disk
Exec=kitty --title "HyprFlux Installer" sudo hyprflux-install
Icon=system-software-install
Type=Application
Categories=System;
```

---

## Phase 6: Build Infrastructure

### 6.1 `build.sh`

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/work"
OUT_DIR="${SCRIPT_DIR}/out"

# Step 1: Build AUR packages
echo "Building AUR packages..."
"${SCRIPT_DIR}/aur/build-aur.sh"

# Step 2: Build ISO
echo "Building ISO..."
sudo mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${SCRIPT_DIR}"

echo "ISO built successfully in ${OUT_DIR}/"
```

### 6.2 QEMU test script

```bash
#!/bin/bash
# test-qemu.sh — Test the ISO in QEMU
ISO=$(ls -t out/*.iso | head -1)
run_archiso -u -i "${ISO}"
```

---

## Phase 7: CI/CD

### 7.1 `.github/workflows/build-iso.yml`

**Triggers**: push to `main`, tags (`v*`), manual dispatch

**Steps**:
1. Checkout code
2. Set up Arch Linux container/chroot
3. Install `archiso` package
4. Build AUR packages (`aur/build-aur.sh`)
5. Run `mkarchiso`
6. Upload ISO as artifact
7. On tag push: create GitHub Release with ISO attached

**Estimated build time**: 15-30 minutes (depending on runner)

---

## Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Boot loader (ISO) | GRUB for UEFI + Syslinux for BIOS | GRUB required for Vimix theme |
| Display manager | SDDM with auto-login | Matches HyprFlux's existing setup |
| Network manager | NetworkManager (not systemd-networkd) | Better desktop integration, nm-applet in tray |
| Init system hooks | archiso + plymouth | Plymouth for branded boot splash |
| Filesystem image | squashfs (xz compression) | Standard, good compression |
| Live user | `hyprflux` (UID 1000, passwordless sudo) | Standard for live ISOs |
| AUR packages | Pre-built custom local repo | Professional, no internet required at boot |
| Installer | Custom TUI (dialog/whiptail) | Lightweight and Arch-native |
| NVIDIA | Auto-detect + separate boot entry | Covers both AMD/Intel and NVIDIA users |
| Dotfiles source | Pre-baked in /etc/skel/ | Zero-config experience on login |
| Dotfile merge strategy | KooL base + HyprFlux override | HyprFlux configs take precedence |

---

## Consolidated Package List

### Base System
```
base
linux
linux-firmware
linux-headers
base-devel
archlinux-keyring
findutils
```

### Microcode
```
amd-ucode
intel-ucode
```

### Boot & Init
```
grub
efibootmgr
mkinitcpio
mkinitcpio-archiso
plymouth
syslinux
```

### Hyprland Core
```
hyprland
hypridle
hyprlock
hyprpolkitagent
xdg-desktop-portal-hyprland
xdg-desktop-portal-gtk
umockdev
```

### Display Manager
```
sddm
qt6-declarative
qt6-svg
qt6-virtualkeyboard
qt6-multimedia-ffmpeg
qt5-quickcontrols2
qt6-5compat
```

### Audio (PipeWire)
```
pipewire
wireplumber
pipewire-audio
pipewire-alsa
pipewire-pulse
sof-firmware
```

### Networking
```
networkmanager
network-manager-applet
openssh
iwd
dhcpcd
```

### Bluetooth
```
bluez
bluez-utils
blueman
```

### Terminal & Shell
```
kitty
foot
zsh
zsh-completions
fzf
lsd
bat
tmux
nano
```

### Desktop Utilities
```
waybar
rofi
swaync
wlogout
swww
cliphist
grim
slurp
swappy
wallust
brightnessctl
playerctl
pamixer
pavucontrol
wl-clipboard
yad
imagemagick
```

### File Manager
```
thunar
thunar-volman
tumbler
ffmpegthumbnailer
thunar-archive-plugin
xarchiver
gvfs
gvfs-mtp
```

### Browsers
```
firefox
chromium
```

### Editors & Dev Tools
```
neovim
npm
github-cli
```

### Media
```
mpv
mpv-mpris
obs-studio
vlc
loupe
yt-dlp
```

### System Utilities
```
btop
cava
fastfetch
nvtop
gnome-system-monitor
inxi
pciutils
usbutils
dmidecode
```

### File Utilities
```
yazi
zoxide
rclone
unzip
wget
curl
jq
bc
xdg-user-dirs
xdg-utils
pacman-contrib
```

### Theming & Appearance
```
kvantum
qt5ct
qt6ct
nwg-look
nwg-displays
papirus-icon-theme
gtk-engine-murrine
```

### Fonts
```
adobe-source-code-pro-fonts
noto-fonts
noto-fonts-emoji
otf-font-awesome
ttf-droid
ttf-fira-code
ttf-jetbrains-mono
ttf-jetbrains-mono-nerd
ttf-victor-mono
```

### Graphics Drivers
```
mesa
nvidia-dkms
nvidia-settings
nvidia-utils
libva
libva-nvidia-driver
```

### Installer Dependencies
```
arch-install-scripts
parted
dosfstools
btrfs-progs
e2fsprogs
gptfdisk
dialog
cryptsetup
lvm2
```

### Additional Utilities
```
qalculate-gtk
mousepad
libspng
python-requests
python-pyquery
sudo
reflector
```

### Firmware
```
linux-firmware-marvell
broadcom-wl
```

### AUR Packages (custom local repo)
```
yay-bin
quickshell
ttf-fantasque-nerd
visual-studio-code-bin
64gram-desktop-bin
vesktop
stacer-bin
localsend-bin
```

---

## Execution Order

| Step | Phase | Task |
|------|-------|------|
| 1 | 1 | Git init + profiledef.sh + packages.x86_64 + pacman.conf |
| 2 | 4 | Boot configs (syslinux, grub, efiboot) |
| 3 | 3 | airootfs/etc/ system configs (users, systemd, hostname, locale) |
| 4 | 3 | airootfs/etc/skel/ dotfiles (copy from references, merge) |
| 5 | 3 | Theme assets (SDDM, Plymouth, GRUB, GTK, icons, cursors) |
| 6 | 3 | NVIDIA auto-detection script |
| 7 | 5 | Custom TUI installer |
| 8 | 3 | Web app PWA entries |
| 9 | 2 | AUR build infrastructure |
| 10 | 6 | build.sh wrapper + QEMU test script |
| 11 | 7 | GitHub Actions CI/CD |
| 12 | — | Documentation + testing instructions |

---

## Estimated ISO Size

| Component | Size |
|-----------|------|
| Base system + kernel | ~500MB |
| Hyprland + desktop packages | ~400MB |
| Browsers (Firefox + Chromium) | ~300MB |
| Full-featured extras (OBS, VLC, VS Code, etc.) | ~500MB |
| Themes + wallpapers + icons | ~100MB |
| NVIDIA drivers | ~200MB |
| AUR packages | ~200MB |
| **Total (compressed squashfs)** | **~2.5-3.5GB** |

---

*Last Updated: 2026-03-08*
