# Phase 2: Boot Configuration (UEFI + BIOS/Legacy)

## Goal

Create the boot loader configuration files that allow the HyprFlux ISO to boot on both **UEFI** and **Legacy BIOS** machines. This includes systemd-boot entries for UEFI and syslinux configs for BIOS.

After this phase, the ISO should boot cleanly on both UEFI and Legacy BIOS hardware/VMs.

---

## Boot Architecture Overview

```
ISO Boot Process:
├── UEFI Machine
│   └── systemd-boot (efiboot/loader/) → kernel + initramfs
│
└── Legacy BIOS Machine
    └── syslinux (syslinux/) → kernel + initramfs
```

Both paths ultimately load the same kernel (`vmlinuz-linux`) and initramfs (`initramfs-linux.img`) with the same boot parameters. The difference is just the bootloader firmware interface.

**NOTE:** We use `systemd-boot` for UEFI (not GRUB). This matches the official archiso releng profile and is simpler. GRUB is only installed on the **target system** (Phase 4, Step 9), not used for ISO boot.

---

## Template Variables

archiso's `mkarchiso` automatically replaces these template variables at build time in all boot config files:

| Variable | Replaced With | Example |
|----------|---------------|---------|
| `%ARCHISO_UUID%` | ISO filesystem UUID | `2024-01-15-12-30-00-00` |
| `%INSTALL_DIR%` | `install_dir` from profiledef.sh | `hyprflux` |
| `%ARCH%` | Architecture | `x86_64` |

**CRITICAL:** Do NOT use custom placeholders like `HYPRFLUX_REPLACE_LABEL`. Use the official `%VARIABLE%` syntax. No manual `sed` replacement is needed in `build.sh`.

---

## File List

| # | File | Lines | Description |
|---|------|-------|-------------|
| 1 | `efiboot/loader/loader.conf` | ~4 | systemd-boot configuration |
| 2 | `efiboot/loader/entries/01-hyprflux-x86_64-linux.conf` | ~6 | Default boot entry |
| 3 | `efiboot/loader/entries/02-hyprflux-x86_64-linux-ram.conf` | ~6 | Copy-to-RAM boot entry |
| 4 | `grub/grub.cfg` | ~45 | GRUB config (fallback for EFI systems without systemd-boot) |
| 5 | `syslinux/syslinux.cfg` | ~10 | Main syslinux config (includes modular files) |
| 6 | `syslinux/archiso_sys-linux.cfg` | ~20 | Linux boot entries for syslinux |
| 7 | `syslinux/archiso_head.cfg` | ~25 | Syslinux header/styling |
| 8 | `syslinux/archiso_tail.cfg` | ~10 | Syslinux footer (reboot/poweroff) |
| 9 | `syslinux/archiso_sys.cfg` | ~5 | Syslinux system include file |

---

## Detailed Specifications

### 1. `efiboot/loader/loader.conf` (~4 lines)

systemd-boot configuration for UEFI machines.

```ini
timeout 15
default 01-hyprflux-*
editor no
```

**Notes:**
- `editor no` prevents users from editing kernel params at boot (security)
- 15-second timeout before auto-selecting the default entry
- Wildcard pattern matches the default entry

---

### 2. `efiboot/loader/entries/01-hyprflux-x86_64-linux.conf`

Primary systemd-boot entry for the HyprFlux live environment.

```ini
title   HyprFlux Installer
linux   /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
initrd  /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
options archisosearchuuid=%ARCHISO_UUID% cow_spacesize=2G copytoram=n
```

**Key changes from original plan:**
- Uses `archisosearchuuid=%ARCHISO_UUID%` instead of deprecated `archisolabel=`
- Uses `%INSTALL_DIR%` and `%ARCH%` template variables instead of hardcoded paths
- No `archisobasedir=` needed when using UUID-based detection

---

### 3. `efiboot/loader/entries/02-hyprflux-x86_64-linux-ram.conf`

Copy-to-RAM variant (loads entire squashfs into RAM -- faster but needs 2GB+ RAM).

```ini
title   HyprFlux Installer (Copy to RAM)
linux   /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
initrd  /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
options archisosearchuuid=%ARCHISO_UUID% cow_spacesize=2G copytoram=y
```

---

### 4. `grub/grub.cfg` (~45 lines)

GRUB configuration as fallback for UEFI systems. Some UEFI firmware may load GRUB instead of systemd-boot.

