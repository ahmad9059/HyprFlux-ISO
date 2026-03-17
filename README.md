# HyprFlux ISO

<p align="center">
  <img src="https://raw.githubusercontent.com/ahmad9059/HyprFlux/main/review/HyprFlux.svg" alt="HyprFlux" width="720" />
</p>

HyprFlux ISO is a custom Arch Linux live ISO that boots into a branded text-based installer and provisions a HyprFlux desktop system on real hardware or in a virtual machine. It is built on top of `archiso`, targets `x86_64`, supports both UEFI and legacy BIOS boot, and is designed for online installation where the HyprFlux stack is cloned and installed from upstream repositories during the install process.

The project focuses on three goals:

- provide a clean, repeatable Arch-based installation experience for HyprFlux
- preserve a minimal and maintainable ISO build profile
- automate image production and validation through local testing and GitHub Actions

## Overview

The ISO boots to a live Arch environment and auto-logs into `tty1`, where the HyprFlux installer launches automatically. The installer collects system configuration, partitions disks, installs a base Arch system with `pacstrap`, performs core system configuration inside the target root, then prepares the HyprFlux installation flow for first boot.

At a high level, the project includes:

- an `archiso` profile with branded boot assets and live-environment configuration
- a custom TUI installer with centered HyprFlux branding and log streaming
- both automatic and manual partitioning flows
- a target-system provisioning pipeline for base Arch plus HyprFlux integration
- QEMU-based test tooling
- a GitHub Actions workflow for automated ISO builds and release artifacts

## Current Boot and Install Model

The repository currently uses a boot-first HyprFlux integration path.

The flow is:

1. Boot the live ISO
2. Auto-login as `root` on `tty1`
3. Launch `hyprflux-install.sh`
4. Collect installation settings
5. Partition and mount the target disk
6. Install the base Arch system with `pacstrap`
7. Configure timezone, locale, users, networking, and GRUB in the target system
8. Clone the HyprFlux and Arch-Hyprland repositories into the target user's home directory
9. Reboot into the installed system
10. Continue the HyprFlux desktop integration flow from the installed system's first boot path

This keeps the live ISO simpler and avoids coupling the full HyprFlux install pipeline directly into the ISO build process.

## Key Features

- `x86_64` Arch Linux live ISO based on `archiso`
- UEFI boot support through GRUB
- legacy BIOS boot support through Syslinux
- online installation model with GitHub-based repository cloning at install time
- custom TUI installer with HyprFlux branding, centered layout, and progress log view
- automatic and manual disk partitioning paths
- NetworkManager-based network setup in the live environment
- root auto-login on `tty1` to launch the installer immediately
- QEMU test launcher for UEFI and BIOS validation
- GitHub Actions workflow for automated build and artifact publishing

## Repository Layout

```text
.
├── .github/workflows/build-iso.yml      # CI build and release pipeline
├── airootfs/                            # Live filesystem contents copied into ISO
│   ├── etc/                             # Live system configuration
│   ├── root/                            # Installer entrypoint and shell startup
│   └── usr/share/                       # Live assets such as plymouth/theme data
├── build.sh                             # Local mkarchiso wrapper
├── efiboot/                             # Loader assets used by archiso tooling
├── grub/                                # UEFI GRUB configuration and theme assets
├── pacman.conf                          # Build-time pacman configuration
├── packages.x86_64                      # Packages included in the live ISO
├── plans/                               # Design and implementation planning documents
├── profiledef.sh                        # archiso profile definition
├── references/                          # Upstream reference repos and assets
├── syslinux/                            # BIOS boot menu configuration
├── test-qemu.sh                         # Local QEMU test helper
└── README.md
```

## Installer Pipeline

The main installer lives at `airootfs/root/hyprflux-install.sh` and uses helper libraries in `airootfs/root/lib/`.

The installer pipeline is structured as follows:

- `Step 0` Network setup
- `Step 1` Welcome prompt
- `Step 2` Timezone selection
- `Step 3` Locale selection
- `Step 4` Keyboard layout selection
- `Step 5` Hostname selection
- `Step 6` User creation
- `Step 7` Disk partitioning
- `Step 8` Base system installation with `pacstrap`
- `Step 9` Target system configuration with `arch-chroot`
- `Step 10` HyprFlux integration preparation
- `Step 11` Cleanup and reboot

## Boot Configuration

The ISO supports both firmware paths:

- `UEFI`: GRUB-based menu and boot chain
- `BIOS`: Syslinux-based menu and boot chain

Relevant files:

- `profiledef.sh`
- `grub/grub.cfg`
- `syslinux/syslinux.cfg`
- `syslinux/archiso_sys-linux.cfg`
- `efiboot/loader/entries/*`

The profile uses:

- `install_dir="hyprflux"`
- `bootmodes=('bios.syslinux' 'uefi.grub')`
- compressed `squashfs` airoot image generation

## Live Environment Design

The live environment is intentionally minimal and task-focused.

- root shell is `zsh`
- `tty1` auto-login launches the installer via `.zlogin`
- NetworkManager is the only network manager used in the live image
- the TUI library handles centered layout, prompts, short spinners, and long-running progress redraws
- build-time assets such as GRUB themes and Plymouth themes can be shipped directly under `airootfs/usr/share/`

## Build Requirements

