#!/bin/bash
# ============================================================================
# hyprflux-chroot-wrapper.sh
# ============================================================================
# Runs INSIDE arch-chroot. Orchestrates HyprFlux installation with
# chroot-safe adaptations.
#
# Arguments:
#   $1 = TARGET_USER (the user account created during installation)
#   $2 = HAS_NVIDIA ("yes" or "no")
#
# This script replaces the Arch-Hyprland whiptail flow entirely and runs
# individual install scripts in the correct order with shims to handle
# chroot limitations (no systemd PID 1, no dbus, no PCI bus, etc.)
# ============================================================================
set -e

TARGET_USER="$1"
HAS_NVIDIA="$2"
TARGET_HOME="/home/${TARGET_USER}"

echo "============================================"
echo "  HyprFlux Chroot Wrapper"
echo "============================================"
echo "  User:   ${TARGET_USER}"
echo "  NVIDIA: ${HAS_NVIDIA}"
echo "============================================"
echo ""

# ============================================================================
# PHASE 0: Install shims and prepare environment
# ============================================================================

echo "==> Phase 0: Setting up chroot environment..."

# --- systemctl shim ---
# Replaces systemctl so that:
#   - "enable --now" becomes "enable" (strips --now)
#   - Runtime verbs (start/stop/restart/is-active/status) are skipped
#   - --user commands are attempted but may fail silently
cat > /usr/local/bin/systemctl-shim << 'SHIM_EOF'
#!/bin/bash
# systemctl shim for chroot environment
args=("$@")
filtered=()
has_runtime_verb=false
has_user=false

for arg in "${args[@]}"; do
    case "$arg" in
        start|stop|restart|is-active|status|reload|daemon-reload|daemon-reexec)
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

# Skip runtime commands entirely
if [[ "$has_runtime_verb" == true ]]; then
    echo "[shim] Skipping: systemctl ${args[*]}" >&2
    exit 0
fi

# For --user commands: attempt but don't fail hard
if [[ "$has_user" == true ]]; then
    /usr/bin/systemctl "${filtered[@]}" 2>/dev/null || true
    exit 0
fi

# For system-level "enable" commands, use the real systemctl
/usr/bin/systemctl "${filtered[@]}"
SHIM_EOF
chmod +x /usr/local/bin/systemctl-shim

# Backup real systemctl and install shim
if [[ ! -f /usr/bin/systemctl.real ]]; then
    cp /usr/bin/systemctl /usr/bin/systemctl.real
fi
cp /usr/local/bin/systemctl-shim /usr/bin/systemctl

# --- chsh shim ---
# Shell is already set via usermod; chsh would hang in chroot due to PAM
cat > /usr/local/bin/chsh << 'CHSH_SHIM'
#!/bin/bash
echo "[shim] chsh stubbed (shell set via usermod)" >&2
exit 0
CHSH_SHIM
chmod +x /usr/local/bin/chsh

# --- gsettings shim ---
# No dbus in chroot; gsettings calls deferred to first-boot
cat > /usr/local/bin/gsettings << 'GSETTINGS_SHIM'
#!/bin/bash
echo "[shim] gsettings stubbed (no dbus in chroot)" >&2
exit 0
GSETTINGS_SHIM
chmod +x /usr/local/bin/gsettings

# --- nwg-look shim ---
# No display in chroot
cat > /usr/local/bin/nwg-look << 'NWGLOOK_SHIM'
#!/bin/bash
echo "[shim] nwg-look stubbed (no display in chroot)" >&2
exit 0
NWGLOOK_SHIM
chmod +x /usr/local/bin/nwg-look

# --- Ensure sudo works for target user without password ---
echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hyprflux-temp
chmod 440 /etc/sudoers.d/hyprflux-temp

# --- Pre-set shell to zsh ---
usermod -s /usr/bin/zsh "${TARGET_USER}" 2>/dev/null || true

echo "    Shims installed."

# ============================================================================
# PHASE A: Run Arch-Hyprland install scripts
# ============================================================================

ARCH_HYPR_DIR="${TARGET_HOME}/Arch-Hyprland"
INSTALL_SCRIPTS="${ARCH_HYPR_DIR}/install-scripts"

echo ""
echo "==> Phase A: Arch-Hyprland components"
echo ""

# Helper function to run script as target user
run_as_user() {
    local script="$1"
    local script_name
    script_name=$(basename "$script")
    
    if [[ ! -f "$script" ]]; then
        echo "    [SKIP] ${script_name} (not found)"
        return 0
    fi
    
    echo "    Running ${script_name}..."
    su - "${TARGET_USER}" -c "cd ${ARCH_HYPR_DIR} && bash ${script}" || {
        echo "    [WARN] ${script_name} had issues (continuing)"
        return 0
    }
}

