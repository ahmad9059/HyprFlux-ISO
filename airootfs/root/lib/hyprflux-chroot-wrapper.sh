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
# NOTE: base-installer and base-dots are merged into the HyprFlux repo
# (base-installer/ and base-dots/ subdirs). This script replaces the
# base-installer whiptail flow entirely and runs
# individual install scripts in the correct order with shims to handle
# chroot limitations (no systemd PID 1, no dbus, no PCI bus, etc.)
# ============================================================================
set -uo pipefail
# NOTE: We intentionally do NOT use set -e here.
# Phase A/B scripts may fail (network, AUR, etc.) and we must always
# reach Phase C to enable sddm, even if earlier phases have errors.

TARGET_USER="$1"
HAS_NVIDIA="$2"
NVIDIA_DRIVER="${3:-nouveau}"
XKB_LAYOUT="${4:-us}"
XKB_VARIANT="${5:-}"
INSTALL_PROFILE="${6:-full}"
[[ "$INSTALL_PROFILE" == desktop || "$INSTALL_PROFILE" == full ]] || exit 1
[[ "$NVIDIA_DRIVER" == open || "$NVIDIA_DRIVER" == nouveau ]] || exit 1
[[ "$XKB_LAYOUT" =~ ^[a-zA-Z0-9_+-]+$ && "$XKB_VARIANT" =~ ^[a-zA-Z0-9_+-]*$ ]] || exit 1
TARGET_HOME="/home/${TARGET_USER}"
[[ $EUID -eq 0 && "$TARGET_USER" =~ ^[a-z][a-z0-9_-]{0,31}$ && "$TARGET_USER" != root ]] || exit 1
id "$TARGET_USER" >/dev/null || exit 1
FAILED_COMPONENTS=()
ISO_THEME_MODULE=""

