# Phase 3: TUI Installer Framework & Branding

## Goal

Create the visual framework for the HyprFlux installer: the large ASCII art banner, the scrolling output area, color scheme, auto-launch mechanism, and the shared library functions used by all installer steps. This is the "chrome" that makes the installer look like Omarchy (reference image).

After this phase, booting the ISO should display the big HyprFlux logo with a status area below it, before handing off to Phase 4's installation logic.

---

## Design: Omarchy-Style TUI Layout

Based on the reference screenshot, the screen is divided into two regions:

```
+----------------------------------------------------------------+
|                                                                |
|  ██╗  ██╗██╗   ██╗██████╗ ██████╗ ███████╗██╗     ██╗   ██╗  |
|  ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗██╔════╝██║     ██║   ██║  |
|  ███████║ ╚████╔╝ ██████╔╝██████╔╝█████╗  ██║     ██║   ██║  |
|  ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗██╔══╝  ██║     ██║   ██║  |
|  ██║  ██║   ██║   ██║     ██║  ██║██║     ███████╗╚██████╔╝  |
|  ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚═╝     ╚══════╝ ╚═════╝  |
|  ██╗  ██╗                                                      |
|  ╚═╝  ╚═╝                                                      |
|                                                                |
|  Installing...                                                 |
|                                                                |
|  > ==> Setting timezone to America/New_York...                 |
|  > ==> Generating locales...                                   |
|  > ==> Creating user account...                                |
|  > ==> Partitioning disk /dev/sda...                           |
|  > ==> Installing base system (pacstrap)...                    |
|  > :: Synchronizing package databases...                       |
|  > :: downloading core.db...                                   |
|                                                                |
+----------------------------------------------------------------+
```

**Layout breakdown:**
- **Top ~40%**: Large green ASCII art logo (centered, static)
- **Status line**: Yellow "Installing..." text (changes to show current phase)
- **Bottom ~50%**: Scrolling output area that shows installation progress (like a log tail)

---

## File List

| # | File | Lines | Description |
|---|------|-------|-------------|
| 1 | `airootfs/root/hyprflux-install.sh` | ~100 (skeleton) | Main installer entry point (skeleton, filled in Phase 4) |
| 2 | `airootfs/root/lib/tui.sh` | ~200 | TUI framework: banner, colors, output area, dialog wrappers |
| 3 | `airootfs/root/lib/common.sh` | ~80 | Shared utilities: logging, error handling, validation |
| 4 | `airootfs/root/.zlogin` | ~10 | Auto-launches installer on tty1 login |
| 5 | `airootfs/etc/motd` | ~20 | Welcome banner (shown if user escapes to shell) |

---

## Detailed Specifications

### 1. TUI Framework: `airootfs/root/lib/tui.sh` (~200 lines)

The core visual engine. Provides functions to:

**a) Display the HyprFlux banner (top of screen)**

```bash
LOGO_COLOR="\033[1;32m"  # Bold green (like Omarchy)
RESET="\033[0m"

show_banner() {
    clear
    echo -e "${LOGO_COLOR}"
    cat << 'BANNER'
    ██╗  ██╗██╗   ██╗██████╗ ██████╗ ███████╗██╗     ██╗   ██╗██╗  ██╗
    ██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗██╔════╝██║     ██║   ██║╚██╗██╔╝
    ███████║ ╚████╔╝ ██████╔╝██████╔╝█████╗  ██║     ██║   ██║ ╚███╔╝
    ██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗██╔══╝  ██║     ██║   ██║ ██╔██╗
    ██║  ██║   ██║   ██║     ██║  ██║██║     ███████╗╚██████╔╝██╔╝ ██╗
    ╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝
BANNER
    echo -e "${RESET}"
}
```

**b) Status line (below banner)**

```bash
STATUS_COLOR="\033[1;33m"  # Bold yellow
ARROW_COLOR="\033[0;36m"   # Cyan

set_status() {
    local msg="$1"
    # Save cursor, move to status line row, clear line, print, restore cursor
    tput sc
    tput cup $STATUS_LINE 0
    tput el
    echo -e "  ${STATUS_COLOR}${msg}${RESET}"
    tput rc
}
```

**c) Scrolling output area**

The output area occupies the bottom portion of the terminal. Installation commands pipe their output here. The approach:

1. After drawing the banner, calculate remaining terminal lines
2. Set up a "scroll region" using ANSI escape sequences so output scrolls only in the bottom area
3. All `log_step` and command output goes to this region

```bash
setup_output_area() {
    local term_lines
    term_lines=$(tput lines)
    
    BANNER_LINES=10        # Logo height
    STATUS_LINE=$((BANNER_LINES + 1))
    OUTPUT_START=$((STATUS_LINE + 2))
    
    # Set scroll region to bottom of screen
    tput csr $OUTPUT_START $((term_lines - 1))
    tput cup $OUTPUT_START 0
}
```

**d) Logging functions (output to scroll area)**

