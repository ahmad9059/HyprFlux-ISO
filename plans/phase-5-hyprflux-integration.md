# Phase 5: HyprFlux Integration & Post-Install

## Goal

Wire up the HyprFlux, Arch-Hyprland, and Hyprland-Dots installation pipeline to run inside the chroot after the base system is configured. This is the phase that turns a plain Arch install into a fully configured HyprFlux Hyprland desktop.

After this phase, the full installer is complete: boot ISO -> answer prompts -> reboot into a working HyprFlux desktop.

---

## Overview

The installation chain (from your diagram) is:

```
archiso (base install)
  └─> HyprFlux install.sh
        ├─> Arch-Hyprland install.sh
        │     ├─> pacman.sh (configure pacman)
        │     ├─> yay.sh (install AUR helper)
        │     ├─> 00-base.sh (base-devel, keyring)
        │     ├─> hyprland.sh (Hyprland compositor)
        │     ├─> 01-hypr-pkgs.sh (ecosystem packages)
        │     ├─> fonts.sh, bluetooth.sh, sddm.sh, pipewire.sh ...
        │     ├─> nvidia.sh (if NVIDIA GPU detected)
        │     └─> dotfiles-main.sh (clone Hyprland-Dots + copy.sh)
        │
        └─> dotsSetup.sh (HyprFlux modules 01-17)
              ├─> 01-backup.sh, 02-dotfiles.sh, 03-packages.sh ...
              ├─> 07-sddm.sh, 08-gtk.sh, 09-grub.sh, 10-plymouth.sh ...
              └─> 13-wallpapers.sh, 14-webapps.sh, 16-bibata.sh ...
```

---

## Step 10: Install HyprFlux (in chroot, as target user)

### Strategy

We run the existing `install.sh` from the HyprFlux repo inside the chroot. This script already handles cloning Arch-Hyprland, running all its install scripts, then running all HyprFlux dotfiles modules.

**Key challenges:**
1. AUR helper (yay) cannot run as root -- must run as the created user
2. Some scripts are interactive (read prompts) -- need to be suppressed
3. The reboot prompt at the end must be skipped (ISO mode)
4. The chroot environment has limited capabilities (no systemd running)

### Implementation

```bash
step_install_hyprflux() {
    set_status "Installing HyprFlux (this takes 20-60 minutes)..."
    
    # ====== Pre-clone repos into chroot ======
    # Clone as the target user so paths match what install.sh expects
    log_step "Cloning HyprFlux repository..."
    arch-chroot "$MOUNT_POINT" su - "${USERNAME}" -c \
        "git clone --depth=1 https://github.com/ahmad9059/HyprFlux.git ~/HyprFlux" \
        2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    
    log_step "Cloning Arch-Hyprland repository..."
    arch-chroot "$MOUNT_POINT" su - "${USERNAME}" -c \
        "git clone --depth=1 https://github.com/ahmad9059/Arch-Hyprland.git ~/Arch-Hyprland" \
        2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    
    # ====== Patch Arch-Hyprland for non-interactive mode ======
    # The install.sh in Arch-Hyprland has `read HYP` prompts that block.
    # HyprFlux's install.sh already patches this with:
    #   sed -i '/^[[:space:]]*read HYP$/c\HYP="n"' install.sh
    # So we don't need to do it again -- HyprFlux handles it.
    
    # ====== Run HyprFlux install.sh ======
    # HYPRFLUX_ISO_MODE=1 tells install.sh to skip the reboot prompt
    log_step "Running HyprFlux installation pipeline..."
    
    arch-chroot "$MOUNT_POINT" su - "${USERNAME}" -c "
        export HYPRFLUX_ISO_MODE=1
        cd ~/HyprFlux
        bash install.sh
    " 2>&1 | while IFS= read -r line; do
        log_cmd "$line"
    done
    
    local status=${PIPESTATUS[0]}
    if [[ $status -ne 0 ]]; then
        log_warn "HyprFlux installation had errors (exit code: $status)"
        log_warn "Some packages may have failed to install. The system should still be usable."
        # Don't die -- partial installs are usually recoverable
    fi
    
    # ====== Post-install service enables ======
    # Some services need to be enabled at the system level
    log_step "Enabling system services..."
    
    arch-chroot "$MOUNT_POINT" bash -c "
        systemctl enable sddm 2>/dev/null || true
        systemctl enable bluetooth 2>/dev/null || true
        systemctl enable NetworkManager 2>/dev/null || true
    " 2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    
    # Enable user-level services (pipewire, etc.)
    # These are enabled by the Arch-Hyprland scripts during install,
    # but we verify them here
    log_step "Verifying user services..."
    arch-chroot "$MOUNT_POINT" su - "${USERNAME}" -c "
        systemctl --user enable pipewire.socket 2>/dev/null || true
        systemctl --user enable pipewire-pulse.socket 2>/dev/null || true
        systemctl --user enable wireplumber.service 2>/dev/null || true
    " 2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    
    log_ok "HyprFlux installation complete."
}
```

