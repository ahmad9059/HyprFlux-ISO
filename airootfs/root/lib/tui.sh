#!/bin/bash
# ============================================================================
# lib/tui.sh -- HyprFlux TUI Framework
# ============================================================================
# Provides the visual layer for the installer: ASCII banner, colors,
# and simple terminal-based prompts using fzf for selection.
#
# Design: Clean terminal interface
#   - Large green ASCII art logo at top
#   - Yellow status text (current phase)
#   - Simple prompts and fzf menus (no dialog boxes)
# ============================================================================

# Guard against double-sourcing
[[ -n "${_TUI_SH_LOADED:-}" ]] && return 0
_TUI_SH_LOADED=1

# ============================================================================
# Color Definitions
# ============================================================================
BOLD="\033[1m"
RESET="\033[0m"

# Logo / branding
LOGO_COLOR="\033[1;32m"      # Bold green

# Status line
STATUS_COLOR="\033[1;33m"    # Bold yellow

# Log output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[1;31m"
CYAN="\033[0;36m"
ARROW_COLOR="\033[0;36m"     # Cyan arrows for ==>
DIM="\033[2m"
WHITE="\033[1;37m"

# ============================================================================
# ASCII Art Banner
# ============================================================================
show_banner() {
    clear
    local term_cols
    term_cols=$(tput cols 2>/dev/null || echo 80)

    echo -e "${LOGO_COLOR}"

    # The banner is 66 chars wide -- center it
    local banner_width=66
    local pad=$(( (term_cols - banner_width) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    local padding=""
    for ((i = 0; i < pad; i++)); do
        padding+=" "
    done

    # Using printf for consistent centering
    while IFS= read -r line; do
        printf '%s%s\n' "$padding" "$line"
    done << 'BANNER'
██╗  ██╗██╗   ██╗██████╗ ██████╗ ███████╗██╗     ██╗   ██╗██╗  ██╗
██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗██╔════╝██║     ██║   ██║╚██╗██╔╝
███████║ ╚████╔╝ ██████╔╝██████╔╝█████╗  ██║     ██║   ██║ ╚███╔╝ 
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗██╔══╝  ██║     ██║   ██║ ██╔██╗ 
██║  ██║   ██║   ██║     ██║  ██║██║     ███████╗╚██████╔╝██╔╝ ██╗
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝
BANNER

    echo -e "${RESET}"
    echo ""   # Blank line after banner
}

# ============================================================================
# Terminal Size Check
# ============================================================================
check_terminal_size() {
    local cols lines
    cols=$(tput cols 2>/dev/null || echo 80)
    lines=$(tput lines 2>/dev/null || echo 24)

    if [[ $cols -lt 80 || $lines -lt 24 ]]; then
        echo -e "  ${YELLOW}WARNING:${RESET} Terminal is ${cols}x${lines}."
        echo -e "  ${YELLOW}Recommended minimum: 80x24${RESET}"
        sleep 2
    fi
}

# ============================================================================
# Output Area Setup (simplified - no cursor positioning needed)
# ============================================================================
setup_output_area() {
    # No-op for simple terminal mode
    :
}

# ============================================================================
# Status Line
# ============================================================================
set_status() {
    local msg="$1"
    echo ""
    echo -e "  ${STATUS_COLOR}>>> ${msg}${RESET}"
    echo ""
}

# ============================================================================
# Logging Functions
# ============================================================================
log_step() {
    echo -e "  ${ARROW_COLOR}==>${RESET} $*"
}

log_ok() {
    echo -e "  ${GREEN}[OK]${RESET} $*"
}

log_warn() {
    echo -e "  ${YELLOW}[WARN]${RESET} $*"
}

log_error() {
    echo -e "  ${RED}[ERROR]${RESET} $*"
}

log_cmd() {
    echo -e "  ${DIM}>${RESET} $*"
}

log_info() {
    echo -e "  ${DIM}$*${RESET}"
}

# ============================================================================
# Run Command with Live Output
# ============================================================================
run_cmd() {
    local desc="$1"
    shift
    log_step "$desc"

    set +e
    "$@" 2>&1 | while IFS= read -r line; do
        echo -e "  ${DIM}>${RESET} ${line}"
    done
    local status=${PIPESTATUS[0]}
    set -e

    if [[ $status -eq 0 ]]; then
        log_ok "$desc"
    else
        log_error "$desc (exit code: $status)"
        return "$status"
    fi
}

# ============================================================================
# Simple Prompts (no dialog)
# ============================================================================

# --- Menu selection using fzf ---
# Usage: result=$(tui_menu "Select an option:" "item1" "item2" "item3")
# Returns the selected item text
tui_menu() {
    local prompt="$1"
    shift
    local items=("$@")

    echo -e "\n  ${WHITE}${prompt}${RESET}" >&2
    echo "" >&2

    # Use fzf for selection
    local choice
    choice=$(printf '%s\n' "${items[@]}" | fzf --height=15 --reverse --border --prompt="  > " --pointer="→" --color="fg:#d0d0d0,bg:#000000,hl:#5fafff,fg+:#ffffff,bg+:#1a1a2e,hl+:#87d7ff,info:#afaf87,prompt:#ff79c6,pointer:#ff79c6,marker:#87ff00,spinner:#ff79c6,header:#8be9fd" 2>/dev/tty) || {
        return 1
    }

    echo "$choice"
}

# --- Yes/No prompt ---
# Usage: tui_yesno "Continue?" && do_stuff
tui_yesno() {
    local prompt="$1"
    local default="${2:-y}"  # default to yes

    echo "" >&2
    echo -e "  ${WHITE}${prompt}${RESET}" >&2

    local hint
    if [[ "$default" == "y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi

    while true; do
        echo -ne "  ${CYAN}${hint}${RESET} " >&2
        read -r answer < /dev/tty

        # Use default if empty
        [[ -z "$answer" ]] && answer="$default"

        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo -e "  ${YELLOW}Please enter y or n${RESET}" >&2 ;;
        esac
    done
}

# --- Text input ---
# Usage: hostname=$(tui_input "Enter hostname" "hyprflux")
tui_input() {
    local prompt="$1"
    local default="${2:-}"

    echo "" >&2
    echo -e "  ${WHITE}${prompt}${RESET}" >&2

    local hint=""
    [[ -n "$default" ]] && hint=" (default: ${default})"

    echo -ne "  ${CYAN}>${RESET}${hint} " >&2
    local result
    read -r result < /dev/tty

    # Use default if empty
    [[ -z "$result" ]] && result="$default"

    echo "$result"
}

# --- Password input (hidden) ---
# Usage: password=$(tui_password "Enter password")
tui_password() {
    local prompt="$1"

    echo "" >&2
    echo -e "  ${WHITE}${prompt}${RESET}" >&2
    echo -ne "  ${CYAN}>${RESET} " >&2

    local result
    read -rs result < /dev/tty
    echo "" >&2  # newline after hidden input

    echo "$result"
}

# --- Message box (just press Enter to continue) ---
# Usage: tui_msg "Installation complete!"
tui_msg() {
    local msg="$1"
    echo "" >&2
    echo -e "  ${WHITE}${msg}${RESET}" >&2
    echo "" >&2
    echo -ne "  ${DIM}Press Enter to continue...${RESET}" >&2
    read -r < /dev/tty
}

# --- Error message ---
# Usage: tui_error "Something went wrong"
tui_error() {
    local msg="$1"
    echo "" >&2
    echo -e "  ${RED}ERROR: ${msg}${RESET}" >&2
    echo "" >&2
    echo -ne "  ${DIM}Press Enter to continue...${RESET}" >&2
    read -r < /dev/tty
}

# --- Search/filter list using fzf ---
# Usage: choice=$(printf '%s\n' "${items[@]}" | tui_search "Select item")
tui_search() {
    local prompt="$1"

    echo -e "\n  ${WHITE}${prompt}${RESET}" >&2
    echo -e "  ${DIM}Type to filter, arrow keys to navigate, Enter to select${RESET}" >&2
    echo "" >&2

    local result
    result=$(fzf --height=20 --reverse --border --prompt="  > " --pointer="→" --color="fg:#d0d0d0,bg:#000000,hl:#5fafff,fg+:#ffffff,bg+:#1a1a2e,hl+:#87d7ff,info:#afaf87,prompt:#ff79c6,pointer:#ff79c6,marker:#87ff00,spinner:#ff79c6,header:#8be9fd" 2>/dev/tty) || {
        return 1
    }

    echo "$result"
}

# --- Multi-select using fzf ---
# Usage: selected=$(printf '%s\n' "${items[@]}" | tui_multiselect "Select packages")
tui_multiselect() {
    local prompt="$1"

    echo -e "\n  ${WHITE}${prompt}${RESET}" >&2
    echo -e "  ${DIM}Tab to select/deselect, Enter to confirm${RESET}" >&2
    echo "" >&2

    local result
    result=$(fzf --multi --height=20 --reverse --border --prompt="  > " --pointer="→" --marker="✓" --color="fg:#d0d0d0,bg:#000000,hl:#5fafff,fg+:#ffffff,bg+:#1a1a2e,hl+:#87d7ff,info:#afaf87,prompt:#ff79c6,pointer:#ff79c6,marker:#87ff00,spinner:#ff79c6,header:#8be9fd" 2>/dev/tty) || {
        return 1
    }

    echo "$result"
}

# ============================================================================
# Backward compatibility aliases (for existing code)
# ============================================================================
dlg_menu() {
    local title="$1"
    shift
    tui_menu "$title" "$@"
}

dlg_yesno() {
    tui_yesno "$1"
}

dlg_input() {
    tui_input "$1" "${2:-}"
}

dlg_password() {
    tui_password "$1"
}

dlg_msgbox() {
    tui_msg "$1"
}

dlg_search() {
    tui_search "$1"
}

dlg_checklist() {
    local title="$1"
    shift
    # Convert old format to simple list
    local items=()
    while [[ $# -ge 2 ]]; do
        items+=("$1")
        shift 2
    done
    printf '%s\n' "${items[@]}" | tui_multiselect "$title"
}

dlg_radiolist() {
    local title="$1"
    shift
    # Convert old format to simple list
    local items=()
    while [[ $# -ge 2 ]]; do
        items+=("$1")
        shift 2
    done
    tui_menu "$title" "${items[@]}"
}