```bash
log_step()  { echo -e "  ${ARROW_COLOR}==>${RESET} $*"; }
log_ok()    { echo -e "  ${GREEN}[OK]${RESET} $*"; }
log_warn()  { echo -e "  ${YELLOW}[WARN]${RESET} $*"; }
log_error() { echo -e "  ${RED}[ERROR]${RESET} $*"; }
log_cmd()   { echo -e "  ${CYAN}>${RESET} $*"; }
```

**e) Run command with live output in scroll area**

```bash
# Runs a command, showing output in the scroll region.
# Usage: run_cmd "Installing packages" pacman -S --noconfirm base
run_cmd() {
    local desc="$1"
    shift
    log_step "$desc"
    "$@" 2>&1 | while IFS= read -r line; do
        echo -e "  ${CYAN}>${RESET} ${line}"
    done
    local status=${PIPESTATUS[0]}
    if [[ $status -eq 0 ]]; then
        log_ok "$desc"
    else
        log_error "$desc (exit code: $status)"
        return $status
    fi
}
```

**f) Dialog wrappers (for interactive prompts)**

When user input is needed, we temporarily leave the scrolling output mode, show a `dialog` box, then restore the banner + output area.

```bash
# Show a dialog menu and return the selection
# Usage: result=$(dlg_menu "Select timezone region" "Africa" "America" "Asia" ...)
dlg_menu() {
    local title="$1"
    shift
    local items=()
    local i=1
    for item in "$@"; do
        items+=("$i" "$item")
        i=$((i + 1))
    done
    
    local choice
    choice=$(dialog --clear --title "$title" \
        --menu "" 20 60 14 "${items[@]}" 2>&1 >/dev/tty)
    
    # Restore banner after dialog clears the screen
    show_banner
    setup_output_area
    
    # Return the actual item (not the number)
    local idx=$((choice - 1))
    echo "${@:$choice:1}"
}

# Yes/No dialog
# Usage: dlg_yesno "Continue with installation?" && do_stuff
dlg_yesno() {
    dialog --clear --title "HyprFlux" --yesno "$1" 8 50
    local result=$?
    show_banner
    setup_output_area
    return $result
}

# Input box
# Usage: hostname=$(dlg_input "Enter hostname" "hyprflux")
dlg_input() {
    local prompt="$1"
    local default="${2:-}"
    local result
    result=$(dialog --clear --title "HyprFlux" \
        --inputbox "$prompt" 8 50 "$default" 2>&1 >/dev/tty)
    show_banner
    setup_output_area
    echo "$result"
}

# Password box (hidden input)
# Usage: password=$(dlg_password "Enter password")
dlg_password() {
    local prompt="$1"
    local result
    result=$(dialog --clear --title "HyprFlux" \
        --passwordbox "$prompt" 8 50 2>&1 >/dev/tty)
    show_banner
    setup_output_area
    echo "$result"
}
```

---

### 2. Common Utilities: `airootfs/root/lib/common.sh` (~80 lines)

Shared functions used throughout the installer.

```bash
#!/bin/bash
# lib/common.sh -- Shared installer utilities

# ====== Error handling ======
die() {
    log_error "$@"
    log_error "Installation failed. Dropping to shell for debugging."
    log_error "You can re-run the installer with: bash ~/hyprflux-install.sh"
    # Reset scroll region so shell works normally
    tput rmcup 2>/dev/null || true
    tput sgr0
    exec /bin/bash
}

# ====== Validation ======
validate_hostname() {
    local name="$1"
    [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,62}$ ]]
}

validate_username() {
    local name="$1"
    [[ "$name" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]
}

# ====== Internet check ======
check_internet() {
    ping -c 1 -W 5 archlinux.org &>/dev/null
}

# ====== Boot mode detection ======
detect_boot_mode() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        echo "uefi"
    else
        echo "bios"
    fi
}

# ====== Disk helpers ======
get_part_prefix() {
    local disk="$1"
    if [[ "$disk" == *nvme* || "$disk" == *mmcblk* ]]; then
        echo "${disk}p"
    else
        echo "${disk}"
    fi
}

# ====== Mount point ======
MOUNT_POINT="/mnt/archinstall"
```

---

### 3. Installer Skeleton: `airootfs/root/hyprflux-install.sh` (~100 lines, skeleton)

This is the entry point. In Phase 3, we create the skeleton that sources libraries and shows the banner. The actual installation steps are added in Phase 4.

```bash
#!/bin/bash
# ============================================================
# hyprflux-install.sh -- HyprFlux Arch Linux Installer
# ============================================================
# TUI installer for HyprFlux (Hyprland desktop on Arch Linux).
# Boots from the live ISO, prompts for configuration, installs
# base Arch, then sets up HyprFlux with all dotfiles and themes.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/tui.sh"
source "${SCRIPT_DIR}/lib/common.sh"

# ====== Initialize TUI ======
show_banner
setup_output_area

set_status "Welcome to HyprFlux Installer"

# Trap errors
trap 'die "An unexpected error occurred on line $LINENO"' ERR

# ====== Step 0: Network ======
# (Phase 4)

# ====== Step 1: Welcome ======
# (Phase 4)

# ====== Steps 2-6: Configuration prompts ======
# (Phase 4)

# ====== Step 7: Disk partitioning ======
# (Phase 4)

# ====== Step 8: Install base system ======
# (Phase 4)

# ====== Step 9: Configure base system ======
# (Phase 4)

# ====== Step 10: Install HyprFlux ======
# (Phase 5)

# ====== Step 11: Cleanup & Reboot ======
# (Phase 5)

set_status "Installation Complete!"
log_ok "HyprFlux has been installed successfully."
log_ok "Remove the USB drive and reboot to start using HyprFlux."
```

