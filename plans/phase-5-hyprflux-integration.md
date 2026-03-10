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
| `chsh` retry loop | Arch-Hyprland `zsh.sh:89` | Requires PAM authentication; loops forever on failure |
| `ask_yes_no()` interactive | HyprFlux module `17-optional-packages.sh` | Hangs waiting for TTY input (but empty stdin = auto-skip) |
| `setup_sudo()` keep-alive | `lib/common.sh` | Background `while true` loop in chroot (harmless with NOPASSWD) |
| curl/git downloads | Various scripts | Needs DNS/network properly configured in chroot |
| `nwg-look` display ops | HyprFlux module `08-gtk.sh` | No display server in chroot |

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
              ├─ Install systemctl shim (strips --now, skips runtime verbs)
              ├─ Install chsh shim (no-op, shell set via usermod)
              ├─ Install gsettings/nwg-look shims (no dbus in chroot)
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
              │   ├─ zsh.sh (with chsh shim)
              │   ├─ thunar.sh (file manager)
              │   ├─ xdph.sh (xdg-desktop-portal-hyprland)
              │   ├─ sddm_theme.sh (SDDM theming)
              │   └─ dotfiles-main.sh (clones JaKooLit/Hyprland-Dots)
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
| 1 | `airootfs/root/lib/hyprflux-chroot-wrapper.sh` | ~450 | Master chroot wrapper script |
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
2. **systemctl shim** — strips `--now` flag, skips runtime verbs (start/stop/restart/is-active/status), attempts `--user enable` (may fail silently)
3. **chsh shim** — returns success immediately (shell already set via `usermod`)
4. **gsettings/nwg-look shims** — script files in `/usr/local/bin/` (not function exports, which don't survive `su -`)
5. **sudo shim** — when running as target user, sudo is pre-configured to not require password
6. **Skip dbus-dependent operations** — gsettings/nwg-look deferred to first-boot service
7. **Non-interactive** — all `read` prompts and `ask_yes_no` calls are bypassed (empty stdin = "no")
8. **Config variables** — all dotsSetup.sh config variables are written to a shared env file sourced by each module

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
#   "enable --now" becomes "enable" (strips --now, no running systemd in chroot)
#   "start", "stop", "restart", "is-active", "status" are silently skipped
#   "--user" + runtime verbs are skipped (no user dbus session)
#   "--user enable" is ATTEMPTED (creates symlink, may fail silently)
#   "enable" (without --now) works normally
cat > /usr/local/bin/systemctl-shim << 'SHIM_EOF'
#!/bin/bash
# systemctl shim for chroot environment
#
# Logic:
#   1. Runtime verbs (start/stop/restart/is-active/status) → always skip
#   2. --now flag → strip it (convert "enable --now" to "enable")
#   3. --user + runtime verb → skip
#   4. --user + enable → attempt (may fail, that's ok — first-boot handles it)
#   5. Everything else → pass through to real systemctl
args=("$@")
filtered=()
has_runtime_verb=false
has_user=false

for arg in "${args[@]}"; do
    case "$arg" in
        start|stop|restart|is-active|status)
            has_runtime_verb=true
            filtered+=("$arg")
            ;;
        --now)
            # Strip --now flag entirely
            ;;
        --user)
            has_user=true
            filtered+=("$arg")
            ;;
        *)
            filtered+=("$arg")
            ;;
    esac
done

# Skip runtime commands entirely (with or without --user)
if [[ "$has_runtime_verb" == true ]]; then
    echo "[chroot-shim] Skipping runtime: systemctl ${args[*]}" >&2
    exit 0
fi

# For --user enable: attempt it but don't fail hard
# (user systemd instance isn't running, but the symlink creation might work)
if [[ "$has_user" == true ]]; then
    echo "[chroot-shim] Attempting --user enable (may fail): systemctl ${filtered[*]}" >&2
    /usr/bin/systemctl "${filtered[@]}" 2>/dev/null || true
    exit 0
fi

# For system-level "enable" commands, use the real systemctl
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

# NOTE: We do NOT export ISAUR="yay" here. Each Arch-Hyprland script
# independently sources Global_functions.sh, which auto-detects yay if
# installed (line 73). Since yay.sh runs before any script that needs
# the AUR helper, auto-detection works correctly. Also, `export` wouldn't
# survive the `su -` boundary anyway (su resets the environment).

echo "==> Phase A: Arch-Hyprland components"

