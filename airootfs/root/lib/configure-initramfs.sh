#!/bin/bash
# Runs inside the target chroot. Upstream cosmetic modules must not dictate
# boot-critical hook ordering or replace storage/GPU modules.
set -euo pipefail
mkdir -p /etc/mkinitcpio.conf.d
cat > /etc/mkinitcpio.conf.d/99-hyprflux.conf <<'EOF'
MODULES+=(virtio_blk virtio_pci virtio_scsi nvme ahci sd_mod xhci_pci usb_storage uas mmc_block sdhci_pci)
FILES+=(/usr/lib/firmware/regulatory.db /usr/lib/firmware/regulatory.db.p7s)
HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)
COMPRESSION="zstd"
EOF
if [[ -f /usr/lib/initcpio/install/plymouth ]]; then
    sed -i 's/base systemd /base systemd plymouth /' /etc/mkinitcpio.conf.d/99-hyprflux.conf
fi
mkinitcpio -P
