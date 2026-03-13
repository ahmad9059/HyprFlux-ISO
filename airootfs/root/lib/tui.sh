#!/bin/bash
# ============================================================================
# lib/tui.sh -- HyprFlux TUI Framework (Omarchy-style centered layout)
# ============================================================================
# Every screen: clear -> draw banner -> show content below it.
# All text and gum prompts are indented by $PAD (spaces) to align with
# the banner's left edge.
#
# Cursor is HIDDEN by default. Only shown when gum prompts need input.
# This prevents the blinking cursor at column 0 on status screens.
#
# Long operations (pacstrap, git clone): output goes to a log file.
# A background monitor periodically redraws the ENTIRE screen (banner +
# status + last N log lines). No cursor save/restore -- just full redraws.
# This eliminates flashing/blinking artifacts completely.
# ============================================================================

[[ -n "${_TUI_SH_LOADED:-}" ]] && return 0
_TUI_SH_LOADED=1

# ============================================================================
# ANSI
# ============================================================================
readonly ANSI_CLEAR_SCREEN=$'\033[H\033[2J'
readonly ANSI_HIDE_CURSOR=$'\033[?25l'
readonly ANSI_SHOW_CURSOR=$'\033[?25h'

# ============================================================================
# Colors
# ============================================================================
readonly BOLD=$'\033[1m'
readonly RESET=$'\033[0m'
readonly LOGO_COLOR=$'\033[1;32m'
readonly SEPARATOR_COLOR=$'\033[1;31m'
readonly WELCOME_COLOR=$'\033[0;36m'
readonly STATUS_COLOR=$'\033[1;33m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[0;33m'
readonly RED=$'\033[1;31m'
readonly CYAN=$'\033[0;36m'
readonly DIM=$'\033[2m'
readonly GRAY=$'\033[90m'
readonly WHITE=$'\033[1;37m'

# ============================================================================
# Layout
# ============================================================================
TERM_WIDTH=0
TERM_HEIGHT=0
PADDING_LEFT=0
PAD=""

# The banner is exactly 66 display-columns wide.
readonly LOGO_DISPLAY_WIDTH=66

