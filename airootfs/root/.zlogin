# .zlogin -- Auto-launch HyprFlux installer on tty1 (and serial console)
#
# This file is sourced by zsh on login. When root auto-logs in on tty1
# (via the getty autologin drop-in) or on the serial console ttyS0
# (serial-getty autologin drop-in), this launches the TUI installer.
#
# A lock file guarantees only ONE installer instance runs, even if both
# consoles are connected at the same time. Other TTYs (Ctrl+Alt+F2, etc.)
# get a plain shell for debugging.

if [[ "$(tty)" == "/dev/tty1" || "$(tty)" == "/dev/ttyS0" ]]; then
    # Brief pause for terminal to fully initialize
    sleep 1

    # Single-instance lock: the second console reports and stays idle.
    exec 9>/tmp/hyprflux-installer.lock
    if ! flock -n 9; then
        printf '\nHyprFlux installer is already running on another console.\n'
        return
    fi

    # Launch installer -- if it exits (Ctrl+C or error), user gets a shell
    bash ~/hyprflux-install.sh || true

    # Center exit message to match the TUI layout
    _tw=$(stty size 2>/dev/null </dev/tty | awk '{print $2}')
    : "${_tw:=120}"
    _pad=$(printf "%*s" "$(( (_tw - 66) / 2 ))" "")

    printf '\n'
    printf '%s\033[?25h' ''  # Show cursor
    printf '%s%s\n' "$_pad" "Installer exited. You are now in a root shell."
    printf '%s%s\n' "$_pad" "To re-run: bash ~/hyprflux-install.sh"
    printf '\n'
fi