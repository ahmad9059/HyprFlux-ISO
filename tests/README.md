# Installer regression tests

## Fast checks (no root, no VM, no network)

```bash
python3 -m unittest discover -s tests -v
```

These inject failures into the **real installer functions** and check validation,
partition naming, mirror preservation, log retention and QEMU disk safety.
They do not prove that an installed desktop boots.

## KVM live smoke test

Build without modifying host packages (Docker must already be usable):

```bash
bash scripts/build-container.sh
```

This caches build tools and downloaded packages. The privileged container is
required by archiso; it mounts only this project and a dedicated package-cache
volume. It invokes `build.sh`, which clears the project's previous `work/` and
`out/` artifacts. Test disks and logs under `.qemu-tests/` are preserved.

Host requirements: `qemu-system-x86_64`, `qemu-img`, `xorriso`, `blkid`, Python 3,
and `edk2-ovmf` for UEFI. Run as your normal user, with access to `/dev/kvm`.

```bash
python3 tests/qemu-smoke.py out/hyprflux-YYYY.MM.DD-x86_64.iso
python3 tests/qemu-smoke.py --bios out/hyprflux-YYYY.MM.DD-x86_64.iso
```

The fast path extracts the kernel/initramfs and bypasses the ISO bootloader.
Test the actual firmware loader separately:

```bash
python3 tests/qemu-smoke.py --firmware-boot path/to.iso
python3 tests/qemu-smoke.py --firmware-boot --bios path/to.iso
```

Every run creates an isolated `.qemu-tests/<run>/` with a new sparse 40 GiB disk,
serial log, QEMU log, command arguments and source hashes. No host disk is attached.
No SSH port or public VNC listener is opened.

The runner uses Q35 for both firmware modes. On this host the legacy i440fx
model failed to discover its IDE CD-ROM during direct UEFI kernel boot; Q35's
AHCI path boots correctly. Serial tests disable Plymouth to avoid input capture.

## Full installation and real desktop boot

New disposable installs default to `--profile desktop`. Use `--profile full`
to exercise the extended application bundle. Both profiles require desktop
essentials, including Waybar and wlogout, before optional application batches.
The chosen profile is stored in each run's `machine.json`.
The guest also checks `/etc/hyprflux-install-profile` and prints the installed
profile plus the recorded missing-application list. For Full acceptance, inspect
component warnings and package logs as well: an empty missing-AUR list does not
prove that every optional repository application installed successfully.

To avoid downloading the same signed packages for every disposable install,
optionally seed from an existing pacman package cache:

```bash
python3 tests/qemu-smoke.py --install --embedded --package-cache /path/to/pacman/pkg path/to.iso
```

The cache is a separate **read-only** 9p share, not part of the frozen installer
source. The driver copies archives/signatures into the disposable target cache
without overwriting existing files; partial downloads and symlinks are ignored.
Normal pacman version selection and signature validation remain enabled. Missing
or newer packages still download normally. The shared host cache is never
written by the guest. This is a warm-cache performance test, not evidence of a
fresh-network download path. The option also works with `--resume`.

To exercise the manual-partition path against real disposable block devices:

```bash
python3 tests/qemu-smoke.py --install --embedded --manual-layout --package-cache .qemu-tests/package-cache path/to.iso
```

The automated shell fixture creates GPT with a 512 MiB EFI partition (UEFI) or
2 MiB BIOS boot partition (BIOS), plus ext4 root. It then invokes the embedded
installer's actual manual mount/filesystem validation and installs normally.
Add `--bios` for the latter layout. This mode requires a new run with no swap;
it tests the manual code path but does **not** replace human partition-shell or
TUI-flow acceptance. Layout metadata is recorded in `machine.json`.

```bash
python3 tests/qemu-smoke.py --install path/to.iso
# Use the state directory printed by the installation run:
python3 tests/qemu-smoke.py --boot .qemu-tests/uefi-<run> --3d
```

For final-image acceptance, use the ISO's embedded installer rather than current
hot-loaded installer scripts:

```bash
python3 tests/qemu-smoke.py --install --embedded path/to/final.iso
python3 tests/qemu-smoke.py --boot .qemu-tests/uefi-<run> --3d
```

Repeat with `--bios`. `--embedded` requires a new installation, records the ISO
digest in `image.sha256`, and sources `/root/hyprflux-install.sh` from the live
image. Only the VM driver/verifier is supplied by the read-only test share. The
driver still replaces interactive prompts with known test answers; manual TUI
flow testing remains a separate acceptance requirement.

