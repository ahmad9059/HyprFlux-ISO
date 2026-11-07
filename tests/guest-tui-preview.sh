#!/bin/bash
# Isolated source/embedded UI preview, never an installation acceptance result.
set -euo pipefail
[[ $(systemd-detect-virt) == qemu || $(systemd-detect-virt) == kvm ]]
chvt 1
setsid bash -c '
    exec </dev/tty1 >/dev/tty1 2>&1
    if [[ "${HYPRFLUX_TEST_EMBEDDED:-0}" == 1 ]]; then
        source /root/lib/tui.sh
    else
        source /run/hyprflux-source/airootfs/root/lib/tui.sh
    fi
    INSTALL_LOG_DIR=/run/hyprflux-ui-preview
    start_progress "Installing HyprFlux — UI preview only"
    for line in \
        "Preview only: this VM is not being installed." \
        "==> Configuring base system" \
        "==> Generating en_US.UTF-8 locale" \
        "==> Installing desktop packages" \
        "==> Configuring Hyprland and Waybar" \
        "==> Preserving stage logs for diagnostics"; do
        printf "%s\n" "$line" >> "$PROGRESS_LOG"
    done
    sleep 2
    touch /run/hyprflux-ui-preview-ready
    sleep 60
' &
preview_pid=$!
trap 'kill "$preview_pid" 2>/dev/null || true; wait "$preview_pid" 2>/dev/null || true' EXIT
for ((attempt=0; attempt<100; attempt++)); do
    if [[ -e /run/hyprflux-ui-preview-ready ]]; then
        echo HYPRFLUX_TUI_PREVIEW_READY
        wait "$preview_pid"
        exit 0
    fi
    kill -0 "$preview_pid"
    sleep .1
done
echo 'HYPRFLUX_TEST_FAILED UI preview did not render'
exit 1
