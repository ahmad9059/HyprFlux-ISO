#!/bin/bash
set -euo pipefail
trap 'echo "HYPRFLUX_TEST_FAILED line=$LINENO"' ERR
[[ $(uname -m) == x86_64 ]]
systemctl is-active NetworkManager
systemctl start pacman-init.service
for tool in gum fzf pacstrap arch-chroot lsinitcpio grub-install git curl; do
    command -v "$tool"
done
curl --fail --silent --location --max-time 30 https://archlinux.org/ -o /dev/null
bash -n /run/hyprflux-source/airootfs/root/hyprflux-install.sh
echo HYPRFLUX_TEST_SMOKE_PASS
