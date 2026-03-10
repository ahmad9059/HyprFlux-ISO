# Phase 2: Boot Configuration (UEFI + BIOS/Legacy)

## Goal

Create the boot loader configuration files that allow the HyprFlux ISO to boot on both **UEFI** and **Legacy BIOS** machines. This includes GRUB configs for UEFI, syslinux configs for BIOS, and the systemd-boot loader entries.

After this phase, the ISO should boot cleanly on both UEFI and Legacy BIOS hardware/VMs.

---

## Boot Architecture Overview

```
ISO Boot Process:
├── UEFI Machine
│   ├── systemd-boot (loader/entries/) → kernel + initramfs
│   └── GRUB fallback (grub/grub.cfg) → kernel + initramfs
│
└── Legacy BIOS Machine
    └── syslinux (syslinux/syslinux.cfg) → kernel + initramfs
```

Both paths ultimately load the same kernel (`vmlinuz-linux`) and initramfs (`initramfs-linux.img`) with the same boot parameters. The difference is just the bootloader firmware interface.

---

## File List

| # | File | Lines | Description |
|---|------|-------|-------------|
| 1 | `grub/grub.cfg` | ~50 | GRUB config for UEFI ISO boot |
| 2 | `efiboot/loader/loader.conf` | ~4 | systemd-boot configuration |
| 3 | `efiboot/loader/entries/01-hyprflux.conf` | ~6 | systemd-boot entry for live env |
| 4 | `syslinux/syslinux.cfg` | ~30 | Main syslinux config (BIOS boot) |
| 5 | `syslinux/splash.png` | binary | Boot splash image (640x480, optional) |

---

## Detailed Specifications

### 1. `grub/grub.cfg` (~50 lines)

GRUB configuration for the live ISO. Used when booting via UEFI.

```bash
# grub.cfg -- HyprFlux Live ISO (GRUB/UEFI)

# Visual
set timeout=15
set default=0
set gfxmode=auto
insmod all_video
insmod gfxterm
terminal_output gfxterm

# Theme (optional, can be added later)
# loadfont /boot/grub/fonts/unicode.pf2
# set gfxpayload=keep

# Archiso boot parameters
set archiso_label="HYPRFLUX_REPLACE_LABEL"

menuentry "HyprFlux Installer" --class arch --class linux {
    set gfxpayload=keep
    linux /arch/boot/x86_64/vmlinuz-linux \
        archisobasedir=arch \
        archisolabel=${archiso_label} \
        cow_spacesize=2G \
        copytoram=n
    initrd /arch/boot/x86_64/initramfs-linux.img
}

menuentry "HyprFlux Installer (Copy to RAM)" --class arch --class linux {
    set gfxpayload=keep
    linux /arch/boot/x86_64/vmlinuz-linux \
        archisobasedir=arch \
        archisolabel=${archiso_label} \
        cow_spacesize=2G \
        copytoram=y
    initrd /arch/boot/x86_64/initramfs-linux.img
}

menuentry "System shutdown" --class shutdown {
    echo "Shutting down..."
    halt
}

menuentry "System restart" --class restart {
    echo "Restarting..."
    reboot
}
```

**Notes:**
- `HYPRFLUX_REPLACE_LABEL` is replaced by mkarchiso during build (or the build script can sed it)
- `cow_spacesize=2G` gives more writable space in the live env (default 256M is tight)
- "Copy to RAM" option loads the entire squashfs into RAM -- faster but needs 2GB+ RAM
- The `archiso_label` MUST match `iso_label` from `profiledef.sh`

---

### 2. `efiboot/loader/loader.conf` (~4 lines)

systemd-boot configuration for UEFI machines.

```ini
timeout 15
default 01-hyprflux.conf
editor no
```

**Notes:**
- `editor no` prevents users from editing kernel params at boot (security)
- 15-second timeout before auto-selecting the default entry

---

### 3. `efiboot/loader/entries/01-hyprflux.conf` (~6 lines)

systemd-boot entry for the HyprFlux live environment.

```ini
title   HyprFlux Installer
linux   /arch/boot/x86_64/vmlinuz-linux
initrd  /arch/boot/x86_64/initramfs-linux.img
options archisobasedir=arch archisolabel=HYPRFLUX_REPLACE_LABEL cow_spacesize=2G copytoram=n
```

**Note:** `HYPRFLUX_REPLACE_LABEL` is dynamically replaced at build time.

---

### 4. `syslinux/syslinux.cfg` (~30 lines)

Syslinux configuration for Legacy BIOS machines.

