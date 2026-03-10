#!/usr/bin/env bash
# shellcheck disable=SC2034
# profiledef.sh -- archiso profile definition for HyprFlux

iso_name="hyprflux"
iso_label="HYPRFLUX_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="HyprFlux <https://github.com/ahmad9059/HyprFlux>"
iso_application="HyprFlux Arch Linux Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="hyprflux"
buildmodes=('iso')
bootmodes=(
  'bios.syslinux'
  'uefi.systemd-boot'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/hyprflux-install.sh"]="0:0:755"
  ["/root/lib"]="0:0:755"
  ["/root/lib/tui.sh"]="0:0:755"
  ["/root/lib/common.sh"]="0:0:755"
  ["/root/lib/hyprflux-chroot-wrapper.sh"]="0:0:755"
)
