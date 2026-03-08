#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="hyprflux"
iso_label="HYPRFLUX_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="HyprFlux <https://hyprflux.dev>"
iso_application="HyprFlux Live/Installer"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.grub')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/hyprflux-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/home/hyprflux"]="1000:1000:750"
  ["/usr/local/bin/hyprflux-install"]="0:0:755"
  ["/usr/local/bin/hyprflux-welcome"]="0:0:755"
  ["/usr/local/bin/hyprflux-nvidia-detect"]="0:0:755"
)
