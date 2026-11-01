#!/bin/bash
# Read-only diagnostics for this harness's disposable live VM.
set -uo pipefail
[[ $(systemd-detect-virt) == kvm || $(systemd-detect-virt) == qemu ]] || exit 90
grep -q 'hyprflux.test=1' /proc/cmdline || exit 91
mountpoint -q /mnt/archinstall || exit 92
exec >/dev/ttyS0 2>&1
printf '\n=== HYPRFLUX READ-ONLY DIAGNOSTICS BEGIN ===\n'
date -u
df -h /mnt/archinstall /tmp
free -m
ps -eo user,pid,etime,args | grep -E 'pacman|makepkg|yay|paru|hyprflux-chroot-wrapper' | grep -v grep || true
for log in /mnt/archinstall/home/fluxcheck/HyprFlux/logs/installer/*hypr-pkgs.log; do
    [[ -f "$log" ]] || continue
    printf '\n--- %s: recent errors ---\n' "$log"
    grep -Ein 'error:|failed|not found|conflict|broken|timeout' "$log" | tail -35 || true
    printf '\n--- latest package log output ---\n'
    tail -25 "$log"
done
printf '\n=== HYPRFLUX READ-ONLY DIAGNOSTICS END ===\n'
