# .zlogin -- Auto-launch HyprFlux installer on tty1
#
# This file is sourced by zsh on login. When root auto-logs in on tty1
# (via the getty autologin drop-in), this launches the TUI installer.
#
# Phase 1: Placeholder -- just prints a message.
# Phase 3+ will replace this with the actual installer launch.

if [[ "$(tty)" == "/dev/tty1" ]]; then
    echo ""
    echo "  HyprFlux Live Environment"
    echo "  ========================="
    echo ""
    echo "  The installer will launch here in a future phase."
    echo "  For now, you have a working live Arch Linux shell."
    echo ""
    echo "  Network: nmtui  |  Disks: lsblk  |  Shell: zsh"
    echo ""
fi
