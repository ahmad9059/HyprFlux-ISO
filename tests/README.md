# Installer regression tests

## Fast checks (no root, no VM, no network)

Desktop implementation regressions now live in the **HyprFlux config repo**:
`python3 -m unittest discover -s tests -v` there checks Foot and its generator,
config parity, Kitty GPU handling, cyan icons/hooks and SDDM dependencies.
This ISO repo checks delegation to the published source pin and validates the
installed result; it does not carry duplicate desktop-fix utilities.

```bash
python3 -m unittest discover -s tests -v
```

These inject failures into the **real installer functions** and check validation,
partition naming, mirror preservation, log retention and QEMU disk safety.
They do not prove that an installed desktop boots.

The suite also covers required-prompt cancellation, repeated disk reselection,
live/target parallel-download configuration and HTTPS-probe fallback. When `gum`
is available, `test_real_tui.py` runs actual text prompts on a disposable PTY to
check Escape versus explicit Enter; otherwise those optional tests are skipped.
Run them in an isolated Arch container rather than installing test dependencies
onto the host. No test in this group partitions disks or invokes the installer.

Required text/search/menu prompts cancel cleanly instead of silently choosing
defaults. Blank text submitted with Enter still accepts its displayed default.
Cancelling disk selection, wipe confirmation or swap-size input returns to the
partition-mode menu before any automatic partitioning takes place. Yes/no
prompts continue to treat cancellation as No.

## KVM live smoke test

Build without modifying host packages (Docker must already be usable):

```bash
bash scripts/build-container.sh
```

This caches build tools and downloaded packages. The privileged container is
required by archiso; it mounts only this project and a dedicated package-cache
volume. It invokes `build.sh`, which clears the project's previous `work/` tree
but preserves existing ISOs. Each build writes to a unique `out/build-*/`
directory. Test disks and logs under `.qemu-tests/` are preserved.
Both QEMU launchers discover completed images in `out/` and one directory level
below it. Automatic selection requires a `.sha256` sidecar so it skips partial
builds; an explicit ISO path remains supported. Discovery does not itself verify
the checksum contents.

### Optional package cache inside the ISO

```bash
# Use signed package pairs already in the container's persistent build cache:
bash scripts/build-container.sh --with-package-cache

# Or use a populated cache on an Arch build host (up to 2 GiB by default):
sudo env HYPRFLUX_PACKAGE_CACHE=/var/cache/pacman/pkg \
  HYPRFLUX_CACHE_LIMIT_MIB=2048 bash build.sh
```

The cache is staged in a temporary profile; no binary packages are added to the
source tree. Fresh repository metadata is fetched into an isolated build-only
database; the native host's installed/sync databases are not changed. Old or
unavailable versions and foreign architectures are excluded; base/Desktop
packages take priority, with at most one cached version per name/architecture.
Archives require a detached signature, are bounded by the size
limit, and receive a SHA256 integrity manifest. This packages existing cache
contents; it does not download a complete desktop bundle or promise that cached
versions match the repositories on installation day. An empty/unsigned cache
fails the opt-in build explicitly rather than silently producing an unseeded ISO.

Before pacstrap, the installer verifies and copies this seed directly to the
target disk's pacman cache (not live RAM), preserving existing downloads and at
least 2 GiB free space. Upstream HyprFlux package transactions reuse that same
standard cache. Pacman still selects repository versions and verifies package
signatures; stale or missing packages download normally. Corrupt cache manifests
or unavailable cache media cause a logged warning and normal online fallback.
Internet remains required for repositories, updates, Git clones and AUR builds.
Performance depends on cache freshness; no new speed claim is made without a
matching installed-desktop test.

Transfer counts/bytes and elapsed seeding time are stored in the target's
`/var/log/hyprflux-installer/package-cache-seed.json`. Base/desktop elapsed time
and interface receive-byte deltas are in `performance.tsv`. Receive counters
include DNS, Git, NTP and other guest traffic; seeded bytes are **not** asserted
to equal network bytes saved. Use matching-profile A/B runs before claiming a
speedup.

### Compression investigation

The default recipe remains xz. An explicit experimental recipe is available:

```bash
HYPRFLUX_COMPRESSION=zstd bash scripts/build-container.sh --with-package-cache
```

This uses SquashFS zstd level 15 and live-initramfs zstd level 3. CI's manual
dispatch accepts the same `compression` choice and uses the same `build.sh`.
To benchmark a completed unmounted build tree, use the builder container to run:

```bash
python scripts/benchmark-compression.py --rootfs work/x86_64/airootfs \
  --initramfs PATH_TO_EXTRACTED_INITRAMFS --output NEW_RESULTS_DIRECTORY
```

It requires 12 GiB scratch space, measures two-thread compression/extraction on
the actual filesystem plus the main initramfs CPIO, and removes its own scratch
artifacts. It changes no profile defaults. These timings are not USB-boot,
cold-cache or installed-desktop acceptance results. Test the resulting image's
actual firmware loaders and installation separately.

### Optional authenticated release signatures

Native `build.sh` can sign and verify the completed ISO with GnuPG. Configure a
release key in a private `GNUPGHOME` outside the profile and set
`HYPRFLUX_SIGNING_KEY` to its fingerprint. Use `HYPRFLUX_REQUIRE_SIGNATURE=1` to
fail early when no signing key is configured. A protected key may use
`HYPRFLUX_SIGNING_PASSPHRASE` (passed to GPG through a private descriptor, never
command-line arguments); do not put secrets in source files or shell history.

CI supports secrets `ISO_SIGNING_FINGERPRINT`, `ISO_SIGNING_PRIVATE_KEY`, and
optional `ISO_SIGNING_PASSPHRASE`, with an ephemeral keyring removed afterward.
Signed builds produce `IMAGE.iso.asc`, verified against the completed ISO.
Unsigned development builds remain supported and are labelled as such. The
container helper intentionally does not mount a developer's private keyring;
sign its output afterward with `bash scripts/sign-iso.sh path/to/image.iso`.

Publish the public key/fingerprint over a separately trusted channel, then users
can authenticate the image with `gpg --verify IMAGE.iso.asc IMAGE.iso`. SHA256
alone is not authentication. A throwaway test key does not constitute a real
release signature. Releases remain drafts pending exact-image and hardware
acceptance even when they are signed.

### Hardware and display diagnostics

The live installer records PCI graphics/network/storage IDs, bound drivers and
DRM connector modes in `/var/log/hyprflux-hardware.json`, copied to the installed
system as `/var/log/hyprflux/live-hardware.json`. It excludes device serial
numbers. Missing-driver warnings are advisory: the installed driver may differ.
The report never pins live DRM card numbers or a guessed resolution into the
target desktop. Hyprland selects the connected monitor's preferred/native mode
at startup; custom scaling, unusual EDIDs and hybrid-GPU behavior still require
real-hardware validation.

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

Add `--virtual-audio` on a new install to attach Intel HDA and remember it for
installed boot tests. The guest requires a real ALSA PipeWire sink and streams a
short WAV through `pw-play`. QEMU uses the `none` audio backend: no host sound is
played or recorded. This proves virtual guest routing/streaming, **not audible
hardware playback**. System D-Bus must also be active and all system policy XML
must parse before any desktop boot pass is recorded.

A second `--boot STATE --3d --offline` checks a cold installed-system reboot
without Internet. It does not rerun package installation or first-login setup.

`guest-maintenance-checks.sh` is a separate guarded overlay-only test, never part
of a clean install or a production image. It deliberately resets one test
Papirus link, reinstalls the same cached official package with required local
signature verification, and requires the actual upgrade hook to restore cyan.
It also maps Thunar, Firefox and Chromium (temporary browser profiles, normal
sandboxing) and captures their windows. Such states are marked
`maintenance_test=true`, `embedded=false`, `resumed=true` and excluded from clean
matrix acceptance; their clean read-only backing disk must remain unchanged.

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

### Installer presentation checks

Installed desktop acceptance additionally validates Foot configuration and blur
requests, cyan Papirus folder symlinks/GTK theme, real mapped Kitty and Foot
windows, and actual HyprFlux SDDM QML theme rendering (not its fallback login).
Detailed test logs/screenshots remain in `/var/log/hyprflux-desktop-checks/` on
the disposable guest. The themed QML test uses Qt software rendering to isolate
QML dependencies from virtual-GPU EGL issues; it is not hardware acceptance.
Kitty's local launcher limits the tested software-rendering workaround to VirtIO
DRM graphics and removes that automatic override from child shells.