record_missing_applications() {
    local report="$1"
    shift
    if (( $# )); then
        mkdir -p "$(dirname "$report")"
        printf '%s\n' "$@" > "$report"
    else
        rm -f -- "$report"
    fi
}

# Always revoke temporary privileges, including on errors and interrupts.
cleanup_wrapper() {
    rm -f /etc/sudoers.d/hyprflux-temp
    rm -f /usr/local/bin/chsh /usr/local/bin/gsettings /usr/local/bin/nwg-look /usr/local/bin/yay-iso
    rm -f /tmp/hyprflux-module-env.sh
    if [[ -n "${ISO_THEME_MODULE:-}" ]]; then rm -f -- "$ISO_THEME_MODULE"; fi
}
trap cleanup_wrapper EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

recover_pacman_lock() {
    local lock="$1"
    [[ -e "$lock" ]] || return 0
    if ! command -v pgrep >/dev/null; then
        echo '[ERROR] Cannot safely inspect package-manager processes; keeping database lock.'
        return 1
    fi
    local process_status=0
    pgrep -x 'pacman|yay|paru|pamac-daemon|packagekitd' >/dev/null || process_status=$?
    if (( process_status != 1 )); then
        echo '[ERROR] A package manager is running or inspection failed; keeping database lock.'
        return 1
    fi
    echo '[Recovery] Removing stale pacman lock; no package manager is running.'
    rm -f -- "$lock"
}

prepare_iso_theme_module() {
    local source="$1" destination="$2"
    # papirus-folders is not an official-repository package. Do not let the
    # optional folder-color tool abort installation of the actual icon theme.
    # Adapt a temporary copy, leaving the pinned upstream checkout untouched.
    grep -Fq 'pacman -S --needed --noconfirm papirus-icon-theme papirus-folders' "$source" \
        || { echo '[ERROR] Unrecognized pinned theme-module install command.' >&2; return 1; }
    sed 's/pacman -S --needed --noconfirm papirus-icon-theme papirus-folders/pacman -S --needed --noconfirm papirus-icon-theme/' \
        "$source" > "$destination" || return 1
    chmod 644 "$destination"
}

# Retain downloaded packages and retry transient HTTPS resets. A failed
# transaction does not imply that the selected package set is invalid.
rotate_mirrors() {
    local destination="$1" candidate
    candidate=$(mktemp "${destination}.XXXXXX") || return 1
    if awk '/^[[:space:]]*Server[[:space:]]*=/ && !saved {saved=$0; next} {print} END {if(saved) print saved}' \
        "$destination" > "$candidate"; then
        chmod 644 "$candidate"
        mv -f "$candidate" "$destination"
    else
        rm -f "$candidate"
        return 1
    fi
}

pacman_retry() {
    local attempt
    for attempt in 1 2 3; do
        if pacman "$@"; then return 0; fi
        if (( attempt < 3 )); then
            echo "[WARN] Package transaction failed; retrying ($attempt/3)..."
            if [[ -n "${RETRY_MIRRORLIST:-}" && -f "$RETRY_MIRRORLIST" ]]; then
                rotate_mirrors "$RETRY_MIRRORLIST" \
                    || echo '[WARN] Could not rotate mirror priority.'
            fi
            sleep 5
        fi
    done
    return 1
}

desktop_commands_present() {
    pacman -Q waybar-git wlogout >/dev/null 2>&1 \
        && command -v waybar >/dev/null && command -v wlogout >/dev/null
}

normalize_hyprland_defaults() {
    local settings="$1"
    [[ -f "$settings" ]] || return 0
    # The pinned dots redundantly set the default scale of 1. Hyprland 0.57
    # deprecates this key; omitting it preserves the default without warnings.
    # Do not silently discard a user's non-default special-workspace scale.
    sed -i '/^[[:space:]]*special_scale_factor[[:space:]]*=[[:space:]]*1\(\.0\+\)\{0,1\}[[:space:]]*,[[:space:]]*\(--.*\)\{0,1\}$/d' "$settings"
}

install_waybar_session_service() {
    local home="$1"
    mkdir -p "$home/.config/systemd/user" "$home/.local/bin"
    cat > "$home/.config/systemd/user/hyprflux-waybar.service" <<'WAYBAR_SERVICE_EOF'
[Unit]
Description=HyprFlux Waybar
PartOf=graphical-session.target
StartLimitIntervalSec=30
StartLimitBurst=5

[Service]
Type=simple
ExecStart=/usr/bin/waybar
Restart=on-failure
RestartSec=2
TimeoutStopSec=5
StandardOutput=journal
StandardError=journal
WAYBAR_SERVICE_EOF
    cat > "$home/.local/bin/hyprflux-start-waybar.sh" <<'WAYBAR_START_EOF'
#!/bin/bash
set -euo pipefail
mkdir -p "$HOME/.local/state/hyprflux"
exec >>"$HOME/.local/state/hyprflux/session-start.log" 2>&1
: "${WAYLAND_DISPLAY:?Wayland session required}"
: "${HYPRLAND_INSTANCE_SIGNATURE:?Hyprland session required}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
# Import synchronously: independent Lua exec calls do not establish ordering.
dbus-update-activation-environment --systemd WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP
systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP
# Finish first-login GTK exports before the bar loads its theme. An XDG
# autostart duplicate may already own the lock, so wait for that copy as well.
timeout --kill-after=2s 60 bash "$HOME/.local/bin/hyprflux-first-boot.sh" \
    || echo '[WARN] First-login setup needs attention; see first-boot.log.'
flock -w 30 "$HOME/.local/state/hyprflux/first-boot.lock" true \
    || echo '[WARN] First-login setup is still running.'
systemctl --user daemon-reload
# An installed unit may never have been loaded on a fresh user manager.
systemctl --user reset-failed hyprflux-waybar.service 2>/dev/null || true
systemctl --user restart hyprflux-waybar.service
WAYBAR_START_EOF
    chmod 755 "$home/.local/bin/hyprflux-start-waybar.sh"
    local startup="$home/.config/hypr/UserConfigs/startup-apps.lua"
    if [[ -f "$startup" ]]; then
        sed -i 's/hl\.exec_cmd("waybar")/-- Waybar is managed by the HyprFlux session launcher./' "$startup"
    fi
}

normalize_and_validate_waybar() {
    local directory="$1"
    # Pinned hardware detection replaces a multi-line hwmon array but drops its
    # comma. Repair that precise generated form; reject other malformed JSONC.
    sed -i 's/^\([[:space:]]*"hwmon-path"[[:space:]]*:[[:space:]]*\[.*\]\)[[:space:]]*$/\1,/' \
        "$directory/Modules" || return 1
    python - "$directory" <<'WAYBAR_VALIDATE_EOF'
from pathlib import Path
import sys
import json5

directory = Path(sys.argv[1])
for name in ("config", "Modules", "ModulesWorkspaces", "ModulesCustom", "ModulesGroups", "UserModules"):
    path = directory / name
    try:
        with path.open(encoding="utf-8") as stream:
            json5.load(stream)
    except (OSError, ValueError) as error:
        raise SystemExit(f"[ERROR] Invalid Waybar configuration {path}: {error}")
    print(f"[OK] Waybar JSONC parsed: {path}")
WAYBAR_VALIDATE_EOF
}

install_desktop_aur() {
    local attempt
    for attempt in 1 2 3; do
        if desktop_commands_present; then return 0; fi
        timeout --kill-after=30s 1800 su - "$TARGET_USER" -s /bin/bash -c \
            'yay -S --needed --noconfirm waybar-git wlogout' </dev/null || true
        if desktop_commands_present; then return 0; fi
        rotate_mirrors "$RETRY_MIRRORLIST" || true
    done
    echo '[ERROR] Required Waybar/wlogout installation failed.'
    return 1
}

echo "============================================"
echo "  HyprFlux Chroot Wrapper"
echo "============================================"
echo "  User:   ${TARGET_USER}"
echo "  NVIDIA: ${HAS_NVIDIA}"
echo "============================================"
echo ""

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

echo "==> Pre-flight checks..."

# Check filesystem is writable
if ! touch /tmp/.write_test 2>/dev/null; then
    echo "    [ERROR] Filesystem is read-only! Cannot continue."
    exit 1
fi
rm -f /tmp/.write_test

# Check available disk space (need at least 5GB free)
AVAILABLE_KB=$(df / | tail -1 | awk '{print $4}')
AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))
if [[ $AVAILABLE_GB -lt 5 ]]; then
    echo "    [WARN] Low disk space: ${AVAILABLE_GB}GB free (recommend 5GB+)"
