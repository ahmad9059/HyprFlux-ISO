# HyprFlux ISO

## Goal

Build a custom Arch Linux ISO for **HyprFlux** -- a Hyprland desktop distribution. The ISO boots into a TUI installer (styled like Omarchy with a large ASCII logo at top and scrolling installation output below) that:
1. Installs base Arch Linux
2. Runs the HyprFlux + Arch-Hyprland + Hyprland-Dots installation pipeline inside chroot
3. Produces a fully configured Hyprland desktop on reboot

## Requirements

- **Both UEFI and Legacy BIOS boot support**
- **Online install**: repos are cloned from GitHub at install time (no baking packages into ISO)
- **TUI design**: Large centered HyprFlux ASCII art logo at top of screen, scrolling installation output below (Omarchy-style)
- Two partition options: **Automatic** (wipe entire disk) and **Manual** (user partitions with EFI/Swap/Root)
- archiso configuration: timezone search, keyboard layout search, locale selection, hostname, user creation
- **Chroot Wrapper approach** (Option A): custom wrapper replaces Arch-Hyprland's whiptail flow, runs individual scripts with chroot-safe shims

## Architecture

```
ISO Boot Process:
  UEFI  -> systemd-boot -> kernel + initramfs -> live env
  BIOS  -> syslinux     -> kernel + initramfs -> live env

Live Environment:
  auto-login root (tty1) -> .zlogin -> hyprflux-install.sh

Installation Pipeline:
  Step 0:  Network setup (NetworkManager)
  Step 1:  Welcome prompt
  Steps 2-6: Config (timezone, locale, keyboard, hostname, user)
  Step 7:  Disk partitioning (auto/manual)
  Step 8:  pacstrap base system
  Step 9:  chroot system config (locale, GRUB, users)
  Step 10: HyprFlux integration (chroot wrapper)
  Step 11: Cleanup + reboot

Chroot Wrapper (Step 10):
  Phase A: Arch-Hyprland scripts (individually, with shims)
  Phase B: HyprFlux dotsSetup modules (01-17)
  Phase C: Enable system services (sddm, bluetooth, NetworkManager)
  Phase D: First-boot fixup service (GTK/gsettings, pipewire)
```

## Project Structure

```
hyprflux-iso/
+-- build.sh                            # Master build script (~90 lines)
+-- profiledef.sh                       # archiso profile definition
+-- packages.x86_64                     # Live env packages
+-- pacman.conf                         # Build-time pacman config
+-- airootfs/
|   +-- etc/
|   |   +-- hostname, locale.conf, locale.gen
|   |   +-- passwd (root shell = zsh), shadow
|   |   +-- motd
|   |   +-- mkinitcpio.conf.d/archiso.conf
|   |   +-- mkinitcpio.d/linux.preset
|   |   +-- systemd/
|   |       +-- journal.conf.d/volatile-storage.conf
|   |       +-- logind.conf.d/do-not-suspend.conf
|   |       +-- system/
|   |           +-- pacman-init.service
|   |           +-- getty@tty1.service.d/autologin.conf
|   +-- root/
|       +-- .zlogin                     # Auto-launches installer on tty1
|       +-- hyprflux-install.sh         # Main installer (~500 lines)
|       +-- lib/
|           +-- tui.sh                  # TUI framework (banner, colors, dialogs)
|           +-- common.sh               # Shared utilities
|           +-- hyprflux-chroot-wrapper.sh  # Chroot integration (~450 lines)
+-- efiboot/loader/                     # systemd-boot entries (UEFI)
+-- grub/grub.cfg                       # GRUB fallback (UEFI)
+-- syslinux/                           # Syslinux configs (BIOS)
+-- plans/                              # Phase plans (6 files)
+-- references/                         # Read-only reference repos (NOT tracked in git)
|   +-- HyprFlux/                       # HyprFlux dotfiles repo
|   +-- Arch-Hyprland/                  # JaKooLit's installer
|   +-- Hyprland-Dots/                  # JaKooLit's dotfiles
+-- test-qemu.sh                        # QEMU test launcher
+-- .github/workflows/build-iso.yml     # CI/CD
```

## Phase Plans

All plans are in `plans/` at repo root. There are 6 phases:

1. **Phase 1** (`plans/phase-1-archiso-profile.md`): archiso profile, build script, packages, systemd units
2. **Phase 2** (`plans/phase-2-boot-configuration.md`): systemd-boot, syslinux, GRUB boot configs
3. **Phase 3** (`plans/phase-3-tui-framework.md`): TUI framework, ASCII banner, dialog wrappers, auto-launch
4. **Phase 4** (`plans/phase-4-installer-logic.md`): Network, config prompts, disk partitioning, pacstrap, chroot config
5. **Phase 5** (`plans/phase-5-hyprflux-integration.md`): Chroot wrapper, shims, Arch-Hyprland scripts, HyprFlux modules, first-boot service
6. **Phase 6** (`plans/phase-6-cicd-testing.md`): GitHub Actions CI/CD, testing checklist, release process

**IMPORTANT**: Always read the relevant plan file(s) before implementing or modifying any phase. Plans contain exact specifications, line-number references to upstream repos, and critical notes about chroot-safety issues.

## Key Technical Decisions

- **install_dir = "hyprflux"** (not default "arch") -- requires `archisobasedir=%INSTALL_DIR%` on all boot cmdlines
- **NetworkManager only** -- no systemd-networkd (needed for nmcli/nmtui in installer)
- **systemctl shim** in chroot: strips `--now`, skips runtime verbs, attempts `--user enable`
- **chsh shim** in chroot: no-op script (shell pre-set via `usermod`)
- **gsettings/nwg-look shims** in chroot: actual scripts in `/usr/local/bin/` (not function exports, which don't survive `su -`)
- **NVIDIA detection** happens BEFORE chroot (needs live PCI bus, `lspci`)
- **First-boot service** handles: GTK gsettings, nwg-look, pipewire user services
- **Module config variables** from dotsSetup.sh are written to a shared env file sourced per module

## Reference Repos (in references/, read-only)

- **HyprFlux** (`references/HyprFlux/`): `install.sh` (123 lines), `dotsSetup.sh` (127 lines), `lib/` (common.sh, packages.sh, git.sh), `modules/` (01-17)
- **Arch-Hyprland** (`references/Arch-Hyprland/`): `install.sh` (515 lines), `install-scripts/` (00-base.sh, pacman.sh, yay.sh, etc.), `install-scripts/Global_functions.sh`
- **Hyprland-Dots** (`references/Hyprland-Dots/`): JaKooLit's dotfiles (cloned by dotfiles-main.sh during install)

## Chroot Wrapper Shims

The chroot wrapper installs temporary shims to handle operations that fail in chroot:

| Shim | Location | Purpose |
|------|----------|---------|
| systemctl | `/usr/bin/systemctl` (replaces real) | Strips --now, skips runtime verbs |
| chsh | `/usr/local/bin/chsh` | No-op (shell set via usermod) |
| gsettings | `/usr/local/bin/gsettings` | No-op (deferred to first-boot) |
| nwg-look | `/usr/local/bin/nwg-look` | No-op (no display in chroot) |

All shims are cleaned up at the end of the wrapper.

## Current Status

- All 6 phase plans are written, reviewed, and corrected (18 issues found and fixed)
- Expert review complete (3 deep-dive research tasks on archiso releng, Arch-Hyprland scripts, HyprFlux modules)
- **Implementation has NOT started** -- plans are ready, no code exists yet beyond pre-existing test-qemu.sh and CI workflow
- Next step: Begin Phase 1 implementation

## Build & Test

```bash
# Build the ISO (requires archiso package, must run as root)
sudo bash build.sh

# Test in QEMU
./test-qemu.sh --uefi    # UEFI boot test
./test-qemu.sh --bios    # Legacy BIOS boot test
```

## Conventions

- Bash scripts use `set -euo pipefail`
- All installer variables prefixed with `INSTALL_` (e.g., `INSTALL_TIMEZONE`, `INSTALL_USERNAME`)
- archiso template variables: `%ARCHISO_UUID%`, `%INSTALL_DIR%`, `%ARCH%` (replaced by mkarchiso at build time)
- Chroot wrapper scripts use `|| true` on non-critical operations for resilience
- TUI colors: green logo, yellow status, cyan arrows, red errors