```ini
# syslinux.cfg -- HyprFlux Live ISO (Legacy BIOS)

DEFAULT hyprflux
PROMPT 1
TIMEOUT 150

UI menu.c32

MENU TITLE HyprFlux Installer
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

LABEL hyprflux
    MENU LABEL HyprFlux Installer
    MENU DEFAULT
    LINUX /arch/boot/x86_64/vmlinuz-linux
    INITRD /arch/boot/x86_64/initramfs-linux.img
    APPEND archisobasedir=arch archisolabel=HYPRFLUX_REPLACE_LABEL cow_spacesize=2G copytoram=n

LABEL hyprflux-ram
    MENU LABEL HyprFlux Installer (Copy to RAM)
    LINUX /arch/boot/x86_64/vmlinuz-linux
    INITRD /arch/boot/x86_64/initramfs-linux.img
    APPEND archisobasedir=arch archisolabel=HYPRFLUX_REPLACE_LABEL cow_spacesize=2G copytoram=y

LABEL reboot
    MENU LABEL Reboot
    COM32 reboot.c32

LABEL poweroff
    MENU LABEL Power Off
    COM32 poweroff.c32
```

---

### 5. `syslinux/splash.png` (optional)

A 640x480 PNG splash image for the syslinux boot menu. This is optional -- without it, syslinux shows a text-only menu. Can be added later for branding.

If included, add this to `syslinux.cfg`:
```
MENU BACKGROUND splash.png
```

---

## Build-Time Label Replacement

The `build.sh` from Phase 1 needs a small addition to replace `HYPRFLUX_REPLACE_LABEL` with the actual ISO label in all boot config files. This can be handled by mkarchiso's built-in label replacement, OR we add a pre-build step to `build.sh`:

```bash
# In build.sh, before mkarchiso:
ISO_LABEL="HYPRFLUX_$(date +%Y%m)"
sed -i "s/HYPRFLUX_REPLACE_LABEL/${ISO_LABEL}/g" \
    grub/grub.cfg \
    efiboot/loader/entries/01-hyprflux.conf \
    syslinux/syslinux.cfg
```

**Note:** mkarchiso may handle this automatically via the `iso_label` variable in `profiledef.sh`. If so, the sed is unnecessary. Test during Phase 1 implementation to confirm.

---

## Directory Structure After Phase 2

```
hyprflux-iso/
├── build.sh                          # Phase 1
├── profiledef.sh                     # Phase 1
├── packages.x86_64                   # Phase 1
├── pacman.conf                       # Phase 1
├── airootfs/                         # Phase 1
│   └── etc/ ...
├── efiboot/                          # << Phase 2
│   └── loader/
│       ├── loader.conf
│       └── entries/
│           └── 01-hyprflux.conf
├── grub/                             # << Phase 2
│   └── grub.cfg
├── syslinux/                         # << Phase 2
│   └── syslinux.cfg
├── plans/
├── instructions.md
├── test-qemu.sh
└── .gitignore
```

---

## BIOS vs UEFI in the Target Installer

Phase 2 only covers the **ISO's own boot process**. The **target system's bootloader** (installed to the user's disk) is handled in Phase 4, Step 9. The installer will:

1. Detect if the machine booted in UEFI or BIOS mode:
   ```bash
   if [ -d /sys/firmware/efi ]; then
       BOOT_MODE="uefi"
   else
       BOOT_MODE="bios"
   fi
   ```

2. Install GRUB accordingly:
   - **UEFI**: `grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB`
   - **BIOS**: `grub-install --target=i386-pc /dev/sdX`

3. Adjust partitioning:
   - **UEFI**: EFI system partition (ESP) required -- 1024MB FAT32
   - **BIOS**: Optional 1MB BIOS boot partition (type `ef02`) for GPT, or MBR partitioning

This is detailed in Phase 4.

---

## Validation Steps

1. Build the ISO with `sudo bash build.sh`
2. **UEFI test**: `./test-qemu.sh --uefi` -- should show GRUB menu with "HyprFlux Installer" entry, boots to root shell
3. **BIOS test**: `./test-qemu.sh --bios` -- should show syslinux menu with "HyprFlux Installer" entry, boots to root shell
4. Verify the boot menu shows proper titles ("HyprFlux Installer")
5. Verify the "Copy to RAM" variant boots correctly (needs 2GB+ RAM in QEMU)
6. Verify timeout (15 seconds) and auto-selection work

---

## Estimated Implementation Time

~20-30 minutes (mostly config files, minimal logic).

---

## Dependencies

- **Requires Phase 1** -- profile and packages must exist
- **Required by Phase 3** -- the installer needs to boot before it can run