else
    echo "    Disk space OK: ${AVAILABLE_GB}GB free"
fi

# Check internet connectivity
if ! curl -s --max-time 5 https://archlinux.org >/dev/null 2>&1; then
    echo "    [WARN] Internet connectivity check failed"
else
    echo "    Internet connectivity OK"
fi

echo ""

# ============================================================================
# PHASE 0: Install shims and prepare environment
# ============================================================================

echo "==> Phase 0: Setting up chroot environment..."

# --- Crash recovery ---
# If an older wrapper died mid-Phase-A, its systemctl shim may still be in
# place. Restore the real binary before any module can rebuild the initramfs.
if [[ -f /usr/bin/systemctl.real ]]; then
    cp /usr/bin/systemctl.real /usr/bin/systemctl
    rm -f /usr/bin/systemctl.real
    echo "    [Recovery] Restored real systemctl from a previous interrupted run."
fi
if ! file -L /usr/bin/systemctl 2>/dev/null | grep -q 'ELF'; then
    echo "    [ERROR] /usr/bin/systemctl is not the real ELF binary; aborting before initramfs generation." >&2
    exit 1
fi

# Never replace /usr/bin/systemctl. mkinitcpio's systemd hook copies that
# executable into the initramfs; copying a shell shim there breaks
# initrd-cleanup.service because systemctl.real is not included in the image.
# Real systemctl detects chroot/offline operation and safely skips runtime work.
rm -f /usr/local/bin/systemctl-shim

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

# --- Temporary FULL passwordless sudo (removed at cleanup) ---
echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hyprflux-temp
chmod 440 /etc/sudoers.d/hyprflux-temp

# pacman can execute package hooks as root. Never grant it permanent NOPASSWD.
rm -f /etc/sudoers.d/hyprflux-pacman
visudo -cf /etc/sudoers.d/hyprflux-temp || exit 1

# A usable desktop must not depend on an optional AUR/application batch.
recover_pacman_lock /var/lib/pacman/db.lck || exit 1
for mirror in \
    'https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
    'https://mirrors.mit.edu/archlinux/$repo/os/$arch' \
    'https://mirror.rackspace.com/archlinux/$repo/os/$arch'; do
    grep -Fxq "Server = $mirror" /etc/pacman.d/mirrorlist \
        || printf 'Server = %s\n' "$mirror" >> /etc/pacman.d/mirrorlist
done
RETRY_MIRRORLIST=/etc/pacman.d/mirrorlist
pacman_retry -Syu --needed --noconfirm hyprland hypridle hyprlock sddm mesa \
    kitty foot rofi swaync networkmanager pipewire pipewire-audio pipewire-pulse pipewire-alsa pipewire-jack wireplumber sof-firmware \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk polkit hyprpolkitagent \
    qt6-svg qt6-virtualkeyboard qt6-multimedia xorg-xwayland zsh \
    firefox chromium thunar tumbler thunar-archive-plugin thunar-volman file-roller \
    network-manager-applet power-profiles-daemon wireless-regdb bluez bluez-utils blueman \
    wl-clipboard cliphist grim slurp hyprpicker swappy imagemagick jq \
    pamixer pavucontrol playerctl brightnessctl nwg-look nwg-displays \
    python-requests python-pyquery python-json5 xdg-user-dirs xdg-utils gvfs gvfs-mtp \
    qt5ct qt6ct kvantum kvantum-qt5 tmux neovim fzf ripgrep fd lsd bat zoxide btop fastfetch yazi yad \
    adwaita-fonts gsettings-desktop-schemas dconf papirus-icon-theme noto-fonts noto-fonts-emoji noto-fonts-cjk ttf-jetbrains-mono-nerd \
    otf-font-awesome mpv plymouth bc libspng \
    || { echo '[ERROR] Essential desktop package transaction failed.'; exit 1; }

# --- Pre-set shell to zsh (only if zsh is already installed) ---
# zsh.sh in Phase A installs zsh; we set the shell after that runs.
# Here we ensure at minimum /bin/bash is set so 'su -' works reliably.
usermod -s /bin/bash "${TARGET_USER}" 2>/dev/null || true

echo "    Shims installed."

# ============================================================================
# PHASE A: Run base-installer install scripts
# ============================================================================

HYPRFLUX_DIR="${TARGET_HOME}/HyprFlux"  # merged repo root
ARCH_HYPR_DIR="${HYPRFLUX_DIR}/base-installer"  # merged into HyprFlux repo
INSTALL_SCRIPTS="${ARCH_HYPR_DIR}/install-scripts"

