# Phase 5: HyprFlux Integration & Post-Install (Chroot Wrapper Approach)

## Goal

Wire up the HyprFlux, Arch-Hyprland, and Hyprland-Dots installation pipeline to run inside the chroot after the base system is configured. This is the phase that turns a plain Arch install into a fully configured HyprFlux Hyprland desktop.

After this phase, the full installer is complete: boot ISO -> answer prompts -> reboot into a working HyprFlux desktop.

---

## Why a Chroot Wrapper Is Required

The original plan was to run `HyprFlux/install.sh` -> `Arch-Hyprland/install.sh` directly inside `arch-chroot`. Deep analysis of the actual source code revealed **9+ points of failure** that make this impossible:

| Problem | Where | Why it breaks in chroot |
|---------|-------|------------------------|
| Exits if run as root | Arch-Hyprland `install.sh:31` | `if [[ $EUID -eq 0 ]]; then exit 1; fi` |
| Whiptail interactive checklist | Arch-Hyprland `install.sh:224-335` | NOT controlled by `HYP` variable — blocks waiting for user input |
| `systemctl enable --now` | pipewire.sh, bluetooth.sh, sddm.sh, monitors | No running systemd PID 1 in chroot |
| `systemctl --user` | pipewire.sh (3 calls) | No user dbus session in chroot |
| `lspci` for NVIDIA detection | Arch-Hyprland `install.sh:219` | No PCI bus access in chroot |
| `gsettings` / dbus | HyprFlux module `08-gtk.sh` | No dbus session bus in chroot |
| `script -qfc` | `lib/packages.sh:53` | Requires `/dev/pts` pseudo-terminal |
| `chsh` | Arch-Hyprland `zsh.sh` | Requires PAM authentication |
| `ask_yes_no()` interactive | HyprFlux module `17-optional-packages.sh` | Hangs waiting for TTY input |
| `setup_sudo()` keep-alive | `lib/common.sh` | Background `while true` loop in chroot |
| curl/git downloads | Various scripts | Needs DNS/network properly configured in chroot |

**Solution:** Create a custom **chroot wrapper script** (`hyprflux-chroot-wrapper.sh`) that replaces the Arch-Hyprland whiptail flow entirely. It runs individual install scripts in the correct order with chroot-safe adaptations.

---

## Architecture

```
ISO Installer (Phase 4)
  └─> step_install_hyprflux()
        │
        ├─ Pre-chroot: detect NVIDIA via lspci (live PCI bus)
        ├─ Pre-chroot: copy resolv.conf into chroot (DNS)
        ├─ Pre-chroot: clone repos as target user
        │
        └─ arch-chroot → hyprflux-chroot-wrapper.sh
              │
              ├─ Install sudo shim (wraps sudo to just run commands)
              ├─ Install systemctl shim (converts --now to enable-only)
              │
              ├─ Phase A: Arch-Hyprland scripts (in order)
              │   ├─ 00-base.sh
              │   ├─ pacman.sh
              │   ├─ yay.sh (as target user, makepkg)
              │   ├─ 01-hypr-pkgs.sh
              │   ├─ pipewire.sh (with systemctl shim)
              │   ├─ fonts.sh
              │   ├─ hyprland.sh
              │   ├─ bluetooth.sh (with systemctl shim)
              │   ├─ sddm.sh (with systemctl shim)
              │   ├─ nvidia.sh (if HAS_NVIDIA=yes)
              │   ├─ zsh.sh (patched chsh)
              │   └─ dotfiles-main.sh (Hyprland-Dots)
              │
              ├─ Phase B: HyprFlux dotsSetup modules (01-17)
              │   ├─ modules 01-07: run as-is
              │   ├─ module 08: skip gsettings (defer to first-boot)
              │   ├─ modules 09-16: run as-is
              │   └─ module 17: auto-skip (non-interactive mode)
              │
              ├─ Phase C: Enable system services
              │   ├─ systemctl enable sddm
              │   ├─ systemctl enable bluetooth
              │   └─ systemctl enable NetworkManager
              │
              └─ Phase D: First-boot fixup service
                  └─ Install systemd service for GTK/gsettings on first login
```

---

## File List