# A1: Base packages
echo "[A1] Installing base packages..."
run_as_user "${INSTALL_SCRIPTS}/00-base.sh"

# A2: Pacman configuration
echo "[A2] Configuring pacman..."
run_as_user "${INSTALL_SCRIPTS}/pacman.sh"

# A3: Install yay (AUR helper)
echo "[A3] Installing yay AUR helper..."
run_as_user "${INSTALL_SCRIPTS}/yay.sh"

# A4: Hyprland packages
echo "[A4] Installing Hyprland ecosystem packages..."
run_as_user "${INSTALL_SCRIPTS}/01-hypr-pkgs.sh"

# A5: PipeWire audio
echo "[A5] Installing PipeWire audio stack..."
run_as_user "${INSTALL_SCRIPTS}/pipewire.sh"

# A6: Fonts
echo "[A6] Installing fonts..."
run_as_user "${INSTALL_SCRIPTS}/fonts.sh"

# A7: Hyprland compositor
echo "[A7] Installing Hyprland compositor..."
run_as_user "${INSTALL_SCRIPTS}/hyprland.sh"

# A8: Bluetooth
echo "[A8] Installing Bluetooth support..."
run_as_user "${INSTALL_SCRIPTS}/bluetooth.sh"

# A9: SDDM display manager
echo "[A9] Installing SDDM..."
run_as_user "${INSTALL_SCRIPTS}/sddm.sh"

# A10: NVIDIA drivers (conditional)
if [[ "${HAS_NVIDIA}" == "yes" ]]; then
    echo "[A10] Installing NVIDIA drivers..."
    run_as_user "${INSTALL_SCRIPTS}/nvidia.sh"
else
    echo "[A10] Skipping NVIDIA (not detected)"
fi

# A11: Zsh + Oh My Zsh
echo "[A11] Installing Zsh + Oh My Zsh..."
run_as_user "${INSTALL_SCRIPTS}/zsh.sh"

# A12: Thunar file manager
echo "[A12] Installing Thunar file manager..."
run_as_user "${INSTALL_SCRIPTS}/thunar.sh"

# A13: XDG Desktop Portal for Hyprland
echo "[A13] Installing xdg-desktop-portal-hyprland..."
run_as_user "${INSTALL_SCRIPTS}/xdph.sh"

# A14: SDDM Theme
echo "[A14] Installing SDDM theme..."
run_as_user "${INSTALL_SCRIPTS}/sddm_theme.sh"

# A15: Dotfiles (clones JaKooLit/Hyprland-Dots)
echo "[A15] Installing Hyprland dotfiles..."
run_as_user "${INSTALL_SCRIPTS}/dotfiles-main.sh"

# A16: Final check
echo "[A16] Running final check..."
run_as_user "${INSTALL_SCRIPTS}/02-Final-Check.sh"

echo ""
echo "    Phase A complete."

# ============================================================================
# PHASE B: Run HyprFlux dotsSetup modules
# ============================================================================

HYPRFLUX_DIR="${TARGET_HOME}/HyprFlux"

echo ""
echo "==> Phase B: HyprFlux dotfiles modules"
echo ""

# --- Create config environment file for modules ---
# HyprFlux modules expect certain variables from dotsSetup.sh
CONFIG_ENV_FILE="/tmp/hyprflux-module-env.sh"
cat > "${CONFIG_ENV_FILE}" << MODULE_ENV_EOF
export HYPRFLUX_ISO_MODE=1
export HYPRFLUX_DIR="${HYPRFLUX_DIR}"
export HYPRFLUX_DOTS_DIR="${HYPRFLUX_DIR}/dots"
export SDDM_THEME="sugar-candy"
export GRUB_THEME_DIR="/usr/share/grub/themes/Vimix"
export PLYMOUTH_THEME_DIR="/usr/share/plymouth/themes"
export GTK_THEME="HyprFlux-Compact"
export ICON_THEME="Papirus-Dark"
export CURSOR_THEME="Bibata-Modern-Classic"
export CURSOR_SIZE=24
export FONT_NAME="Noto Sans"
export FONT_SIZE=11
export WAYBAR_STYLE="catppuccin-mocha"
export TERMINAL="kitty"
export BROWSER="firefox"
MODULE_ENV_EOF