Local builds are expected to run on Arch Linux or an Arch-compatible environment with the required tooling installed.

Minimum host requirements:

- `archiso`
- `grub`
- `git`
- root privileges for `mkarchiso`

Recommended packages for local testing:

- `qemu-desktop` or `qemu-full`
- `edk2-ovmf`

## Building the ISO

Build locally from the repository root:

```bash
sudo bash build.sh
```

What `build.sh` does:

- verifies root access
- checks that `mkarchiso` is installed
- removes previous `work/` and `out/` artifacts
- runs `mkarchiso -v -w work -o out .`
- writes a `.sha256` file for the generated ISO
- optionally removes the `work/` directory after a successful build

Build output is written to:

- `out/*.iso`
- `out/*.iso.sha256`

## Testing in QEMU

The repository ships a test helper at `test-qemu.sh`.

Default UEFI boot test:

```bash
./test-qemu.sh
```

Legacy BIOS test:

```bash
./test-qemu.sh --bios
```

Test characteristics:

- creates a fresh `40G` qcow2 disk image for each run
- uses OVMF for UEFI testing
- boots the most recent ISO from `out/` if no path is provided
- attaches virtio graphics, network, and storage devices

## Writing the ISO to USB

After building, write the ISO to a removable device with `dd`:

```bash
sudo dd bs=4M if=out/hyprflux-*.iso of=/dev/sdX status=progress oflag=sync
```

Replace `/dev/sdX` with the correct target device.

## CI and Release Workflow

The project includes a GitHub Actions workflow at `.github/workflows/build-iso.yml`.

The workflow:

- runs inside an `archlinux:latest` container
- installs `archiso`, `grub`, and `git`
- builds the ISO with `mkarchiso`
- uploads the ISO and checksum as workflow artifacts
- creates a GitHub release for version tags matching `v*`

Triggers:

- push to `main`
- pull requests targeting `main`
- manual `workflow_dispatch`
- version tags such as `v1.0.0`

## Customization Points

The repository is structured so common ISO customizations remain straightforward.

### Packages

Live ISO packages are defined in `packages.x86_64`.

Use this file to add or remove:

- live-environment tooling
- firmware
- network utilities
- editor and shell packages
- splash or boot-related packages such as `plymouth`

### Live Filesystem

Everything under `airootfs/` is copied into the live image.

Typical customizations include:

- `/root/.zlogin`
- `/root/hyprflux-install.sh`
- `/root/lib/tui.sh`
- `/etc/systemd/system/*`
- `/usr/share/plymouth/themes/*`
- `/usr/share/grub/themes/*`

### Boot Menus

Adjust boot menu behavior in:

- `grub/grub.cfg` for UEFI GRUB
- `syslinux/` for BIOS Syslinux menus
- `efiboot/loader/entries/` if needed by your archiso boot tooling layout

### Installer Behavior

Primary installer logic is in:

- `airootfs/root/hyprflux-install.sh`
- `airootfs/root/lib/common.sh`
- `airootfs/root/lib/tui.sh`

## Reference Sources

The project uses read-only upstream references under `references/`.

These are used as implementation references and asset sources:

- `references/HyprFlux`
- `references/Arch-Hyprland`
- `references/Hyprland-Dots`

Typical uses include:

- asset reuse such as GRUB and Plymouth themes
- understanding the upstream HyprFlux installation modules
- aligning ISO integration with the HyprFlux desktop stack

## Development Notes

- shell scripts generally use `set -euo pipefail`
- installer variables use the `INSTALL_` prefix
- `profiledef.sh` controls boot modes, ISO naming, and permissions inside the live image
- `%INSTALL_DIR%`, `%ARCHISO_UUID%`, and `%ARCH%` are `archiso` template values resolved during build

## Troubleshooting

### `mkarchiso` fails because `grub-install` is missing

Ensure the build host has `grub` installed. This is required when using `uefi.grub` in `profiledef.sh`.

### CI fails on the UEFI GRUB validation step

The GitHub Actions container must install `grub` in addition to `archiso`.

### No ISO is generated in `out/`

Review the `mkarchiso` output and confirm:

- the build ran as root
- `profiledef.sh` is in the repository root
- `packages.x86_64` does not reference unavailable packages

### Boot menu changes do not appear

Always rebuild from a clean state when changing boot assets:

```bash
sudo rm -rf work out
sudo bash build.sh
```

### QEMU UEFI boot shows extra firmware text

Some firmware output comes from OVMF itself before GRUB or the kernel starts. This is separate from ISO theming and can vary by QEMU and OVMF version.

## Project Status

This repository contains an actively developed HyprFlux ISO build profile with:

- a working `archiso` layout
- a branded TUI installer
- UEFI and BIOS boot support
- local QEMU testing support
- GitHub Actions-based ISO builds

Behavior and integration details may continue to evolve as the HyprFlux installation flow and upstream assets are refined.

## License and Upstream Attribution

This repository contains project-specific code and configuration for building the HyprFlux ISO. It also references upstream projects and assets used for integration, testing, and customization.

Please review the licenses of:

- Arch Linux and `archiso`
- HyprFlux
- Arch-Hyprland
- Hyprland-Dots
- bundled theme assets under `references/`

## Author

Maintained by Ahmad and the HyprFlux project.