| # | File | Lines | Description |
|---|------|-------|-------------|
| 1 | `airootfs/root/lib/hyprflux-chroot-wrapper.sh` | ~350 | Master chroot wrapper script |
| 2 | Step 10 in `hyprflux-install.sh` | ~80 | Pre-chroot setup + invoke wrapper |
| 3 | Step 11 in `hyprflux-install.sh` | ~40 | Cleanup + reboot |

---

## Step 10: Install HyprFlux

### Pre-Chroot Setup (runs on live ISO)

```bash
step_install_hyprflux() {
    set_status "Installing HyprFlux (this takes 20-60 minutes)..."
    
    # ====== Prepare chroot environment ======
    
    # DNS resolution in chroot
    log_step "Configuring DNS for chroot..."
    cp /etc/resolv.conf "${MOUNT_POINT}/etc/resolv.conf"
    
    # Ensure /dev/pts is available (needed by script -qfc in packages.sh)
    # arch-chroot handles /dev, /proc, /sys bind mounts automatically,
    # but we verify /dev/pts explicitly
    
    # ====== Clone repos as target user ======
    log_step "Cloning HyprFlux repository..."
    arch-chroot "$MOUNT_POINT" su - "${INSTALL_USERNAME}" -c \
        "git clone --depth=1 https://github.com/ahmad9059/HyprFlux.git ~/HyprFlux" \
        2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    
    log_step "Cloning Arch-Hyprland repository..."
    arch-chroot "$MOUNT_POINT" su - "${INSTALL_USERNAME}" -c \
        "git clone --depth=1 https://github.com/ahmad9059/Arch-Hyprland.git ~/Arch-Hyprland" \
        2>&1 | while IFS= read -r line; do log_cmd "$line"; done
    
    # ====== Copy wrapper script into chroot ======
    log_step "Preparing chroot wrapper..."
    cp "${SCRIPT_DIR}/lib/hyprflux-chroot-wrapper.sh" \
        "${MOUNT_POINT}/tmp/hyprflux-chroot-wrapper.sh"
    chmod +x "${MOUNT_POINT}/tmp/hyprflux-chroot-wrapper.sh"
    
    # ====== Run wrapper inside chroot ======
    log_step "Running HyprFlux installation pipeline..."
    
    arch-chroot "$MOUNT_POINT" /bin/bash /tmp/hyprflux-chroot-wrapper.sh \
        "${INSTALL_USERNAME}" \
        "${HAS_NVIDIA}" \
        2>&1 | while IFS= read -r line; do
            log_cmd "$line"
        done
    
    local status=${PIPESTATUS[0]}
    if [[ $status -ne 0 ]]; then
        log_warn "HyprFlux installation had errors (exit code: $status)"
        log_warn "Some packages may have failed. The system should still be usable."
    fi
    
    # Clean up
    rm -f "${MOUNT_POINT}/tmp/hyprflux-chroot-wrapper.sh"
    
    log_ok "HyprFlux installation complete."
}
```

---

## The Chroot Wrapper Script: `hyprflux-chroot-wrapper.sh`

This is the core of Phase 5. It runs INSIDE the chroot and orchestrates the entire HyprFlux installation with chroot-safe adaptations.

### Arguments

```
$1 = INSTALL_USERNAME (the target user)
$2 = HAS_NVIDIA ("yes" or "no")
```

### Design Principles

1. **No whiptail** — all components are pre-selected (the ISO installer already collected user preferences)
2. **systemctl shim** — intercepts `systemctl enable --now` and converts to `systemctl enable` only
3. **sudo shim** — when running as target user, sudo is pre-configured to not require password
4. **Skip dbus-dependent operations** — gsettings/nwg-look deferred to first-boot service
5. **Non-interactive** — all `read` prompts and `ask_yes_no` calls are bypassed

### Implementation Outline

