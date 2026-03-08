# HyprFlux ISO

A custom Arch Linux ISO with a fully pre-configured **HyprFlux** Hyprland desktop environment. Boot it, use it live, or install it to disk with the built-in TUI installer.

## Features

- **Pre-configured Hyprland** desktop with Waybar, Rofi, SDDM, Kitty, and 20+ config directories
- **SDDM auto-login** directly into Hyprland (simple-sddm-2 theme)
- **Custom TUI installer** (`hyprflux-install`) for disk installation with LUKS encryption, btrfs, and ext4 support
- **NVIDIA auto-detection** at boot (separate GRUB/Syslinux boot entries)
- **Dual boot support**: UEFI (GRUB with Vimix theme) and Legacy BIOS (Syslinux)
- **Plymouth boot splash** (hyprland-mac-style theme)
- **28 Chromium PWA web apps** (Netflix, YouTube, GitHub, ChatGPT, Claude, etc.)
- **AUR packages pre-built**: yay-bin, VS Code, Vesktop, 64gram, QuickShell, and more
- **Full theming**: GTK themes, cursor themes (Future-black, Bibata), Papirus icons, wallpapers
- **CI/CD**: GitHub Actions builds ISOs automatically on push/tag

## Quick Start

### Download

Grab the latest ISO from [Releases](../../releases), or build it yourself (see below).

### Write to USB

```bash
sudo dd bs=4M if=hyprflux-*.iso of=/dev/sdX status=progress oflag=sync
```

### Boot

- **UEFI**: Select "HyprFlux" from the GRUB menu
- **BIOS**: Select "Boot HyprFlux" from the Syslinux menu
- **NVIDIA GPU**: Choose the "HyprFlux (NVIDIA)" boot entry

### Install to Disk

From the live session:

```bash
sudo hyprflux-install
```

Or click the "Install HyprFlux" desktop shortcut, or run `hyprflux-welcome` for the welcome screen.

## Building

### Prerequisites

- Arch Linux (or an Arch-based system)
- `archiso` package: `sudo pacman -S archiso`
- `base-devel`, `git` for AUR builds

### Build Steps

```bash
# 1. Clone the repository
git clone https://github.com/ahmad9059/Hyprflux-ISO.git
cd Hyprflux-ISO

# 2. Build AUR packages (as non-root)
./aur/build-aur.sh

# 3. Download external assets (Bibata cursor, PWA icons)
./prepare-assets.sh

# 4. Build the ISO (as root)
sudo ./build.sh
```

The ISO will be in `./out/`.

### Build Options

```bash
sudo ./build.sh --skip-aur   # Skip AUR build (use existing repo)
sudo ./build.sh --clean       # Clean work dir before building
FETCH_WALLPAPERS=1 ./prepare-assets.sh  # Download extra wallpapers
```

### Testing with QEMU

```bash
./test-qemu.sh              # UEFI boot (default)
./test-qemu.sh --bios       # Legacy BIOS boot
```

Requires `qemu-desktop` and `edk2-ovmf`.

## Project Structure

```
Hyprflux-ISO/
├── profiledef.sh              # archiso profile definition
├── packages.x86_64            # official repo packages (~150+)
├── pacman.conf                # build-time pacman config
├── build.sh                   # main build script
├── prepare-assets.sh          # download external assets
├── test-qemu.sh               # QEMU test launcher
├── airootfs/                  # root filesystem overlay
│   ├── etc/
│   │   ├── skel/              # pre-baked dotfiles (hypr, waybar, kitty, etc.)
│   │   ├── sddm.conf         # SDDM auto-login config
│   │   └── ...                # system configs
│   └── usr/
│       ├── local/bin/
│       │   ├── hyprflux-install       # TUI disk installer
│       │   ├── hyprflux-welcome       # welcome screen
│       │   └── hyprflux-nvidia-detect # NVIDIA auto-detection
│       └── share/
│           ├── applications/  # .desktop files (installer + 28 PWAs)
│           ├── sddm/themes/  # simple-sddm-2
│           ├── plymouth/     # hyprland-mac-style
│           ├── grub/themes/  # Vimix
│           ├── themes/       # GTK themes
│           ├── icons/        # cursor themes + PWA icons
│           └── wallpapers/   # bundled wallpapers
├── grub/                      # UEFI GRUB configs
├── syslinux/                  # Legacy BIOS Syslinux configs
├── aur/
│   ├── build-aur.sh           # AUR package builder
│   ├── PKGBUILDS/             # tracked PKGBUILDs
│   └── repo/                  # generated local repo (gitignored)
└── .github/workflows/
    └── build-iso.yml          # CI/CD pipeline
```

## AUR Packages

These packages are pre-built and included via a local repo:

| Package | Purpose |
|---------|---------|
| `yay-bin` | AUR helper |
| `quickshell` | Desktop overview shell |
| `ttf-fantasque-nerd` | Nerd font |
| `visual-studio-code-bin` | Code editor |
| `64gram-desktop-bin` | Telegram client |
| `vesktop` | Discord client |
| `stacer-bin` | System optimizer |
| `localsend-bin` | Local file sharing |

## Boot Modes

| Mode | Firmware | Bootloader | Supported |
|------|----------|------------|-----------|
| Legacy BIOS | MBR/CSM | Syslinux | Yes |
| UEFI x64 | GPT/UEFI | GRUB | Yes |
| UEFI Secure Boot | GPT/UEFI | Signed shim | Not yet |

## Credits

- [archiso](https://gitlab.archlinux.org/archlinux/archiso) - Arch Linux ISO builder
- [JaKooLit/Hyprland-Dots](https://github.com/JaKooLit/Hyprland-Dots) - Base dotfiles
- [Hyprland](https://hyprland.org/) - Wayland compositor
- [Vimix GRUB theme](https://github.com/vinceliuice/grub2-themes)

## License

MIT
# HyprFlux-ISO