echo ""
echo "==> Phase A: base-installer components"
echo ""

# Helper function to run an install script as the target user.
# Uses -s /bin/bash explicitly so it works before zsh is installed.
run_as_user() {
    local script="$1"
    local script_name
    script_name=$(basename "$script")

    if [[ ! -f "$script" ]]; then
        echo "    [WARN] ${script_name} (not found)"
        FAILED_COMPONENTS+=("$script_name")
        return 0
    fi

    echo "    Running ${script_name}..."
    timeout --kill-after=30s 2400 su - "${TARGET_USER}" -s /bin/bash -c "
        export HOME=\"${TARGET_HOME}\"
        export PATH=\"/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin\"
        # Several upstream scripts use set -e with tput during initialization.
        # A batch chroot may inherit TERM=dumb, making them exit without a log.
        export TERM=xterm-256color
        export HYPRFLUX_LOGS_DIR=\"${TARGET_HOME}/HyprFlux/logs\"
        cd \"${ARCH_HYPR_DIR}\" 2>/dev/null || cd \"\$HOME\"
        bash \"${script}\"
    " </dev/null || {
        echo "    [WARN] ${script_name} had issues (continuing)"
        FAILED_COMPONENTS+=("$script_name")
        return 0
    }
}

# Ensure unified log dir exists and is writable by the target user
mkdir -p "${TARGET_HOME}/HyprFlux/logs/installer"
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/HyprFlux/logs"

# Inject HyprFlux's own zsh.sh over the base one (same as base-installer
# install.sh does). Official packages and direct AUR builds suffice for the
# ISO profiles; do not run the optional third-party repository bootstrap here.
cp "${HYPRFLUX_DIR}/scripts/zsh.sh" "${INSTALL_SCRIPTS}/zsh.sh" 2>/dev/null || true
chmod +x "${INSTALL_SCRIPTS}/zsh.sh" 2>/dev/null || true
echo '[A0] Using official repositories + direct AUR helper setup (A3).'
echo '    Optional Chaotic-AUR repository bootstrap is not required by ISO profiles.'

# A1: Base packages
echo "[A1] Installing base packages..."
run_as_user "${INSTALL_SCRIPTS}/00-base.sh"

# A2: Pacman configuration
echo "[A2] Configuring pacman..."
run_as_user "${INSTALL_SCRIPTS}/pacman.sh"

# A3: Install yay (AUR helper)
echo "[A3] Installing yay AUR helper..."
if ! command -v yay >/dev/null; then run_as_user "${INSTALL_SCRIPTS}/yay.sh"; fi

# Verify yay was installed and is in PATH
if ! command -v yay &>/dev/null && ! su - "${TARGET_USER}" -s /bin/bash -c "command -v yay" &>/dev/null; then
    echo "    [WARN] yay not found in PATH after installation, retrying from AUR..."
    # NOTE: yay-bin is AUR-only — `pacman -S yay-bin` can never succeed.
    # Clone the PKGBUILD and makepkg as the target user (sudo is passwordless
    # here via the Phase-0 sudoers drop-in).
    su - "${TARGET_USER}" -s /bin/bash -c "
        cd /tmp || exit 1
        rm -rf yay-bin
        git clone --depth=1 https://aur.archlinux.org/yay-bin.git yay-bin 2>/dev/null || exit 1
        cd yay-bin || exit 1
        makepkg -si --noconfirm 2>/dev/null
    " || echo "    [WARN] yay fallback build failed (AUR packages will not install)"
fi

# Ensure yay is in the user's PATH by creating a symlink if needed
if [[ -f /usr/bin/yay ]] && [[ ! -L /usr/local/bin/yay ]]; then
    ln -sf /usr/bin/yay /usr/local/bin/yay 2>/dev/null || true
fi

# Export yay path for scripts that source Global_functions.sh
YAY_PATH=$(command -v yay || su - "${TARGET_USER}" -s /bin/bash -c "command -v yay" 2>/dev/null || echo "")
export YAY_PATH
if [[ -n "$YAY_PATH" ]]; then
    echo "    yay is available at: $YAY_PATH"
    # Create wrapper to ensure yay is always found
    cat > /usr/local/bin/yay-iso << YAY_EOF
#!/bin/bash
exec "$YAY_PATH" "\$@"
YAY_EOF
    chmod +x /usr/local/bin/yay-iso
else
    echo "    [WARN] yay installation may have failed. AUR packages will not install."
fi

# A4: Hyprland packages
echo "[A4] Installing Hyprland ecosystem packages..."
# Install the session-critical AUR components BEFORE optional multi-gigabyte
# application batches. A timed-out media bundle must not leave Waybar missing.
install_desktop_aur || exit 1
# Patch Global_functions.sh to ensure ISAUR is set correctly for chroot
if [[ -f "${INSTALL_SCRIPTS}/Global_functions.sh" ]]; then
    # Backup original
    cp "${INSTALL_SCRIPTS}/Global_functions.sh" "${INSTALL_SCRIPTS}/Global_functions.sh.bak"
    # Replace the ISAUR line to use a fallback
    sed -i 's/^ISAUR=$(command -v yay || command -v paru)/ISAUR=$(command -v yay || command -v paru || echo "\/usr\/bin\/yay")/' "${INSTALL_SCRIPTS}/Global_functions.sh"
