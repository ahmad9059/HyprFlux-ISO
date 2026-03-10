# .zlogin -- Auto-launch HyprFlux installer on tty1
#
# This file is sourced by zsh on login. When root auto-logs in on tty1
# (via the getty autologin drop-in), this launches the TUI installer.
#
# Only tty1 gets the installer. Other TTYs (Ctrl+Alt+F2, etc.) get a
# plain shell for debugging.

if [[ "$(tty)" == "/dev/tty1" ]]; then
    # Brief pause for terminal to fully initialize
    sleep 1

    # Launch installer -- if it exits (Ctrl+C or error), user gets a shell
    bash ~/hyprflux-install.sh || true

    echo ""
    echo "  Installer exited. You are now in a root shell."
    echo "  To re-run: bash ~/hyprflux-install.sh"
    echo ""
fi