---

## Modification to HyprFlux install.sh

One small change is needed in the HyprFlux repo's `install.sh` to support ISO mode. Wrap the reboot prompt:

**File:** `references/HyprFlux/install.sh` (lines 117-123)

**Before:**
```bash
if ask_yes_no "Do you want to reboot now?"; then
  log_ok "Rebooting..."
  sudo reboot
else
  log_ok "You chose NOT to reboot. Please reboot later."
fi
```

**After:**
```bash
if [[ -z "${HYPRFLUX_ISO_MODE:-}" ]]; then
  if ask_yes_no "Do you want to reboot now?"; then
    log_ok "Rebooting..."
    sudo reboot
  else
    log_ok "You chose NOT to reboot. Please reboot later."
  fi
else
  log_ok "HyprFlux setup complete (ISO mode -- reboot handled by installer)."
fi
```

This is a ~6 line change. When `HYPRFLUX_ISO_MODE=1` is exported (which our installer does), the reboot prompt is skipped.

---

## NVIDIA GPU Detection

The Arch-Hyprland `nvidia.sh` script handles NVIDIA driver installation. In the ISO installer, we should detect NVIDIA GPUs proactively and inform the user:

```bash
detect_nvidia() {
    if lspci | grep -i nvidia &>/dev/null; then
        log_step "NVIDIA GPU detected. Proprietary drivers will be installed."
        return 0
    fi
    return 1
}
```

The existing Arch-Hyprland scripts handle NVIDIA installation when prompted. In auto mode, we set `HYP="n"` which may skip NVIDIA. We should investigate whether the installer needs to force NVIDIA installation when a GPU is detected.

**Action item for implementation:** Read Arch-Hyprland's main `install.sh` to understand how `HYP` variable controls NVIDIA script execution. May need to patch this differently.

---

## Step 11: Cleanup & Reboot

```bash
step_cleanup_reboot() {
    set_status "Installation Complete!"
    
    # Unmount everything
    log_step "Unmounting partitions..."
    
    # Sync filesystem
    sync
    
    # Unmount in reverse order
    umount -R "$MOUNT_POINT" 2>/dev/null || true
    swapoff --all 2>/dev/null || true
    
    log_ok "Partitions unmounted."
    
    # Final message
    dialog --clear --title "HyprFlux Installation Complete!" \
        --msgbox "\
Installation is complete!\n\n\
Please:\n\
  1. Remove the USB drive / ISO\n\
  2. Press OK to reboot\n\n\
After reboot, you'll be greeted by the SDDM login screen.\n\
Log in with:\n\
  Username: ${USERNAME}\n\
  Password: (the password you set)\n\n\
Enjoy HyprFlux!" 16 55
    
    show_banner
    set_status "Rebooting..."
    log_ok "Rebooting in 5 seconds..."
    sleep 5
    reboot
}
```

---

## Complete Installer Flow (Steps 0-11)

```bash
# In hyprflux-install.sh, after sourcing libs:

setup_network          # Step 0: Internet
step_welcome           # Step 1: Confirm
step_timezone          # Step 2: Timezone
step_locale            # Step 3: Locale
step_keyboard          # Step 4: Keyboard
step_hostname          # Step 5: Hostname
step_user              # Step 6: User + Password

mkdir -p "$MOUNT_POINT"
step_disk              # Step 7: Partition + Format + Mount
step_base_install      # Step 8: pacstrap
step_configure_system  # Step 9: chroot config (locale, GRUB, users)
step_install_hyprflux  # Step 10: Clone + run HyprFlux pipeline
step_cleanup_reboot    # Step 11: Unmount + reboot
```