fi
if [[ "$INSTALL_PROFILE" == full ]]; then
    run_as_user "${INSTALL_SCRIPTS}/01-hypr-pkgs.sh"
else
    echo '    Desktop essentials installed; extended application bundle not selected.'
fi

# A4b: Record missing optional applications without repeating expensive builds.
if [[ "$INSTALL_PROFILE" == full ]]; then
AUR_PACKAGES=(mpvpaper waybar-git visual-studio-code-bin 64gram-desktop-bin vesktop \
              foliate localsend-bin tuxedo-bin claude-code opencode-bin openai-codex-bin \
              freedownloadmanager)
AUR_MISSING=()
for _aur_pkg in "${AUR_PACKAGES[@]}"; do
  if ! su - "${TARGET_USER}" -s /bin/bash -c "command -v yay >/dev/null 2>&1 && yay -Q $_aur_pkg >/dev/null 2>&1" 2>/dev/null; then
    AUR_MISSING+=("$_aur_pkg")
  fi
done
record_missing_applications /var/log/hyprflux-installer/missing-applications.txt "${AUR_MISSING[@]}"
if [ ${#AUR_MISSING[@]} -gt 0 ]; then
  echo "    [WARN] AUR packages missing after Phase A: ${AUR_MISSING[*]}"
  echo "           Optional applications are recorded for manual recovery; no repeated hour-long build loops."
  if [ ${#AUR_MISSING[@]} -gt 0 ]; then
    echo "    [WARN] AUR packages still missing: ${AUR_MISSING[*]}"
    echo "           After login: yay -S --needed <package>"
    echo "           Last lines of the install log for diagnosis:"
    _pkg_log=("${TARGET_HOME}/HyprFlux/logs/installer/"*_hypr-pkgs.log)
    tail -25 "${_pkg_log[@]}" 2>/dev/null | sed 's/^/           /'
  else
    echo "    [OK] All missing AUR packages installed during retry."
  fi
fi
unset _aur_pkg AUR_PACKAGES AUR_MISSING AUR_STILL_MISSING _pkg_log
else
    rm -f /var/log/hyprflux-installer/missing-applications.txt
fi
printf '%s\n' "$INSTALL_PROFILE" > /etc/hyprflux-install-profile

# A5: PipeWire audio
echo "[A5] Installing PipeWire audio stack..."
pacman -Q pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber sof-firmware >/dev/null
echo '    Required audio packages verified; user-service activation is deferred to first login.'

# A6: Fonts
echo "[A6] Installing fonts..."
if [[ "$INSTALL_PROFILE" == full ]]; then
    run_as_user "${INSTALL_SCRIPTS}/fonts.sh"
else
    echo '    Desktop fonts are already installed; skipping the extended font collection.'
fi

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
    if [[ "$NVIDIA_DRIVER" == open ]]; then
        echo '[A10] Installing current NVIDIA open drivers and matching kernel headers...'
        pacman_retry -S --needed --noconfirm linux-headers nvidia-open-dkms nvidia-utils nvidia-settings \
            || { echo '[ERROR] NVIDIA driver installation failed.'; exit 1; }
        mkdir -p /etc/mkinitcpio.conf.d /etc/modprobe.d
        echo 'MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' > /etc/mkinitcpio.conf.d/90-hyprflux-nvidia.conf
        echo 'options nvidia_drm modeset=1 fbdev=1' > /etc/modprobe.d/hyprflux-nvidia.conf
        for kernel in /usr/lib/modules/*; do
            [[ -f "$kernel/pkgbase" ]] || continue
            modinfo -k "${kernel##*/}" nvidia >/dev/null || exit 1
        done
    else
        echo '[A10] Using in-kernel Nouveau with Mesa (legacy/recovery option).'
    fi
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

# A14: (removed — SDDM theme ships via HyprFlux module 06-sddm)

# A15: Dotfiles (verifies merged base-dots; config deployed once by module 02)
echo "[A15] Installing Hyprland dotfiles..."
run_as_user "${INSTALL_SCRIPTS}/dotfiles-main.sh"

# A16: Final check
echo "[A16] Running final check..."
echo '    Using ISO final validation below; legacy audit uses obsolete package names.'

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
# modules/expect these from dotsSetup.sh — REPO_DIR is the merged repo root
export REPO_DIR="${HYPRFLUX_DIR}"
export SDDM_THEME_NAME="HyprFlux-sddm-theme"
export SDDM_THEME_SOURCE="${HYPRFLUX_DIR}/utilities/HyprFlux-sddm-theme"
export SDDM_THEME_DEST="/usr/share/sddm/themes/HyprFlux-sddm-theme"
export SDDM_CONF="/etc/sddm.conf"
export GRUB_THEME_ARCHIVE="${HYPRFLUX_DIR}/utilities/HyprFlux-1080p.tar.xz"
export GRUB_THEME_DIR="/tmp/hyprflux-grub"
export PLYMOUTH_THEME_ARCHIVE="${HYPRFLUX_DIR}/utilities/hyprflux-plymouth.tar.xz"
export PLYMOUTH_THEME_DIR="/tmp/hyprflux-plymouth"
export PLYMOUTH_THEME_NAME="hyprflux"
export GTK_THEME="HyprFlux-Compact"
export ICON_THEME="Papirus-Dark"
export CURSOR_THEME="Future-black Cursors"
export CURSOR_SIZE=24
export FONT_NAME="Adwaita Sans 11"
export TERMINAL="kitty"
export BROWSER="chromium"
export WALLPAPER_REPO="https://github.com/ahmad9059/wallpapers-bank"
export WALLPAPER_DIR="${TARGET_HOME}/Pictures/wallpapers"
export BACKUP_DIR="${TARGET_HOME}/dotfiles_backup"
export NVIM_CONFIG_DIR="${TARGET_HOME}/.config/nvim"
export REPO_URL_NVIM="https://github.com/ahmad9059/nvim"
export TMUXIFIER_REPO="https://github.com/jimeh/tmuxifier.git"
export BIBATA_CURSOR_ARCHIVE="${HYPRFLUX_DIR}/utilities/Bibata-Modern-Classic.tar.xz"
export DESKTOP_DIR="${TARGET_HOME}/.local/share/applications"
export ICON_DIR="${TARGET_HOME}/.local/share/icons/apps"
export WEBAPPS_CONF="${HYPRFLUX_DIR}/config/webapps.conf"
export WAYBAR_STYLE_TARGET="${TARGET_HOME}/.config/waybar/style.css"
export WAYBAR_LAYOUT_TARGET="${TARGET_HOME}/.config/waybar/config"
export CUSTOM_WAYBAR_STYLE="${TARGET_HOME}/.config/waybar/style/HyprFlux-Default.css"
export CUSTOM_WAYBAR_LAYOUT="${TARGET_HOME}/.config/waybar/configs/HyprFlux-Default-Laptop"
export BIBATA_CURSOR_URL="https://github.com/LOSEARDES77/Bibata-Cursor-hyprcursor/releases/download/1.0/hypr_Bibata-Modern-Classic.tar.gz"
MODULE_ENV_EOF

# Run modules in order
if [[ -d "${HYPRFLUX_DIR}/modules" ]]; then
    for module in "${HYPRFLUX_DIR}"/modules/[0-9]*.sh; do
        [[ ! -f "$module" ]] && continue
        
        module_name=$(basename "$module")
        module_script="$module"
        if [[ "$module_name" == 04-themes.sh ]]; then
            ISO_THEME_MODULE=$(mktemp /tmp/hyprflux-iso-theme.XXXXXX)
            prepare_iso_theme_module "$module" "$ISO_THEME_MODULE"
            module_script="$ISO_THEME_MODULE"
        fi
        
        echo "    [B] ${module_name}..."
        # A separate strict Bash process preserves errexit even though the
        # parent collects failures. Never suppress stderr: it is diagnostic.
        timeout --kill-after=30s 1200 su - "${TARGET_USER}" -s /bin/bash -c "
            set -e
            export HOME=\"${TARGET_HOME}\"
            source \"${CONFIG_ENV_FILE}\"
            cd \"${HYPRFLUX_DIR}\"
            source lib/common.sh
            source lib/packages.sh
            source lib/git.sh
            source \"${module_script}\"
        " </dev/null || {
            echo "    [WARN] ${module_name} failed; recorded in installation summary."
            FAILED_COMPONENTS+=("$module_name")
        }
        if [[ -n "$ISO_THEME_MODULE" ]]; then
            rm -f -- "$ISO_THEME_MODULE"
            ISO_THEME_MODULE=""
        fi
    done
else
    echo "    [ERROR] HyprFlux modules directory not found"
    exit 1
fi

echo ""
echo "    Phase B complete."

normalize_hyprland_defaults "${TARGET_HOME}/.config/hypr/UserConfigs/user-settings.lua"
normalize_and_validate_waybar "${TARGET_HOME}/.config/waybar" || exit 1

# A chroot has no desktop session. Do not persist its guessed 1080p mode or
# live-environment DRM card numbers (those can change after driver installation).
if [[ -d "${TARGET_HOME}/.config/hypr" ]]; then
    cat > "${TARGET_HOME}/.config/hypr/monitors.lua" <<'MONITORS_EOF'
-- Use the connected display's native mode, not the installer's display.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
MONITORS_EOF
    printf 'monitor=,preferred,auto,1\n' > "${TARGET_HOME}/.config/hypr/monitors.conf"
    gpu_env="${TARGET_HOME}/.config/hypr/UserConfigs/env-variables.lua"
    if [[ -f "$gpu_env" ]]; then
        sed -i '/hl\.env("AQ_DRM_DEVICES",/d' "$gpu_env"
    fi
fi

if [[ "$HAS_NVIDIA" == yes && "$NVIDIA_DRIVER" == nouveau ]]; then
    gpu_env="${TARGET_HOME}/.config/hypr/UserConfigs/env-variables.lua"
    if [[ -f "$gpu_env" ]]; then
        # Upstream detects the vendor, not the selected kernel driver. Its
        # NVIDIA GBM/VAAPI overrides are invalid when running Nouveau.
        sed -i '/>>> GPU_CONFIG_START >>>/,/>>> GPU_CONFIG_END <<</{ />>> GPU_CONFIG/!d; }' "$gpu_env"
    fi
fi

# ============================================================================
# PHASE C: Enable system services
# ============================================================================

echo ""
echo "==> Phase C: Enabling system services"

# Now that zsh has been installed by Phase A, switch user shell to zsh
if command -v zsh &>/dev/null; then
    usermod -s "$(command -v zsh)" "${TARGET_USER}" 2>/dev/null \
        && echo "    Shell set to zsh for ${TARGET_USER}." \
        || echo "    [WARN] Could not set zsh shell (non-fatal)"
fi

# Ensure sddm is installed -- check for the systemd service unit file,
# not the binary (which may not be in PATH even when installed).
if [[ ! -f /usr/lib/systemd/system/sddm.service ]]; then
    echo "    [WARN] sddm service not found -- installing now as fallback..."
    pacman -S --noconfirm --needed sddm 2>/dev/null \
        && echo "    sddm installed." \
        || echo "    [WARN] Could not install sddm via pacman"
fi

# Enable display manager and core services
/usr/bin/systemctl enable sddm 2>/dev/null \
    && echo "    sddm enabled." \
    || echo "    [WARN] Could not enable sddm"

/usr/bin/systemctl enable bluetooth 2>/dev/null \
    && echo "    bluetooth enabled." \
    || echo "    [WARN] Could not enable bluetooth (non-fatal)"

/usr/bin/systemctl enable NetworkManager 2>/dev/null \
    && echo "    NetworkManager enabled." \
    || true  # Already enabled in Step 9 -- not critical here

# Set graphical target as default (needed for SDDM to auto-start)
/usr/bin/systemctl set-default graphical.target 2>/dev/null \
    && echo "    Default target set to graphical." \
    || echo "    [WARN] Could not set graphical target"

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
mkdir -p "$HOME/.local/state/hyprflux"
exec 9>"$HOME/.local/state/hyprflux/first-boot.lock"
flock -n 9 || exit 0
exec >>"$HOME/.local/state/hyprflux/first-boot.log" 2>&1
session_pending=0

# Only run once
if [[ -f "$MARKER" ]]; then
    exit 0
fi

# Wait for desktop to initialize
sleep 3

# Apply GTK theme via gsettings
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface gtk-theme "HyprFlux-Compact" || session_pending=1
    gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark" || session_pending=1
    gsettings set org.gnome.desktop.interface cursor-theme "Future-black Cursors" || session_pending=1
    gsettings set org.gnome.desktop.interface cursor-size 24 || session_pending=1
    gsettings set org.gnome.desktop.interface font-name "Adwaita Sans 11" || session_pending=1
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark" || session_pending=1
fi

# Export the gsettings just applied into GTK config files. Do not use -a:
# that restores a prior nwg-look backup, which a fresh installation lacks.
if command -v nwg-look &>/dev/null; then
    nwg-look -x || session_pending=1
fi

# Enable pipewire user services
systemctl --user enable --now pipewire.socket || session_pending=1
systemctl --user enable --now pipewire-pulse.socket || session_pending=1
systemctl --user enable --now wireplumber.service || session_pending=1

# Never compile software or ask for sudo in a graphical autostart process.
if [[ -s /var/log/hyprflux-installer/missing-applications.txt ]]; then
    notify-send "HyprFlux" "Optional apps need attention; see /var/log/hyprflux-installer/missing-applications.txt" 2>/dev/null || true
fi

# Optional application recovery must not prevent session settings completing.
# Do not grant permanent root privileges to make unattended AUR installs work.
if [ "$session_pending" -eq 0 ]; then
    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
    rm -f "$HOME/.config/autostart/hyprflux-first-boot.desktop"
    # Papirus' checkmark uses its neutral text color by default. Keep the
    # packaged theme untouched; use its positive (green) palette in a local copy.
    success_icon="$HOME/.local/share/icons/hyprflux-first-boot-success.svg"
    papirus_icon="/usr/share/icons/Papirus/24x24/actions/dialog-ok-apply.svg"
    notification_icon="dialog-ok-apply"
    if mkdir -p "$(dirname "$success_icon")" && [[ -r "$papirus_icon" ]] \
        && sed 's/class="ColorScheme-Text"/class="ColorScheme-PositiveText"/g' \
            "$papirus_icon" > "$success_icon"; then
        notification_icon="$success_icon"
    fi
    notify-send --icon="$notification_icon" "HyprFlux" "First-boot setup complete!" 2>/dev/null || true
else
    notify-send "HyprFlux" "Session setup will retry next login; see ~/.local/state/hyprflux/first-boot.log" 2>/dev/null || true
fi
FIRSTBOOT_EOF

chmod +x "${TARGET_HOME}/.local/bin/hyprflux-first-boot.sh"
install_waybar_session_service "$TARGET_HOME"

# Hyprland does not process XDG autostart entries by itself. Launch explicitly;
# the script's flock and completion marker make duplicate launches harmless.
if [[ -f "${TARGET_HOME}/.config/hypr/hyprland.lua" ]]; then
    cat >> "${TARGET_HOME}/.config/hypr/hyprland.lua" <<'LUA_EOF'

-- HyprFlux ISO: deferred desktop-session settings
hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/hyprflux-start-waybar.sh")
end)
LUA_EOF
    printf '\nhl.config({ input = { kb_layout = "%s", kb_variant = "%s" } })\n' \
        "$XKB_LAYOUT" "$XKB_VARIANT" >> "${TARGET_HOME}/.config/hypr/hyprland.lua"
fi

# Fix ownership
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config" 2>/dev/null || true
chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local" 2>/dev/null || true

echo "    First-boot fixup created."

# ============================================================================
# CLEANUP
# ============================================================================

echo ""
echo "==> Cleanup"

# Revoke installation-only privileges; no passwordless pacman rule remains.
rm -f /etc/sudoers.d/hyprflux-temp

# Remove shim scripts
rm -f /usr/local/bin/chsh
rm -f /usr/local/bin/gsettings
rm -f /usr/local/bin/nwg-look
rm -f /usr/local/bin/yay-iso
rm -f "${CONFIG_ENV_FILE}"

# Restore original Global_functions.sh if backed up
if [[ -f "${INSTALL_SCRIPTS}/Global_functions.sh.bak" ]]; then
    mv "${INSTALL_SCRIPTS}/Global_functions.sh.bak" "${INSTALL_SCRIPTS}/Global_functions.sh"
fi

# Install logs are intentionally KEPT in ${TARGET_HOME}/HyprFlux/logs/
# (installer/*.log, dotsSetup.log) — they are the debugging trail for
# package/config failures and are also where the ISO wrapper run is
# preserved via the iso-wrapper.log tee from the installer.

echo "    Cleanup complete."

# Enforce postconditions, not the exit status of permissive upstream scripts.
critical_failed=0
pacman -Dk || critical_failed=1
pacman -Qk hyprland sddm pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber sof-firmware networkmanager waybar-git wlogout \
    cliphist kvantum rofi imagemagick swaync wl-clipboard kitty hypridle hyprlock \
    firefox chromium thunar gsettings-desktop-schemas dconf papirus-icon-theme || critical_failed=1
for command in Hyprland kitty rofi waybar wlogout awww-daemon firefox chromium thunar pipewire wireplumber; do
    if ! command -v "$command" >/dev/null; then
        echo "[ERROR] Required desktop command missing: $command"
        critical_failed=1
    fi
done
for config in hypr/hyprland.lua waybar/config waybar/style.css; do
    if [[ ! -s "${TARGET_HOME}/.config/$config" ]]; then
        echo "[ERROR] Required config missing: $config"
        critical_failed=1
    fi
done
/usr/bin/systemctl enable sddm NetworkManager || critical_failed=1
/usr/bin/systemctl set-default graphical.target || critical_failed=1
[[ -L /etc/systemd/system/display-manager.service ]] || critical_failed=1
visudo -c || critical_failed=1
# Hyprland 0.57 requires XDG_RUNTIME_DIR even for config-only checks. Keep the
# private path short enough for its Unix sockets, then remove it on exit.
if ! timeout 60 su - "$TARGET_USER" -s /bin/bash -c \
    'set -euo pipefail
     runtime=$(mktemp -d /tmp/hv.XXXXXX)
     trap '\''rm -rf "$runtime"'\'' EXIT
     XDG_RUNTIME_DIR="$runtime" Hyprland --config "$HOME/.config/hypr/hyprland.lua" --verify-config'; then
    echo '[ERROR] Installed Hyprland rejects the deployed configuration.'
    critical_failed=1
fi
mkdir -p /var/log/hyprflux-installer
printf '%s\n' "${FAILED_COMPONENTS[@]}" > /var/log/hyprflux-installer/failed-components.txt
if (( critical_failed )); then
    echo '[ERROR] Desktop validation failed. Installation is NOT complete.'
    exit 1
fi
if (( ${#FAILED_COMPONENTS[@]} )); then
    printf '[WARN] Components needing attention: %s\n' "${FAILED_COMPONENTS[*]}"
fi

echo ""
echo "============================================"
echo "  HyprFlux chroot wrapper complete!"
echo "============================================"