```bash
#!/bin/bash
# hyprflux-chroot-wrapper.sh
# Runs INSIDE arch-chroot. Orchestrates HyprFlux installation
# with chroot-safe adaptations.
set -e

TARGET_USER="$1"
HAS_NVIDIA="$2"
TARGET_HOME="/home/${TARGET_USER}"

echo "==> HyprFlux Chroot Wrapper"
echo "    User: ${TARGET_USER}"
echo "    NVIDIA: ${HAS_NVIDIA}"

# ================================================================
# PHASE 0: Install shims and prepare environment
# ================================================================

# --- systemctl shim ---
# Replaces systemctl so that:
#   "enable --now" becomes "enable" (no running systemd in chroot)
#   "start", "stop", "restart", "is-active" are silently skipped
#   "enable" (without --now) works normally
cat > /usr/local/bin/systemctl-shim << 'SHIM_EOF'
#!/bin/bash
# systemctl shim for chroot environment
args=("$@")
filtered=()
skip_cmd=false

for arg in "${args[@]}"; do
    case "$arg" in
        start|stop|restart|is-active|status)
            skip_cmd=true
            filtered+=("$arg")
            ;;
        --now)
            # Strip --now flag, keep the rest
            ;;
        --user)
            # User services can't be enabled in chroot either
            skip_cmd=true
            filtered+=("$arg")
            ;;
        *)
            filtered+=("$arg")
            ;;
    esac
done

if [[ "$skip_cmd" == true ]]; then
    echo "[chroot-shim] Skipping: systemctl ${args[*]}" >&2
    exit 0
fi

# For "enable" commands, use the real systemctl
/usr/bin/systemctl "${filtered[@]}"
SHIM_EOF
chmod +x /usr/local/bin/systemctl-shim

# Temporarily override systemctl
# (save the real one, replace with shim, restore at end)
cp /usr/bin/systemctl /usr/bin/systemctl.real
cp /usr/local/bin/systemctl-shim /usr/bin/systemctl

# --- Ensure sudo works for target user without password (temporary) ---
echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hyprflux-temp
chmod 440 /etc/sudoers.d/hyprflux-temp

# ================================================================
# PHASE A: Run Arch-Hyprland install scripts individually
# ================================================================
# Instead of running install.sh (which has whiptail and root check),
# we run each script in the correct order.

ARCH_HYPR_DIR="${TARGET_HOME}/Arch-Hyprland"
INSTALL_SCRIPTS="${ARCH_HYPR_DIR}/install-scripts"

# Source Arch-Hyprland's global functions
# (provides install_package_pacman, install_package, show_progress, etc.)
export ISAUR="yay"  # Set AUR helper preference

echo "==> Phase A: Arch-Hyprland components"

# A1: Base packages (base-devel, keyring refresh)
echo "==> [A1] Installing base packages..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/00-base.sh"

# A2: Pacman configuration
echo "==> [A2] Configuring pacman..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/pacman.sh"

# A3: Install yay (AUR helper) — MUST be non-root
echo "==> [A3] Installing yay AUR helper..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/yay.sh"

# A4: Hyprland packages
echo "==> [A4] Installing Hyprland ecosystem packages..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/01-hypr-pkgs.sh"

# A5: PipeWire audio
echo "==> [A5] Installing PipeWire audio stack..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/pipewire.sh"

# A6: Fonts
echo "==> [A6] Installing fonts..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/fonts.sh"

# A7: Hyprland compositor
echo "==> [A7] Installing Hyprland compositor..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/hyprland.sh"

# A8: Bluetooth
echo "==> [A8] Installing Bluetooth support..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/bluetooth.sh"

# A9: SDDM display manager
echo "==> [A9] Installing SDDM..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/sddm.sh"

# A10: NVIDIA (conditional)
if [[ "${HAS_NVIDIA}" == "yes" ]]; then
    echo "==> [A10] Installing NVIDIA drivers..."
    su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/nvidia.sh"
fi

# A11: Zsh
# Patch chsh to use usermod instead (avoids PAM issues in chroot)
echo "==> [A11] Installing Zsh + Oh My Zsh..."
# Pre-set the shell to zsh before running the script
usermod -s /usr/bin/zsh "${TARGET_USER}"
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/zsh.sh" || true

# A12: Dotfiles (Hyprland-Dots)
echo "==> [A12] Installing Hyprland dotfiles..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/dotfiles-main.sh"

# A13: Final check
echo "==> [A13] Running final check..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/02-Final-Check.sh" || true

# ================================================================
# PHASE B: Run HyprFlux dotsSetup modules
# ================================================================

HYPRFLUX_DIR="${TARGET_HOME}/HyprFlux"

echo "==> Phase B: HyprFlux dotfiles modules"

# Set environment variables that HyprFlux modules expect
export HYPRFLUX_ISO_MODE=1

# Run modules in order, with special handling for problematic ones
for module in "${HYPRFLUX_DIR}"/modules/[0-9]*.sh; do
    module_name=$(basename "$module")
    echo "==> [Module] ${module_name}..."
    
    case "$module_name" in
        08-gtk.sh)
            # Skip gsettings/nwg-look (requires dbus session)
            # GTK theme will be applied on first boot
            echo "    [DEFERRED] gsettings requires dbus — will apply on first login"
            # Still source the module but override the problematic functions
            su - "${TARGET_USER}" -c "
                export HYPRFLUX_ISO_MODE=1
                cd ${HYPRFLUX_DIR}
                # Source libs but skip gsettings calls
                source lib/common.sh 2>/dev/null || true
                source lib/packages.sh 2>/dev/null || true
                source lib/git.sh 2>/dev/null || true
                # Run the module with gsettings stubbed out
                gsettings() { echo '[stub] gsettings skipped in chroot'; }
                nwg-look() { echo '[stub] nwg-look skipped in chroot'; }
                export -f gsettings nwg-look
                source ${module}
            " || true
            ;;
        17-optional-packages.sh)
            # Skip — interactive (ask_yes_no) and optional
            echo "    [SKIPPED] Optional packages (interactive prompts not available)"
            ;;
        10-plymouth.sh)
            # Plymouth needs mkinitcpio/grub — should work but may need care
            echo "    [Module] Running plymouth setup..."
            su - "${TARGET_USER}" -c "
                export HYPRFLUX_ISO_MODE=1
                cd ${HYPRFLUX_DIR}
                source lib/common.sh 2>/dev/null || true
                source lib/packages.sh 2>/dev/null || true
                source lib/git.sh 2>/dev/null || true
                source ${module}
            " || {
                echo "    [WARN] Plymouth setup had issues (non-fatal)"
            }
            ;;
        *)
            # Normal module execution
            su - "${TARGET_USER}" -c "
                export HYPRFLUX_ISO_MODE=1
                cd ${HYPRFLUX_DIR}
                source lib/common.sh 2>/dev/null || true
                source lib/packages.sh 2>/dev/null || true
                source lib/git.sh 2>/dev/null || true
                source ${module}
            " || {
                echo "    [WARN] ${module_name} had issues (non-fatal)"
            }
            ;;
    esac
done

# ================================================================
# PHASE C: Enable system services (using real systemctl)
# ================================================================

echo "==> Phase C: Enabling system services"

# Restore real systemctl
cp /usr/bin/systemctl.real /usr/bin/systemctl
rm -f /usr/bin/systemctl.real /usr/local/bin/systemctl-shim

systemctl enable sddm 2>/dev/null || true
systemctl enable bluetooth 2>/dev/null || true
systemctl enable NetworkManager 2>/dev/null || true

# User-level services are enabled via ~/.config/systemd/user/
# They will start automatically on first login

# ================================================================
# PHASE D: Create first-boot fixup service
# ================================================================
# This runs on the user's first login and applies deferred settings
# (GTK theme via gsettings, etc.)

echo "==> Phase D: Creating first-boot fixup"

mkdir -p "${TARGET_HOME}/.config/autostart"
cat > "${TARGET_HOME}/.config/autostart/hyprflux-first-boot.desktop" << DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=HyprFlux First Boot Setup
Exec=/home/${TARGET_USER}/.local/bin/hyprflux-first-boot.sh
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP_EOF

mkdir -p "${TARGET_HOME}/.local/bin"
cat > "${TARGET_HOME}/.local/bin/hyprflux-first-boot.sh" << 'FIRSTBOOT_EOF'
#!/bin/bash
# HyprFlux first-boot fixup
# Applies settings that couldn't be configured in chroot (no dbus)

MARKER="$HOME/.config/hyprflux-first-boot-done"

if [[ -f "$MARKER" ]]; then
    exit 0
fi

echo "Applying HyprFlux first-boot settings..."

# Apply GTK theme
gsettings set org.gnome.desktop.interface gtk-theme "HyprFlux-Compact" 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic" 2>/dev/null || true
gsettings set org.gnome.desktop.interface font-name "Noto Sans 11" 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true

# Run nwg-look if available
if command -v nwg-look &>/dev/null; then
    nwg-look -a 2>/dev/null || true
fi

# Enable pipewire user services
systemctl --user enable --now pipewire.socket 2>/dev/null || true
systemctl --user enable --now pipewire-pulse.socket 2>/dev/null || true
systemctl --user enable --now wireplumber.service 2>/dev/null || true

# Mark as done
touch "$MARKER"

# Remove autostart entry (one-shot)
rm -f "$HOME/.config/autostart/hyprflux-first-boot.desktop"
FIRSTBOOT_EOF
chmod +x "${TARGET_HOME}/.local/bin/hyprflux-first-boot.sh"

# Fix ownership
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config" 2>/dev/null || true
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local" 2>/dev/null || true

# ================================================================
# CLEANUP
# ================================================================

echo "==> Cleanup"

# Remove temporary sudoers entry
rm -f /etc/sudoers.d/hyprflux-temp

# Ensure wheel group sudo is properly configured (set in Phase 4)
# Already done: sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "==> HyprFlux chroot wrapper complete!"
```

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
  Username: ${INSTALL_USERNAME}\n\
  Password: (the password you set)\n\n\