```bash
# grub.cfg -- HyprFlux Live ISO (GRUB/UEFI fallback)

set timeout=15
set default=0

insmod all_video
insmod gfxterm
terminal_output gfxterm
set gfxpayload=keep

menuentry "HyprFlux Installer" --class arch --class linux {
    set gfxpayload=keep
    search --no-floppy --set=root --fs-uuid %ARCHISO_UUID%
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux \
        archisosearchuuid=%ARCHISO_UUID% \
        cow_spacesize=2G \
        copytoram=n
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

menuentry "HyprFlux Installer (Copy to RAM)" --class arch --class linux {
    set gfxpayload=keep
    search --no-floppy --set=root --fs-uuid %ARCHISO_UUID%
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux \
        archisosearchuuid=%ARCHISO_UUID% \
        cow_spacesize=2G \
        copytoram=y
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
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

**Key changes from original plan:**
- Uses `search --fs-uuid %ARCHISO_UUID%` for reliable root device discovery
- Uses `archisosearchuuid=%ARCHISO_UUID%` instead of deprecated `archisolabel=`
- Uses template variables for all paths
- No custom `set archiso_label=` variable needed

---

### 5-9. Syslinux Configuration (Modular Structure)

Following the releng profile's modular approach instead of a single flat file.

#### `syslinux/syslinux.cfg` (entry point)

```ini
INCLUDE archiso_sys.cfg
INCLUDE archiso_tail.cfg
```

#### `syslinux/archiso_sys.cfg` (includes system configs)

```ini
INCLUDE archiso_head.cfg
INCLUDE archiso_sys-linux.cfg
```

#### `syslinux/archiso_head.cfg` (header/styling)

```ini
SERIAL 0 115200
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

MENU CLEAR
MENU IMMEDIATE
MENU HELPMSGROW 18
MENU HELPMSGENDROW -1

TIMEOUT 150
DEFAULT hyprflux
```

#### `syslinux/archiso_sys-linux.cfg` (boot entries)

```ini
LABEL hyprflux
    MENU LABEL HyprFlux Installer
    MENU DEFAULT
    LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
    INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
    APPEND archisosearchuuid=%ARCHISO_UUID% cow_spacesize=2G copytoram=n

LABEL hyprflux-ram
    MENU LABEL HyprFlux Installer (Copy to RAM)
    LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
    INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
    APPEND archisosearchuuid=%ARCHISO_UUID% cow_spacesize=2G copytoram=y
```

#### `syslinux/archiso_tail.cfg` (footer entries)

```ini
LABEL reboot
    MENU LABEL Reboot
    COM32 reboot.c32

LABEL poweroff
    MENU LABEL Power Off
    COM32 poweroff.c32
```

**Changes from original plan:**
- Modular structure matching releng (instead of single flat file)
- Uses `archisosearchuuid=%ARCHISO_UUID%` instead of deprecated `archisolabel=`
- Uses template variables for paths
- Added `SERIAL` line for serial console support

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
│           ├── 01-hyprflux-x86_64-linux.conf
│           └── 02-hyprflux-x86_64-linux-ram.conf
├── grub/                             # << Phase 2
│   └── grub.cfg
├── syslinux/                         # << Phase 2
│   ├── syslinux.cfg
│   ├── archiso_sys.cfg
│   ├── archiso_sys-linux.cfg
│   ├── archiso_head.cfg
│   └── archiso_tail.cfg
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
   - **BIOS**: 1MB BIOS boot partition (type `ef02`) for GPT

This is detailed in Phase 4.

---

## Validation Steps

1. Build the ISO with `sudo bash build.sh`
2. **UEFI test**: `./test-qemu.sh --uefi` -- should show systemd-boot menu with "HyprFlux Installer" entry, boots to root shell
3. **BIOS test**: `./test-qemu.sh --bios` -- should show syslinux menu with "HyprFlux Installer" entry, boots to root shell
4. Verify the boot menu shows proper titles ("HyprFlux Installer")
5. Verify the "Copy to RAM" variant boots correctly (needs 2GB+ RAM in QEMU)
6. Verify timeout (15 seconds) and auto-selection work
7. Verify boot parameters are correct: `cat /proc/cmdline` should show `archisosearchuuid=...`

---

## Estimated Implementation Time

~20-30 minutes (mostly config files, minimal logic).

---

## Dependencies

- **Requires Phase 1** -- profile and packages must exist
- **Required by Phase 3** -- the installer needs to boot before it can run