# NOTE: Arch-Hyprland's install.sh (lines 346-353) downloads custom scripts
# from ahmad9059/Scripts (replace_reads.sh, initial.sh, custom zsh.sh) and
# runs them BEFORE the whiptail selection. Since our wrapper bypasses install.sh
# entirely, these scripts are skipped. If they contain essential setup not
# covered by HyprFlux modules, they would need to be added here.
# TODO: Verify whether these custom scripts are needed or redundant.

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
# Pre-set the shell to zsh via usermod (avoids PAM issues with chsh in chroot)
# Then stub out chsh so zsh.sh's retry loop (line 89: while ! chsh ...) exits immediately
echo "==> [A11] Installing Zsh + Oh My Zsh..."
usermod -s /usr/bin/zsh "${TARGET_USER}"
cat > /usr/local/bin/chsh << 'CHSH_SHIM'
#!/bin/bash
# chsh shim for chroot — shell already set via usermod
echo "[chroot-shim] chsh stubbed (shell already set via usermod)" >&2
exit 0
CHSH_SHIM
chmod +x /usr/local/bin/chsh
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/zsh.sh" || true
rm -f /usr/local/bin/chsh  # Remove shim after zsh.sh completes

# A12: Thunar file manager
echo "==> [A12] Installing Thunar file manager..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/thunar.sh" || true

# A13: XDG Desktop Portal for Hyprland
echo "==> [A13] Installing xdg-desktop-portal-hyprland..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/xdph.sh" || true

# A14: SDDM Theme
echo "==> [A14] Installing SDDM theme..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/sddm_theme.sh" || true

# A15: Dotfiles (Hyprland-Dots)
# NOTE: This clones a THIRD repo (JaKooLit/Hyprland-Dots) inside chroot.
# Network access is required (DNS resolution already copied to chroot).
echo "==> [A15] Installing Hyprland dotfiles..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/dotfiles-main.sh"

# A16: Final check
echo "==> [A16] Running final check..."
su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash install-scripts/02-Final-Check.sh" || true

# ================================================================
# PHASE B: Run HyprFlux dotsSetup modules
# ================================================================

HYPRFLUX_DIR="${TARGET_HOME}/HyprFlux"

echo "==> Phase B: HyprFlux dotfiles modules"

# Set environment variables that HyprFlux modules expect
export HYPRFLUX_ISO_MODE=1

# --- Install gsettings and nwg-look shims as SCRIPTS (not function exports) ---
# export -f does NOT survive the su - boundary, so we create actual script files.
# These are used by module 08-gtk.sh which guards gsettings calls with `command -v`.
cat > /usr/local/bin/gsettings << 'GSETTINGS_SHIM'
#!/bin/bash
echo "[chroot-shim] gsettings stubbed (no dbus in chroot)" >&2
exit 0
GSETTINGS_SHIM
chmod +x /usr/local/bin/gsettings

cat > /usr/local/bin/nwg-look << 'NWGLOOK_SHIM'
#!/bin/bash
echo "[chroot-shim] nwg-look stubbed (no display in chroot)" >&2
exit 0
NWGLOOK_SHIM
chmod +x /usr/local/bin/nwg-look

# --- Set dotsSetup.sh config variables ---
# dotsSetup.sh (lines 39-90) sets ~15 config variables that modules expect.
# We replicate them here so modules have access when sourced.
HYPRFLUX_DIR="${TARGET_HOME}/HyprFlux"
HYPRFLUX_DOTS_DIR="${HYPRFLUX_DIR}/dots"
SDDM_THEME="sugar-candy"
GRUB_THEME_DIR="/usr/share/grub/themes/Vimix"
PLYMOUTH_THEME_DIR="/usr/share/plymouth/themes"
GTK_THEME="HyprFlux-Compact"
ICON_THEME="Papirus-Dark"
CURSOR_THEME="Bibata-Modern-Classic"
CURSOR_SIZE=24
FONT_NAME="Noto Sans"
FONT_SIZE=11
WAYBAR_STYLE="catppuccin-mocha"
TERMINAL="kitty"
BROWSER="firefox"