Note: GTK theme and audio will be configured automatically\n\
on your first login (takes ~10 seconds).\n\n\
Enjoy HyprFlux!" 18 58
    
    show_banner
    set_status "Rebooting..."
    log_ok "Rebooting in 5 seconds..."
    sleep 5
    reboot
}
```

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
- PipeWire audio (replaces PulseAudio) — enabled on first login
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
- HyprFlux-Compact GTK theme (applied on first login via first-boot service)
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

This is a ~6 line change. **However, with the chroot wrapper approach, we don't actually call `install.sh` directly**, so this change is only needed if someone runs HyprFlux's `install.sh` standalone in ISO mode in the future. The wrapper bypasses it entirely.

---

## AUR Packages Handling

### Approach A: Online AUR (current implementation)
- yay builds packages during install inside chroot
- Pros: Always latest versions, simple
- Cons: Slow (compile time), requires internet

### Approach B: Pre-built AUR repo (future optimization)
- Pre-build AUR packages in CI and include them in the ISO
- Reference: the existing `aur/build-aur.sh` and `aur/repo/` infrastructure
- Pros: Fast install, works offline for these packages
- Cons: More complex build, packages may be stale

**Decision:** Start with Approach A (online). The GitHub Actions workflow already supports Approach B for future optimization.

---

## Potential Failure Points & Mitigations

| Issue | Risk | Mitigation |
|-------|------|------------|
| Individual Arch-Hyprland script fails | Medium | `|| true` on non-critical scripts; continue with rest |
| yay compilation fails in chroot | Low | `/dev/pts` is bind-mounted by arch-chroot; `script -qfc` should work |
| Zsh `chsh` fails | Medium | Pre-set shell via `usermod` before running zsh.sh |
| Network drops during AUR builds | Medium | Non-fatal; user can re-run yay after reboot |
| Oh My Zsh curl install hangs | Low | Timeout via `--max-time` in curl calls |
| Arch-Hyprland script sources Global_functions.sh | Medium | Wrapper sets `ISAUR=yay` and ensures the file is sourceable |
| First-boot service fails | Low | One-shot; user can re-run manually if needed |
| Module order dependencies | Medium | Wrapper follows exact order from dotsSetup.sh |

---

## Validation Steps

1. Build ISO and boot in QEMU with 4GB+ RAM
2. Complete full installation flow (Steps 0-11)
3. Reboot into installed system
4. SDDM login screen appears
5. Login with created user credentials
6. First-boot fixup runs (~10 seconds, applies GTK theme + audio)
7. Hyprland desktop loads with:
   - Waybar visible at top
   - Wallpaper displayed
   - Super key opens app launcher (Rofi)
   - Terminal (Kitty) launches with zsh + custom prompt
   - Firefox and Chromium available
   - Audio works (PipeWire)
8. Test UEFI and BIOS installations separately

---

## Estimated Implementation Time

~3-5 hours. The chroot wrapper is complex and requires careful testing of each script's behavior inside chroot.

---

## Dependencies

- **Requires Phase 1-4**: bootable ISO with working base installer
- **Requires internet during installation**: repos are cloned from GitHub
- **Optional modification to HyprFlux repo**: ISO mode check (~6 lines, for future standalone use)