---

### 4. Auto-Launch: `airootfs/root/.zlogin` (~10 lines)

Automatically starts the installer when root logs in on tty1 (which happens automatically via the autologin.conf from Phase 1).

```bash
# .zlogin -- Auto-launch HyprFlux installer on tty1
# Only launch on tty1 (not if user opens another tty for debugging)
if [[ "$(tty)" == "/dev/tty1" ]]; then
    # Wait a moment for the terminal to fully initialize
    sleep 1
    
    # Launch installer (if user exits, they get a shell)
    bash ~/hyprflux-install.sh || true
    
    echo ""
    echo "Installer exited. You are now in a root shell."
    echo "To re-run the installer: bash ~/hyprflux-install.sh"
fi
```

---

### 5. Message of the Day: `airootfs/etc/motd` (~20 lines)

Shown when user logs in (before .zlogin runs) or if they switch to tty2.

```
===================================================
      HyprFlux -- Arch Linux Installer
===================================================

  The installer will start automatically on tty1.
  
  If you need a shell for debugging:
    - Press Ctrl+Alt+F2 for tty2
    - Login as root (no password)
  
  To manually start the installer:
    bash ~/hyprflux-install.sh

  Network: NetworkManager is available (nmcli/nmtui)
  Docs: https://github.com/ahmad9059/HyprFlux

===================================================
```

---

## Color Scheme

Matching the Omarchy reference screenshot (dark background, green logo):

| Element | Color | ANSI Code |
|---------|-------|-----------|
| Logo | Bold green | `\033[1;32m` |
| Status line | Bold yellow | `\033[1;33m` |
| Step arrows `==>` | Cyan | `\033[0;36m` |
| OK messages | Green | `\033[0;32m` |
| Warnings | Yellow | `\033[0;33m` |
| Errors | Bold red | `\033[1;31m` |
| Command output `>` | Dim cyan | `\033[0;36m` |
| Reset | - | `\033[0m` |

---

## Terminal Size Handling

The installer should handle different terminal sizes gracefully:

- **Minimum**: 80x24 (standard VGA text mode)
- **Recommended**: 80x40+ (most modern systems)
- Check terminal size on startup, warn if too small
- The banner is ~7 lines tall + padding = ~10 lines for the logo area
- Status line = 1 line
- Remaining lines = scrolling output area (minimum 12 lines at 80x24)

```bash
check_terminal_size() {
    local cols=$(tput cols)
    local lines=$(tput lines)
    if [[ $cols -lt 80 || $lines -lt 24 ]]; then
        echo "WARNING: Terminal is ${cols}x${lines}."
        echo "Recommended minimum: 80x24"
        sleep 2
    fi
}
```

---

## File Permissions

Set in `profiledef.sh` (Phase 1):

```bash
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/hyprflux-install.sh"]="0:0:755"
  ["/root/lib/tui.sh"]="0:0:755"
  ["/root/lib/common.sh"]="0:0:755"
)
```

---

## Directory Structure After Phase 3

```
hyprflux-iso/
├── build.sh
├── profiledef.sh
├── packages.x86_64
├── pacman.conf
├── airootfs/
│   ├── etc/
│   │   ├── hostname
│   │   ├── locale.conf
│   │   ├── locale.gen
│   │   ├── shadow
│   │   ├── motd                                    # << Phase 3
│   │   ├── mkinitcpio.conf.d/archiso.conf
│   │   └── systemd/
│   │       ├── network/20-ethernet.network
│   │       └── system/getty@tty1.service.d/autologin.conf
│   └── root/                                       # << Phase 3
│       ├── .zlogin
│       ├── hyprflux-install.sh                     # (skeleton)
│       └── lib/
│           ├── tui.sh
│           └── common.sh
├── efiboot/ ...
├── grub/ ...
├── syslinux/ ...
└── ...
```

---

## Validation Steps

1. Build ISO: `sudo bash build.sh`
2. Boot in QEMU: `./test-qemu.sh`
3. Should auto-login and display the large green HyprFlux banner
4. Status line should show "Welcome to HyprFlux Installer"
5. Press Ctrl+C -- should drop to shell with re-run instructions
6. Switch to tty2 (Ctrl+Alt+F2) -- should show motd
7. Test terminal resize (QEMU window) -- output area should adapt

---

## Estimated Implementation Time

~1-2 hours (the TUI framework is the most complex part of this phase).

---

## Dependencies

- **Requires Phase 1** (profile, packages) and **Phase 2** (boot configs) to produce a bootable ISO
- **Required by Phase 4** -- all installer steps use the TUI framework functions