---

## Potential Issues & Mitigations

| Issue | Risk | Mitigation |
|-------|------|------------|
| `yay` inside chroot | Can't run as root | `su - $USERNAME` before running install.sh |
| No systemd in chroot | User services won't start | Enable-only (no `--now`); they start on real boot |
| Arch-Hyprland interactive prompts | Blocks automation | HyprFlux's `sed` patches `read HYP` to `HYP="n"` |
| NVIDIA detection | May install wrong drivers | Arch-Hyprland's nvidia.sh handles detection |
| Network drops mid-install | Partial package install | `set -e` not used for this step; warn and continue |
| Long install time (30-60 min) | User thinks it's frozen | Live output scrolling shows activity |
| Wallpaper repo clone (large) | Slow on bad internet | Optional; can be skipped |
| AUR package compilation | Takes long, may fail | Pre-built packages could be cached (future optimization) |
| Oh My Zsh installer | Needs internet | Cloned during Arch-Hyprland's zsh.sh |

---

## What Gets Installed (Summary)

By the end of Phase 5, the target system has:

### Desktop Environment
- Hyprland compositor + hypridle + hyprlock
- Waybar (status bar) with custom themes
- Rofi (app launcher)
- SDDM (display manager) with custom theme
- SwayNC (notifications)
- swww (wallpaper manager)
- QuickShell or AGS (desktop overview)

### System Stack
- PipeWire audio (replaces PulseAudio)
- Bluetooth (bluez + blueman)
- NetworkManager
- GRUB with Vimix theme
- Plymouth boot splash (custom Hyprland theme)

### Applications
- Kitty + Foot terminals
- Firefox + Chromium
- Thunar file manager
- Neovim (with custom config + plugins)
- 28 Chromium PWA web apps
- Various CLI tools (btop, fastfetch, yazi, etc.)

### Theming
- HyprFlux-Compact GTK theme
- Papirus-Dark icons
- Bibata-Modern-Classic cursor
- Custom wallpapers
- Catppuccin Mocha Waybar style

### Shell
- Zsh with Oh My Zsh
- zsh-autosuggestions + zsh-syntax-highlighting
- Tmux with TPM + tmuxifier
- Custom .zshrc and .tmux.conf

---

## AUR Packages Handling

The Arch-Hyprland scripts install `yay` as the AUR helper and use it for packages like `wallust`, `wlogout`, etc. Since the existing GitHub Actions workflow (`build-iso.yml`) already has AUR package pre-building infrastructure, we have two approaches:

### Approach A: Online AUR (current plan)
- Let yay build packages during install
- Pros: Always latest versions, simple
- Cons: Slow (compile time), requires internet

### Approach B: Pre-built AUR repo (future optimization)
- Pre-build AUR packages in CI and include them in the ISO
- Reference: the existing `aur/build-aur.sh` and `aur/repo/` infrastructure
- Pros: Fast install, works offline for these packages
- Cons: More complex build, packages may be stale

**Decision:** Start with Approach A (online). The GitHub Actions workflow already supports Approach B for future optimization.

---

## Validation Steps

1. Build ISO and boot in QEMU with 4GB+ RAM
2. Complete full installation flow (Steps 0-11)
3. Reboot into installed system
4. SDDM login screen appears
5. Login with created user credentials
6. Hyprland desktop loads with:
   - Waybar visible at top
   - Wallpaper displayed
   - Super key opens app launcher (Rofi)
   - Terminal (Kitty) launches with zsh + custom prompt
   - Firefox and Chromium available
7. Test UEFI and BIOS installations separately

---

## Estimated Implementation Time

~2-3 hours. Most complexity is in the chroot integration and error handling.

---

## Dependencies

- **Requires Phase 1-4**: bootable ISO with working base installer
- **Requires internet during installation**: repos are cloned from GitHub
- **Optional modification to HyprFlux repo**: ISO mode check (~6 lines)