_compute_layout() {
  local size
  size=$(stty size 2>/dev/null </dev/tty) || size="40 120"
  TERM_HEIGHT=${size%% *}
  TERM_WIDTH=${size##* }
  : "${TERM_WIDTH:=120}"
  : "${TERM_HEIGHT:=40}"

  PADDING_LEFT=$(( (TERM_WIDTH - LOGO_DISPLAY_WIDTH) / 2 ))
  (( PADDING_LEFT < 0 )) && PADDING_LEFT=0
  PAD=$(printf "%*s" "$PADDING_LEFT" "")
}

# ============================================================================
# Terminal Size Check
# ============================================================================
check_terminal_size() {
  _compute_layout
  if (( TERM_WIDTH < 80 || TERM_HEIGHT < 24 )); then
    printf '%s%sWARNING: Terminal is %sx%s. Recommended: 80x24%s\n' "$PAD" "${YELLOW}" "${TERM_WIDTH}" "${TERM_HEIGHT}" "${RESET}" >&2
    sleep 2
  fi
}

# ============================================================================
# Banner Lines (pre-built for fast redraw)
# ============================================================================
_BANNER_CACHE=""

_build_banner_cache() {
  _compute_layout
  local buf=""
  buf+=$'\n'

  # Logo
  buf+="${LOGO_COLOR}"
  while IFS= read -r line; do
    buf+="${PAD}${line}"$'\n'
  done <<'LOGO'
██╗  ██╗██╗   ██╗██████╗ ██████╗ ███████╗██╗     ██╗   ██╗██╗  ██╗
██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗██╔════╝██║     ██║   ██║╚██╗██╔╝
███████║ ╚████╔╝ ██████╔╝██████╔╝█████╗  ██║     ██║   ██║ ╚███╔╝ 
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗██╔══╝  ██║     ██║   ██║ ██╔██╗ 
██║  ██║   ██║   ██║     ██║  ██║██║     ███████╗╚██████╔╝██╔╝ ██╗
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚═╝     ╚══════╝ ╚═════╝ ╚═╝  ╚═╝
LOGO
  buf+="${RESET}"

  # Separator
  local name="ahmad9059"
  local dashes=$(( LOGO_DISPLAY_WIDTH - 2 - ${#name} ))
  local left=$(( dashes / 2 ))
  local right=$(( dashes - left ))
  buf+="${PAD}${SEPARATOR_COLOR}✻"
  local i
  for (( i = 0; i < left; i++ )); do buf+="─"; done
  buf+="${name}"
  for (( i = 0; i < right; i++ )); do buf+="─"; done
  buf+="✻${RESET}"$'\n'

  # Welcome
  local welcome="Welcome to HyprFlux! lets begin Installation"
  local wpad=$(( (LOGO_DISPLAY_WIDTH - ${#welcome}) / 2 ))
  (( wpad < 0 )) && wpad=0
  local wpad_str
  wpad_str=$(printf "%*s" "$wpad" "")
  buf+="${PAD}${WELCOME_COLOR}${wpad_str}${welcome}${RESET}"$'\n'
  buf+=$'\n'

  _BANNER_CACHE="$buf"
}

# ============================================================================
# Show Banner (clear + centered logo + separator + welcome)
# Cursor is HIDDEN after this call. Interactive prompts re-show it.
# ============================================================================
show_banner() {
  _compute_layout
  if [[ -z "$_BANNER_CACHE" ]]; then
    _build_banner_cache
  fi
  printf '%s' "${ANSI_HIDE_CURSOR}"
  printf '%s' "${ANSI_CLEAR_SCREEN}"
  printf '%s' "$_BANNER_CACHE"
}

# ============================================================================
# Status Line (below banner, centered)
# ============================================================================
set_status() {
  printf '%s%s%s%s\n\n' "$PAD" "${STATUS_COLOR}" "$1" "${RESET}"
}

# ============================================================================
# Centered Text
# ============================================================================
tui_print() {
  printf '%s%s\n' "$PAD" "$*"
}

tui_print_bold() {
  printf '%s%s%s%s\n' "$PAD" "${WHITE}" "$*" "${RESET}"
}

# ============================================================================
# Logging (centered with $PAD) -- for non-progress screens
# ============================================================================
log_step() { printf '%s%s==>%s %s\n' "$PAD" "${CYAN}" "${RESET}" "$*"; }
log_ok()   { printf '%s%s[OK]%s %s\n' "$PAD" "${GREEN}" "${RESET}" "$*"; }
log_warn() { printf '%s%s[WARN]%s %s\n' "$PAD" "${YELLOW}" "${RESET}" "$*"; }
log_error(){ printf '%s%s[ERROR]%s %s\n' "$PAD" "${RED}" "${RESET}" "$*"; }
log_cmd()  { printf '%s%s  → %s%s\n' "$PAD" "${GRAY}" "$*" "${RESET}"; }
log_info() { printf '%s%s%s%s\n' "$PAD" "${DIM}" "$*" "${RESET}"; }

# ============================================================================
# Inline Spinner -- for short blocking operations
#
# Usage: tui_spinner "Checking network..." command [args...]
#
# Shows:  <PAD> ⠹ Checking network...  (animated)
# Then:   <PAD> [OK] Checking network...  or  <PAD> [FAIL] ...
#
# The spinner runs in the foreground using a background command.
# Cursor stays hidden throughout.
# ============================================================================
tui_spinner() {
  local msg="$1"; shift

  # ASCII spinner -- avoids UTF-8 issues in early console
  local -a spin=('/' '-' '\' '|')
  local spin_idx=0

  # Run command in background
  "$@" &>/dev/null &
  local cmd_pid=$!

  # Animate spinner while command runs
  while kill -0 "$cmd_pid" 2>/dev/null; do
    local frame="${spin[$spin_idx]}"
    spin_idx=$(( (spin_idx + 1) % ${#spin[@]} ))
    printf '\r%s%s[%s] %s%s' "$PAD" "${STATUS_COLOR}" "$frame" "$msg" "${RESET}"
    sleep 0.1
  done

  # Get exit code
  local rc=0
  wait "$cmd_pid" || rc=$?

  # Clear spinner line and show result
  printf '\r%s\r' "$(printf '%*s' "$TERM_WIDTH" "")"
  if [[ $rc -eq 0 ]]; then
    log_ok "$msg"
  else
    log_error "$msg"
  fi

  return "$rc"
}

# ============================================================================
# Blocking wait with spinner (no command -- just visual delay)
#
# Usage: tui_wait "Waiting for network..." 5
# Shows spinner for N seconds.
# ============================================================================
tui_wait() {
  local msg="$1"
  local secs="${2:-3}"

  # ASCII spinner -- avoids UTF-8 issues in early console
  local -a spin=('/' '-' '\' '|')
  local spin_idx=0
  local end_time=$(( SECONDS + secs ))

  while (( SECONDS < end_time )); do
    local frame="${spin[$spin_idx]}"
    spin_idx=$(( (spin_idx + 1) % ${#spin[@]} ))
    printf '\r%s%s[%s] %s%s' "$PAD" "${STATUS_COLOR}" "$frame" "$msg" "${RESET}"
    sleep 0.1
  done

  # Clear the spinner line
  printf '\r%s\r' "$(printf '%*s' "$TERM_WIDTH" "")"
}

# ============================================================================
# Long Operation Progress Display
#
# How it works:
#   1. Call start_progress "Status message"
#   2. Run your command with output >> "$PROGRESS_LOG" 2>&1
#   3. Call stop_progress
#
# While running, a background process redraws the entire screen every 0.5s:
#   [banner]
#   [status message with spinner]
#   [last N lines of log, truncated to fit]
#
# This uses full-screen redraws (clear + print) instead of cursor
# save/restore, which eliminates all flashing/blinking artifacts.
# The background process is killed cleanly by stop_progress.
# ============================================================================
PROGRESS_LOG=""
_PROGRESS_PID=""
_PROGRESS_STATUS=""

start_progress() {
  local status_msg="${1:-Installing...}"
  _PROGRESS_STATUS="$status_msg"

  # Create log file (fall back to /dev/null if mktemp fails)
  PROGRESS_LOG=$(mktemp /tmp/hyprflux-progress.XXXXXX 2>/dev/null) || PROGRESS_LOG="/dev/null"

  # Ensure banner cache exists
  if [[ -z "$_BANNER_CACHE" ]]; then
    _build_banner_cache
  fi

  # Cursor is already hidden from show_banner, ensure it stays hidden
  printf '%s' "${ANSI_HIDE_CURSOR}"

  # Start background redraw loop
  _progress_loop &
  _PROGRESS_PID=$!
  disown "$_PROGRESS_PID" 2>/dev/null || true
}

_progress_loop() {
  local max_lines
  # Reserve lines for: banner(~11) + status(2) + padding(2) = ~15 lines overhead
  max_lines=$(( TERM_HEIGHT - 15 ))
  (( max_lines < 5 )) && max_lines=5
  (( max_lines > 25 )) && max_lines=25

  # Available width for the log text itself:
  #   total line = PAD + "  → " + text + RESET
  #   PAD = PADDING_LEFT chars, "  → " = 4 chars, leave 2 char margin
  local max_w=$(( TERM_WIDTH - PADDING_LEFT - 6 ))
  (( max_w < 20 )) && max_w=20

  # Spinner frames -- simple ASCII to avoid UTF-8 issues in early console
  local -a spin=('/' '-' '\' '|')
  local spin_idx=0

  while true; do
    # Clear screen and print banner (cursor already hidden)
    printf '%s' "${ANSI_CLEAR_SCREEN}"
    printf '%s' "$_BANNER_CACHE"

    # Status line with spinner
    local frame="${spin[$spin_idx]}"
    spin_idx=$(( (spin_idx + 1) % ${#spin[@]} ))
    printf '%s%s[%s] %s%s\n\n' "$PAD" "${STATUS_COLOR}" "$frame" "$_PROGRESS_STATUS" "${RESET}"

    # Last N lines of log
    if [[ -f "$PROGRESS_LOG" ]]; then
      local raw_lines
      raw_lines=$(tail -n "$max_lines" "$PROGRESS_LOG" 2>/dev/null) || raw_lines=""
      if [[ -n "$raw_lines" ]]; then
        while IFS= read -r line; do
          # Strip ALL ANSI escape sequences and carriage returns.
          # Use tr to delete \r, then sed with a character class to match ESC[...X
          # The ESC byte is \033 (octal).  We match ESC followed by [ or ( then
          # any number of parameter bytes (0-9 ; ? space) then a letter.
          # Using separate commands avoids sed BRE escaping pitfalls.
          local clean
          clean=$(printf '%s' "$line" | tr -d '\r' | sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b([0-9;?]*[a-zA-Z]//g; s/\x1b[=>]//g')
          # Skip empty/whitespace-only lines
          [[ -z "${clean// /}" ]] && continue
          # Hard truncate to max_w characters
          if (( ${#clean} > max_w )); then
            clean="${clean:0:$(( max_w - 1 ))}~"
          fi
          printf '%s%s  > %s%s\n' "$PAD" "${GRAY}" "$clean" "${RESET}"
        done <<< "$raw_lines"
      fi
    fi

    sleep 0.5
  done
}

stop_progress() {
  # Kill the background redraw loop
  if [[ -n "$_PROGRESS_PID" ]]; then
    kill "$_PROGRESS_PID" 2>/dev/null || true
    wait "$_PROGRESS_PID" 2>/dev/null || true
    _PROGRESS_PID=""
  fi

  # Clean up log file
  if [[ -n "$PROGRESS_LOG" && -f "$PROGRESS_LOG" ]]; then
    rm -f "$PROGRESS_LOG"
  fi
  PROGRESS_LOG=""
  _PROGRESS_STATUS=""

  # Keep cursor hidden -- show_banner hides it, interactive prompts show it
}

# ============================================================================
# Run a command with progress display
# Usage: run_with_progress "Status message" command [args...]
# ============================================================================
run_with_progress() {
  local status_msg="$1"; shift

  start_progress "$status_msg"

  local rc=0
  "$@" >> "$PROGRESS_LOG" 2>&1 || rc=$?

  stop_progress

  return "$rc"
}

# ============================================================================
# Simple command runner (no progress display -- for quick operations)
# ============================================================================
run_cmd() {
  local desc="$1"; shift
  log_step "$desc"
  local rc=0
  "$@" 2>&1 | while IFS= read -r line; do log_cmd "$line"; done
  rc=${PIPESTATUS[0]}
  if [[ $rc -eq 0 ]]; then
    log_ok "$desc"
  else
    log_error "$desc (exit: $rc)"
    return "$rc"
  fi
}

# ============================================================================
# Interactive Prompts (gum-based)
#
# CENTERING STRATEGY: gum's --padding adds internal whitespace inside the
# widget but does NOT shift the widget itself to the right. Instead, we
# prefix the --prompt string with "$PAD" (spaces) so gum renders the
# prompt text starting at the correct column.
#
# CURSOR: All interactive prompts show the cursor before invoking gum,
# then hide it again after. This ensures the cursor is only visible
# when the user needs to type.
# ============================================================================

# --- Menu (gum choose) ---
tui_menu() {
  local prompt="$1"; shift
  local items=("$@")

  printf '%s' "${ANSI_SHOW_CURSOR}" >/dev/tty
  local choice
  choice=$(printf '%s\n' "${items[@]}" | gum choose \
    --header="${PAD}${prompt}" \
    --header.foreground="255" \
    --cursor="${PAD}→ " \
    --cursor.foreground="212" \
    --selected.foreground="212" \
    --unselected-prefix="${PAD}  " \
    --height=15 \
    --no-show-help \
    2>/dev/tty) || { printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty; return 1; }
  printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty
  printf '%s' "$choice"
}

# --- Yes/No (gum choose with Yes/No) ---
# gum confirm renders buttons and hint at column 0 with no way to indent.
# We use gum choose instead, which supports --cursor and --unselected-prefix.
tui_yesno() {
  local prompt="$1"
  local default="${2:-y}"

  local items=("Yes" "No")
  [[ "$default" != "y" ]] && items=("No" "Yes")

  printf '%s' "${ANSI_SHOW_CURSOR}" >/dev/tty
  local choice
  choice=$(printf '%s\n' "${items[@]}" | gum choose \
    --header="${PAD}${prompt}" \
    --header.foreground="255" \
    --cursor="${PAD}→ " \
    --cursor.foreground="212" \
    --selected.foreground="212" \
    --unselected-prefix="${PAD}  " \
    --height=4 \
    --no-show-help \
    2>/dev/tty) || { printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty; return 1; }
  printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty

  [[ "$choice" == "Yes" ]]
}

# --- Text Input (gum input) ---
# Default is shown as placeholder (greyed hint). Field starts empty.
# If user submits empty, we return the default value.
tui_input() {
  local label="$1"
  local default="${2:-}"

  local args=(
    --prompt="${PAD}${label}> "
    --prompt.foreground="212"
    --cursor.foreground="212"
    --width="$LOGO_DISPLAY_WIDTH"
    --no-show-help
  )
  [[ -n "$default" ]] && args+=(--placeholder="$default")

  printf '%s' "${ANSI_SHOW_CURSOR}" >/dev/tty
  local result
  result=$(gum input "${args[@]}" 2>/dev/tty) || {
    printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty
    printf '%s' "$default"
    return 0
  }
  printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty

  # If user submitted empty, use the default
  if [[ -z "$result" && -n "$default" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$result"
  fi
}

# --- Password (gum input --password) ---
tui_password() {
  local label="$1"

  printf '%s' "${ANSI_SHOW_CURSOR}" >/dev/tty
  local result
  result=$(gum input \
    --password \
    --prompt="${PAD}${label}> " \
    --prompt.foreground="212" \
    --cursor.foreground="212" \
    --width="$LOGO_DISPLAY_WIDTH" \
    --no-show-help \
    2>/dev/tty) || { printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty; return 1; }
  printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty
  printf '%s' "$result"
}

# --- Search / Filter (gum filter) ---
tui_search() {
  local label="$1"

  printf '%s' "${ANSI_SHOW_CURSOR}" >/dev/tty
  local result
  result=$(gum filter \
    --prompt="${PAD}${label}> " \
    --prompt.foreground="212" \
    --indicator=" ${PAD}•" \
    --indicator.foreground="212" \
    --match.foreground="212" \
    --cursor-text.foreground="255" \
    --height=20 \
    --no-show-help \
    --placeholder="type to search..." \
    2>/dev/tty) || { printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty; return 1; }
  printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty
  printf '%s' "$result"
}

# --- Multi-select (gum choose --no-limit) ---
tui_multiselect() {
  local prompt="$1"

  printf '%s' "${ANSI_SHOW_CURSOR}" >/dev/tty
  local result
  result=$(gum choose --no-limit \
    --header="${PAD}${prompt}" \
    --header.foreground="255" \
    --cursor="${PAD}→ " \
    --cursor.foreground="212" \
    --selected.foreground="212" \
    --unselected-prefix="${PAD}  " \
    --height=20 \
    --no-show-help \
    2>/dev/tty) || { printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty; return 1; }
  printf '%s' "${ANSI_HIDE_CURSOR}" >/dev/tty
  printf '%s' "$result"
}

# --- Message box ---
tui_msg() {
  echo "" >&2
  printf '%s%s%s%s\n\n' "$PAD" "${WHITE}" "$1" "${RESET}" >&2
  printf '%s%sPress Enter to continue...%s' "$PAD" "${DIM}" "${RESET}" >&2
  printf '%s' "${ANSI_SHOW_CURSOR}"
  read -r </dev/tty
  printf '%s' "${ANSI_HIDE_CURSOR}"
}

# --- Error message ---
tui_error() {
  echo "" >&2
  printf '%s%sERROR: %s%s\n\n' "$PAD" "${RED}" "$1" "${RESET}" >&2
  printf '%s%sPress Enter to continue...%s' "$PAD" "${DIM}" "${RESET}" >&2
  printf '%s' "${ANSI_SHOW_CURSOR}"
  read -r </dev/tty
  printf '%s' "${ANSI_HIDE_CURSOR}"
}

# --- Styled boxes (gum style with --margin for indent) ---
tui_success_box() {
  echo "" >&2
  gum style --foreground="10" --border="rounded" --border-foreground="10" \
    --padding="1 3" --margin="0 0 0 $PADDING_LEFT" "$1" >&2
  echo "" >&2
}

tui_warning_box() {
  echo "" >&2
  gum style --foreground="11" --border="rounded" --border-foreground="11" \
    --padding="1 3" --margin="0 0 0 $PADDING_LEFT" "$1" >&2
  echo "" >&2
}

tui_info_box() {
  echo "" >&2
  gum style --foreground="14" --border="rounded" --border-foreground="14" \
    --padding="1 3" --margin="0 0 0 $PADDING_LEFT" "$1" >&2
  echo "" >&2
}

# ============================================================================
# Cleanup
# ============================================================================
_tui_cleanup() {
  # Kill progress monitor if running
  if [[ -n "${_PROGRESS_PID:-}" ]]; then
    kill "$_PROGRESS_PID" 2>/dev/null || true
    wait "$_PROGRESS_PID" 2>/dev/null || true
  fi
  [[ -n "${PROGRESS_LOG:-}" ]] && rm -f "$PROGRESS_LOG" 2>/dev/null
  printf '%s' "${ANSI_SHOW_CURSOR}" 2>/dev/null || true
}
trap _tui_cleanup EXIT

# ============================================================================
# Backward Compatibility Aliases
# ============================================================================
setup_output_area() { :; }
dlg_menu()     { local t="$1"; shift; tui_menu "$t" "$@"; }
dlg_yesno()    { tui_yesno "$1"; }
dlg_input()    { tui_input "$1" "${2:-}"; }
dlg_password() { tui_password "$1"; }
dlg_msgbox()   { tui_msg "$1"; }
dlg_search()   { tui_search "$1"; }

dlg_checklist() {
  local t="$1"; shift; local items=()
  while [[ $# -ge 2 ]]; do items+=("$1"); shift 2; done
  printf '%s\n' "${items[@]}" | tui_multiselect "$t"
}

dlg_radiolist() {
  local t="$1"; shift; local items=()
  while [[ $# -ge 2 ]]; do items+=("$1"); shift 2; done
  tui_menu "$t" "${items[@]}"
}
