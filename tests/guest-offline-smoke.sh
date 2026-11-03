#!/bin/bash
# Disposable live VM only. Test boot/keyring without network, never partition.
set -euo pipefail
[[ $(systemd-detect-virt) == qemu || $(systemd-detect-virt) == kvm ]]
source /root/hyprflux-install.sh
if check_internet; then
    echo 'HYPRFLUX_TEST_FAILED offline-fixture-has-network'
    exit 1
fi
timeout --kill-after=5s 125 systemctl start pacman-init.service
[[ $(systemctl is-active pacman-init.service) == active ]]
echo 'HYPRFLUX_OFFLINE_LIVE_PASS: offline shell reachable; keyring did not wait for NTP'
scratch=$(mktemp -d /tmp/hyprflux-space-test.XXXXXX)
cleanup() {
    if mountpoint -q "$scratch/root"; then umount "$scratch/root"; fi
    rm -rf -- "$scratch"
}
trap cleanup EXIT
mkdir "$scratch/root"
truncate -s 64M "$scratch/root.ext4"
mkfs.ext4 -q "$scratch/root.ext4"
mount -o loop "$scratch/root.ext4" "$scratch/root"
MOUNT_POINT="$scratch/root"
INSTALL_BOOT_MODE=bios
INSTALL_PROFILE=desktop
# Only the manual shell/keypress are simulated. The capacity query is against
# a real, deliberately too-small ext4 filesystem, never a host block device.
if (
    read() {
        if [[ $# == 1 && $1 == -r ]]; then return 0; fi
        builtin read "$@"
    }
    bash() { :; }
    die() { printf 'CAPACITY_REJECTED: %s\n' "$*"; exit 42; }
    step_disk_manual
) > "$scratch/validation.log" 2>&1; then
    status=0
else
    status=$?
fi
# The installer installs an ERR trap. An expected rejection must be tested in
# a conditional: set +e alone does not suppress that trap in the parent shell.
cat "$scratch/validation.log"
[[ $status == 42 ]]
grep -q 'Root needs at least 25 GiB' "$scratch/validation.log"
echo 'HYPRFLUX_LOW_SPACE_GUARD_PASS: real 64 MiB ext4 target rejected before installation'
echo HYPRFLUX_TEST_SMOKE_PASS