Repeat installation and boot with `--bios` for the legacy boot path. `--boot`
uses a **fresh OVMF variable store**, testing the UEFI fallback loader as well.
The guest must start SDDM, NetworkManager, Hyprland, Waybar and PipeWire and report
no Hyprland config errors. `--3d` requires a working EGL/virgl render device;
Hyprland is not expected to work with an unaccelerated virtual VGA device.
The guest captures the actual compositor with `grim` and transfers its PNG in
the serial log; the runner saves it as `desktop.png`. This works when EGL uses
DMA-BUF scanout and QMP's `screendump` reports `no surface`. Screenshot capture
is required for the current guest verifier to emit its boot-success marker.

Preflight the host without an ISO:

```bash
python3 tests/qemu-preflight.py
python3 tests/qemu-preflight.py --render-node /dev/dri/renderD128
```

Storage coverage: `--disk-bus virtio|scsi|sata|nvme` and `--swap 4` exercise
different controllers and partition layouts. Boot runs remember the installed
disk bus and firmware mode. On multi-GPU hosts, `--3d` probes render nodes and
selects one that initializes and shuts down cleanly; override with
`--render-node /dev/dri/renderD128` if necessary.

Installation gets a three-hour deadline; smoke/boot tests get ten minutes.
Override with `--timeout SECONDS`. Failure preserves the disk and logs.
Allow roughly 30 GiB of host free space for a full install, including package
caches. The runner stops before host free space falls below 2 GiB.

If base-system configuration completed but desktop integration failed, retry
without repartitioning or downloading the base system again:

```bash
python3 tests/qemu-smoke.py --resume .qemu-tests/uefi-<run> path/to.iso
```

Resume retains the recorded profile (old runs without profile metadata use Full).
To explicitly change the resumed integration to Desktop, add `--profile desktop`.
This does not uninstall packages already present from a previous Full attempt.

Resume validates the test disk's release marker and test user. It preserves
partitions, installed packages, package cache, prior console logs and source
snapshots. Only the latest desktop-integration code is rerun. Existing clean
pinned source checkouts are reused; modified checkouts are backed up instead.

## Inspect a running installation without restarting it

Open a separate VT2 shell in the disposable **live ISO** and print read-only
package errors, process status, disk and memory usage into its serial log:

```bash
python3 tests/qemu-console.py .qemu-tests/uefi-<run> --login-root --diagnose
# Reuse that VT2 shell for a source-config check against installed Hyprland:
python3 tests/qemu-console.py .qemu-tests/uefi-<run> --probe-config
```

These use the live ISO's normal empty-password root login, not SSH or a guest
agent. The installer continues on ttyS0. Diagnostics do not change package state;
the config probe uses an isolated temporary HOME/runtime and removes them after
checking. Extra diagnostic-script hashes are recorded separately from the frozen
installer inputs. A successful config probe is **not** a desktop boot test.

`--command '...'` is available for deliberate manual commands in that shell;
it executes with live-root privileges. Do not issue concurrent package-manager
commands while installation is running.

Changed installer scripts are snapshotted and mounted **read-only** over 9p for
each run: no ISO rebuild is needed for script changes. Rebuild for changes to
packages, kernel/initramfs, boot menus, systemd units or shell startup. A hot-loaded
script test is **not** verification of a newly packaged release ISO.

The full test uses public disposable credentials (`fluxcheck` /
`hyprflux-test-only`) and test-only SDDM autologin. These exist only on the test
disk, never in the production image. **Do not distribute test qcow2 images.**

## Release acceptance

Do not call an image production-ready until these pass on that exact image:

- UEFI and BIOS ISO firmware boot
- UEFI and BIOS installation, then real desktop login
- Fresh-NVRAM fallback boot
- Automatic partitioning with and without swap
- Manual ext4 + FAT32 ESP / BIOS-GPT layouts
- At least one Intel/AMD machine and an NVIDIA machine using a supported driver
- Keyboard, networking, sound, suspend/resume and external display checks

Unsupported: ARM, 32-bit x86/UEFI, Secure Boot without custom signing, encrypted
root/RAID/custom filesystem boot configuration. Older GPUs may not support the
current Hyprland renderer. No VM test can guarantee compatibility with every PC.
