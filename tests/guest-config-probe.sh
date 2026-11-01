#!/bin/bash
# Validate the pinned source against the guest's installed Hyprland version.
# Uses an isolated temporary HOME, not the real user's desktop configuration.
set -euo pipefail
[[ $(systemd-detect-virt) == kvm || $(systemd-detect-virt) == qemu ]] || exit 90
grep -q 'hyprflux.test=1' /proc/cmdline || exit 91
mountpoint -q /mnt/archinstall || exit 92
exec >/dev/ttyS0 2>&1
printf '\n=== HYPRFLUX ISOLATED CONFIG PROBE BEGIN ===\n'
# The active installation already provides the chroot mounts. Do not invoke
# arch-chroot concurrently: remounting its /tmp could disturb package builds.
result=0
chroot /mnt/archinstall /usr/bin/su - fluxcheck -s /bin/bash -c '
    set -euo pipefail
    tmp=$(mktemp -d /tmp/hyprflux-config-probe.XXXXXX)
    runtime=$(mktemp -d /tmp/hv.XXXXXX)
    trap '\''rm -rf "$tmp" "$runtime"'\'' EXIT
    cp -a "$HOME/HyprFlux/.config" "$tmp/.config"
    Hyprland --version
    HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" XDG_RUNTIME_DIR="$runtime" \
        Hyprland --config "$tmp/.config/hypr/hyprland.lua" --verify-config
' || result=$?
printf 'HYPRFLUX_CONFIG_PROBE_RESULT=%s\n' "$result"
printf '=== HYPRFLUX ISOLATED CONFIG PROBE END ===\n'
exit "$result"