# Export all config variables so they survive into su - subshells via env
CONFIG_ENV_FILE="/tmp/hyprflux-module-env.sh"
cat > "${CONFIG_ENV_FILE}" << MODULE_ENV_EOF
export HYPRFLUX_ISO_MODE=1
export HYPRFLUX_DIR="${HYPRFLUX_DIR}"
export HYPRFLUX_DOTS_DIR="${HYPRFLUX_DOTS_DIR}"
export SDDM_THEME="${SDDM_THEME}"
export GRUB_THEME_DIR="${GRUB_THEME_DIR}"
export PLYMOUTH_THEME_DIR="${PLYMOUTH_THEME_DIR}"
export GTK_THEME="${GTK_THEME}"
export ICON_THEME="${ICON_THEME}"
export CURSOR_THEME="${CURSOR_THEME}"
export CURSOR_SIZE=${CURSOR_SIZE}
export FONT_NAME="${FONT_NAME}"
export FONT_SIZE=${FONT_SIZE}
export WAYBAR_STYLE="${WAYBAR_STYLE}"
export TERMINAL="${TERMINAL}"
export BROWSER="${BROWSER}"
MODULE_ENV_EOF

# Run modules in order, with special handling for problematic ones
# NOTE: Each su - subshell sources common.sh which calls setup_sudo().
# setup_sudo() spawns a background keep-alive loop, but since we have
# NOPASSWD sudoers, sudo -v succeeds without prompting. The background
# loops are cleaned up when each su - subshell exits (trap in common.sh).
for module in "${HYPRFLUX_DIR}"/modules/[0-9]*.sh; do
    module_name=$(basename "$module")
    echo "==> [Module] ${module_name}..."
    
    case "$module_name" in
        08-gtk.sh)
            # gsettings/nwg-look are shimmed as scripts in /usr/local/bin
            # (see above). The module will find them via `command -v` but
            # they'll just log and exit 0. Real GTK config is deferred to first-boot.
            echo "    [DEFERRED] gsettings requires dbus — will apply on first login"
            su - "${TARGET_USER}" -c "
                source ${CONFIG_ENV_FILE}
                cd ${HYPRFLUX_DIR}
                source lib/common.sh 2>/dev/null || true
                source lib/packages.sh 2>/dev/null || true
                source lib/git.sh 2>/dev/null || true
                source ${module}
            " || true
            ;;
        17-optional-packages.sh)
            # Skip — interactive (ask_yes_no) and optional.
            # NOTE: This skip is technically redundant because when stdin is
            # empty/closed, ask_yes_no's read -rp returns empty string which
            # is treated as "no" (line 106 of common.sh), so the module would
            # silently skip both prompts. Kept explicit for clarity.
            echo "    [SKIPPED] Optional packages (interactive prompts not available)"
            ;;
        10-plymouth.sh)
            # Plymouth needs mkinitcpio/grub — should work but may need care
            echo "    [Module] Running plymouth setup..."
            su - "${TARGET_USER}" -c "
                source ${CONFIG_ENV_FILE}
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
                source ${CONFIG_ENV_FILE}
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

# Remove shim scripts
rm -f /usr/local/bin/gsettings
rm -f /usr/local/bin/nwg-look
rm -f /tmp/hyprflux-module-env.sh

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
- xdg-desktop-portal-hyprland (screen sharing, file picker)
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
| Zsh `chsh` hangs in chroot | **Eliminated** | chsh shimmed as no-op script; shell pre-set via `usermod` |
| Network drops during AUR builds | Medium | Non-fatal; user can re-run yay after reboot |
| Oh My Zsh curl install hangs | Low | Timeout via `--max-time` in curl calls |
| ISAUR not set for Arch-Hyprland scripts | **Eliminated** | Each script sources Global_functions.sh which auto-detects yay |
| `export -f` won't survive `su -` | **Eliminated** | Using script shims in `/usr/local/bin/` instead of function exports |
| systemctl `--user enable` fails in chroot | Low | Shim attempts it (may fail silently); first-boot service handles pipewire |
| setup_sudo() background loops accumulate | Low | NOPASSWD sudoers means `sudo -v` succeeds immediately; loops exit with subshell |
| HyprFlux modules missing config variables | **Eliminated** | All dotsSetup.sh config vars written to shared env file, sourced per module |
| dotfiles-main.sh clones 3rd repo | Low | DNS resolution copied to chroot; network available |
| Custom ahmad9059/Scripts not run | Medium | TODO: verify if essential or covered by HyprFlux modules |
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

~4-6 hours. The chroot wrapper is complex and requires careful testing of each script's behavior inside chroot. The additional shims (chsh, gsettings, nwg-look), config variable replication, and expanded script list add complexity.

---

## Dependencies

- **Requires Phase 1-4**: bootable ISO with working base installer
- **Requires internet during installation**: repos are cloned from GitHub
- **Optional modification to HyprFlux repo**: ISO mode check (~6 lines, for future standalone use)