The HyprFlux UI follows classic Omarchy's wordmark/dim-log-tail layout, with
HyprFlux's cyan logo, pink/magenta prompts and yellow status text. MIT attribution
is included in the image. Dot spinners
use a console-safe line variant on Linux VTs; menu heights adapt to the terminal.
The builder runs real Gum PTY checks plus resize, log sanitation, monitor cleanup
and exit-status regressions.

```bash
python3 tests/qemu-smoke.py --tui-preview path/to.iso
python3 tests/qemu-smoke.py --tui-preview --embedded path/to.iso
```

This previews **current source** on tty1 of a disposable live guest and saves
`tui-preview.png`; add `--embedded` to render the UI library from the actual ISO.
Its log text is synthetic, clearly labelled as a preview;
it does not partition or install anything and does not certify the embedded ISO.

The installer does not prompt for locale: it defaults to `en_US.UTF-8`, which
users may change after installation. Automated installs exercise each application
profile menu choice and check target locale generation/configuration.

For this workspace, `.qemu-tests` links to
`/drive-data/HyprFlux-ISO/qemu-tests`, keeping disposable disks and evidence on the
larger filesystem without changing the harness's state-directory safety checks.

Additional fault/UX cases:

For repeated package-mirror failures, collect guest DNS/HTTPS evidence without
starting another installation:

```bash
python3 tests/qemu-smoke.py --network-diagnostics path/to.iso
python3 tests/qemu-smoke.py --network-diagnostics --ipv4-network path/to.iso
```

The second command disables IPv6 advertisement only on that disposable QEMU
network, not in the production installer. Logs include resolvers, routes,
sequential HTTPS probes and five concurrent mirror requests. A diagnostic
completion marker means evidence was collected, **not** that connectivity or an
installed desktop passed acceptance. Installed tests record their network mode.

```bash
# Live boot/keyring with external networking unavailable; also checks a real
# deliberately too-small ext4 target without touching a host disk:
python3 tests/qemu-smoke.py --offline --memory 4096 path/to.iso

# Minimum advertised RAM, no NTP service, real SDDM password login on reboot:
python3 tests/qemu-smoke.py --install --embedded --memory 4096 --no-ntp \
  --password-login --swap 4 path/to.iso
python3 tests/qemu-smoke.py --boot .qemu-tests/uefi-NEW --3d
```

The install fixture acknowledges the host-provided VM clock but does not bypass
the real signing-key preflight. Production asks for explicit date/time
confirmation when NTP is unavailable, and checks keys before automatic wiping.
Encrypted/LVM/RAID roots are rejected rather than half-configured. Full profile
requires at least 32 GiB root headroom (33 GiB automatic disk before swap), while
Desktop retains its 25/26 GiB checks; future application builds can need more.
Password-login mode injects only the public disposable test password into the
actual SDDM greeter, records a greeter screenshot where available, and forbids
the test autologin setting. It is not a substitute for hardware acceptance.
The verifier also compares legacy versus Lua workspace-dispatch packets so an
official Waybar evaluation checks functionality, not only process existence.

Generate the recorded install/boot matrix for one exact image:

```bash
python3 tests/acceptance-report.py path/to.iso --require-vm-matrix
```

The JSON report hashes the ISO, excludes other images and hot-loaded repairs,
and requires an installation-completion record, a real boot-pass marker and a
PNG screenshot. The optional flag exits nonzero if a required Desktop/Full
VM case is missing. Firmware smoke, optional-app audits, screenshot inspection,
interactive TUI use and physical hardware are separate gates; a complete VM
report never certifies production readiness.

The required recorded matrix has six cases: Desktop automatic and manual-GPT
under UEFI and BIOS, plus Full automatic under UEFI and BIOS. The QEMU runner
copies a fresh OVMF variable template on every UEFI invocation, so installed UEFI
boots also exercise the removable-media fallback loader without retained NVRAM.

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