# Run modules in order
if [[ -d "${HYPRFLUX_DIR}/modules" ]]; then
    for module in "${HYPRFLUX_DIR}"/modules/[0-9]*.sh; do
        [[ ! -f "$module" ]] && continue
        
        module_name=$(basename "$module")
        
        case "$module_name" in
            08-gtk.sh)
                # gsettings requires dbus - deferred to first-boot
                echo "    [B] ${module_name} (gsettings deferred to first-boot)"
                su - "${TARGET_USER}" -c "
                    source ${CONFIG_ENV_FILE} 2>/dev/null || true
                    cd ${HYPRFLUX_DIR}
                    source lib/common.sh 2>/dev/null || true
                    source lib/packages.sh 2>/dev/null || true
                    source lib/git.sh 2>/dev/null || true
                    source ${module}
                " 2>/dev/null || true
                ;;
            17-optional-packages.sh)
                # Interactive - skip in ISO mode
                echo "    [B] ${module_name} (skipped - interactive)"
                ;;
            *)
                echo "    [B] ${module_name}..."
                su - "${TARGET_USER}" -c "
                    source ${CONFIG_ENV_FILE} 2>/dev/null || true
                    cd ${HYPRFLUX_DIR}
                    source lib/common.sh 2>/dev/null || true
                    source lib/packages.sh 2>/dev/null || true
                    source lib/git.sh 2>/dev/null || true
                    source ${module}
                " 2>/dev/null || {
                    echo "    [WARN] ${module_name} had issues (continuing)"
                }
                ;;
        esac
    done
else
    echo "    [WARN] HyprFlux modules directory not found"
fi

echo ""
echo "    Phase B complete."

# ============================================================================
# PHASE C: Enable system services
# ============================================================================

echo ""
echo "==> Phase C: Enabling system services"

# Restore real systemctl
if [[ -f /usr/bin/systemctl.real ]]; then
    cp /usr/bin/systemctl.real /usr/bin/systemctl
    rm -f /usr/bin/systemctl.real
fi

# Enable display manager and core services
systemctl enable sddm 2>/dev/null || echo "    [WARN] Could not enable sddm"
systemctl enable bluetooth 2>/dev/null || echo "    [WARN] Could not enable bluetooth"
systemctl enable NetworkManager 2>/dev/null || true  # Already enabled in Phase 4

echo "    Services enabled."

# ============================================================================
# PHASE D: Create first-boot fixup service
# ============================================================================

echo ""
echo "==> Phase D: Creating first-boot fixup"

# Create autostart directory
mkdir -p "${TARGET_HOME}/.config/autostart"
mkdir -p "${TARGET_HOME}/.local/bin"

# Create autostart desktop entry
cat > "${TARGET_HOME}/.config/autostart/hyprflux-first-boot.desktop" << DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=HyprFlux First Boot Setup
Exec=${TARGET_HOME}/.local/bin/hyprflux-first-boot.sh
Terminal=false
X-GNOME-Autostart-enabled=true
DESKTOP_EOF

# Create first-boot script
cat > "${TARGET_HOME}/.local/bin/hyprflux-first-boot.sh" << 'FIRSTBOOT_EOF'
#!/bin/bash
# HyprFlux first-boot fixup
# Applies settings that couldn't be configured in chroot (no dbus)

MARKER="$HOME/.config/hyprflux-first-boot-done"

# Only run once
if [[ -f "$MARKER" ]]; then
    exit 0
fi

# Wait for desktop to initialize
sleep 3

# Apply GTK theme via gsettings
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface gtk-theme "HyprFlux-Compact" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-size 24 2>/dev/null || true
    gsettings set org.gnome.desktop.interface font-name "Noto Sans 11" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" 2>/dev/null || true
fi

# Apply nwg-look if available
if command -v nwg-look &>/dev/null; then
    nwg-look -a 2>/dev/null || true
fi

# Enable pipewire user services
systemctl --user enable --now pipewire.socket 2>/dev/null || true
systemctl --user enable --now pipewire-pulse.socket 2>/dev/null || true
systemctl --user enable --now wireplumber.service 2>/dev/null || true

# Mark as done
mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"

# Remove autostart entry (one-shot)
rm -f "$HOME/.config/autostart/hyprflux-first-boot.desktop"

# Notify user
notify-send "HyprFlux" "First-boot setup complete!" 2>/dev/null || true
FIRSTBOOT_EOF

chmod +x "${TARGET_HOME}/.local/bin/hyprflux-first-boot.sh"

# Fix ownership
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config" 2>/dev/null || true
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local" 2>/dev/null || true

echo "    First-boot fixup created."

# ============================================================================
# CLEANUP
# ============================================================================

echo ""
echo "==> Cleanup"

# Remove temporary sudoers entry
rm -f /etc/sudoers.d/hyprflux-temp

# Remove shim scripts
rm -f /usr/local/bin/systemctl-shim
rm -f /usr/local/bin/chsh
rm -f /usr/local/bin/gsettings
rm -f /usr/local/bin/nwg-look
rm -f "${CONFIG_ENV_FILE}"

echo "    Cleanup complete."

echo ""
echo "============================================"
echo "  HyprFlux chroot wrapper complete!"
echo "============================================"
