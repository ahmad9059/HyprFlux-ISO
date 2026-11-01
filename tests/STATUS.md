# Hardening verification status

This is a progress checkpoint, **not production certification**.

## Verified

- `python3 -m unittest discover -s tests -v`: **40 tests passed**.
- ShellCheck warning-level checks of installer, libraries, launchers and guest
  scripts passed; Python compilation and `git diff --check` passed.
- `out/hyprflux-2026.10.30-x86_64.iso` was built (1.3 GB), and its SHA256 sidecar
  verified successfully.
- UEFI direct-kernel live smoke: `HYPRFLUX_TEST_SMOKE_PASS`.
  Evidence: `.qemu-tests/uefi-fj_nz6s9/serial.log`.
- Actual UEFI/GRUB serial-menu live smoke: `HYPRFLUX_TEST_SMOKE_PASS`.
  Evidence: `.qemu-tests/uefi-nnypmp34/serial.log`.
- Actual BIOS/Syslinux serial-menu live smoke: `HYPRFLUX_TEST_SMOKE_PASS`.
  Evidence: `.qemu-tests/bios-irbz96pp/serial.log`.
- KVM preflight and EGL/virgl on `/dev/dri/renderD128` initialized and shut down
  cleanly. `/dev/dri/renderD129` crashed QEMU on shutdown; the runner now probes
  devices rather than assuming a vendor-specific preference.

## Corrected-image Desktop profile: all four VM install/boot paths passed

### Active next gate: exact-image Full profile

The user approved lossless compaction of the four completed VM disks, keeping
them bootable. Conversion uses qcow2/zstd, rejects snapshots/backing chains/
bitmaps, runs `qemu-img check`, requires unchanged virtual size and successful
`qemu-img compare`, then atomically replaces the original. Per-run proof is
saved as `compaction.json`. No guest contents are intentionally discarded.

The first disk compacted from 8.67 to 4.97 GiB and compared identical. The
foreground command timed out while checking the second copy; its original
remained intact. Resumed the checks in a background job, reusing the candidate
only after the same validation. Log: `/tmp/opencode/completed-vm-compaction.log`.

Task `sh_19640715900190ZtYyzDlFptJJ` finishes compaction, then runs:

```bash
python3 tests/qemu-smoke.py --install --embedded --disk-bus nvme --profile full --package-cache .qemu-tests/package-cache out/waybar-fix-20261101T053308Z/hyprflux-2026.11.01-x86_64.iso
```

Full install log: `/tmp/opencode/corrected-iso-full-profile-install.log`.
Do not start another installation concurrently. After `installed.ok`, run its
first desktop boot and inspect wrapper component warnings plus recorded missing
applications. The test driver now asserts the recorded installed profile and
prints `HYPRFLUX_INSTALLED_PROFILE` / optional-missing report markers. The report
only reflects the file, not an independent audit of all optional applications.
All 40 tests and ShellCheck pass; production ISO sources are unchanged.

All rows use the exact candidate below (`image.sha256` checked for every run),
with its embedded installer and no manual repair of the installed system:

| Firmware / storage | Layout | Cache | Install + first desktop boot | Evidence state |
| --- | --- | --- | --- | --- |
| UEFI / NVMe | Automatic, no swap | Cold | PASS | `.qemu-tests/uefi-_nvgsobl/` |
| BIOS / SATA | Automatic, 4 GiB swap | Cold | PASS | `.qemu-tests/bios-j1uvj6i3/` |
| UEFI / VirtIO | Manual GPT, 512 MiB ESP | Warm | PASS | `.qemu-tests/uefi-bur1qq9g/` |
| BIOS / SCSI | Manual GPT, 2 MiB BIOS boot | Warm | PASS | `.qemu-tests/bios-azk4x5d5/` |

Every first desktop boot required first-login completion, active SDDM and
NetworkManager, a persistent Waybar process with an actual compositor layer,
no Hyprland config errors, active PipeWire/WirePlumber, removal of temporary
installer privileges/shims, real ELF systemctl, and a captured screenshot.
All four screenshots were inspected. UEFI also passed an unchanged second boot.
The exact candidate's UEFI/GRUB and BIOS/Syslinux firmware live smoke tests pass.

**Remaining release gates:** human TUI/partition-shell use, Full application
profile acceptance, physical Intel/AMD and supported NVIDIA driver testing,
Wi-Fi/audio playback, suspend/resume and external displays. QEMU cannot certify
universal x86_64 hardware compatibility. Keep the release as a candidate/draft.

### Exact-image verification

Rebuild **succeeded**, including checksum verification:
`out/waybar-fix-20261101T053308Z/hyprflux-2026.11.01-x86_64.iso`.
SHA256: `bde9a9941e898926f3aa47f0470d391cabae9cd9734f1795c6fc83987e1f24eb`.
Build evidence: `/tmp/opencode/waybar-fix-iso-build-exec.log` ends with `Done!`
and `hyprflux-2026.11.01-x86_64.iso: OK`.

Clean UEFI/NVMe installation with `--embedded --profile desktop` **passed**:
`/tmp/opencode/waybar-fixed-embedded-uefi-install.log` reports
`HYPRFLUX_TEST_INSTALL_PASS`. Its **first** installed-desktop boot, with fresh
OVMF variables, also **passed**: `/tmp/opencode/waybar-fixed-first-boot.log`
reports `HYPRFLUX_TEST_BOOT_PASS`. This was not a resumed or manually repaired
installation; its recorded image digest matches the candidate above.

Inspected `.qemu-tests/uefi-_nvgsobl/desktop.png`: rendered Waybar and setup
completion notification. The serial log confirms an actual stable Waybar layer,
`all good!` for deprecated config, active audio services, and
`Installer cleanup verified; systemctl is ELF.` No temporary shims/sudoers
entries remained. These checks pass on the candidate's embedded installer.
Actual UEFI/GRUB firmware live smoke **passed**:
`/tmp/opencode/waybar-fixed-uefi-smoke.log` reports `HYPRFLUX_TEST_SMOKE_PASS`;
serial evidence `.qemu-tests/uefi-eq7vd_f5/serial.log`.
BIOS/Syslinux firmware live smoke **passed**:
`/tmp/opencode/waybar-fixed-bios-smoke.log` reports `HYPRFLUX_TEST_SMOKE_PASS`;
serial evidence `.qemu-tests/bios-kwtc8cpk/serial.log`.
Clean embedded installation state: `.qemu-tests/uefi-_nvgsobl/`.
The user approved deleting only the two superseded disks
`.qemu-tests/uefi-bf7nedxy/disk.qcow2` and
`.qemu-tests/bios-0cgr5phq/disk.qcow2` to continue testing. Acquired each runner
lock, preserved image metadata and a removal note, and deleted those exact
files. Their logs/screenshots/source snapshots remain; those two older VMs can
no longer boot. All other test disks and ISOs remain. Free space returned to
27 GiB.

Started a clean embedded **BIOS/SATA + 4 GiB swap** install of this same image:
`sh_195e4825e001V8LhNVqE8uiZet`,
`/tmp/opencode/waybar-fixed-embedded-bios-install.log`.
BIOS/SATA + swap installation **passed** (`HYPRFLUX_TEST_INSTALL_PASS` in
`/tmp/opencode/waybar-fixed-embedded-bios-install.log`), as did its **first
desktop boot** (`HYPRFLUX_TEST_BOOT_PASS` in
`/tmp/opencode/waybar-fixed-bios-first-boot.log`). Inspected
`.qemu-tests/bios-j1uvj6i3/desktop.png`: rendered bar and first-boot completion.
Both cold-cache automatic installation paths now pass for the corrected image.
The unchanged-disk second UEFI boot also **passed**:
`/tmp/opencode/waybar-fixed-second-boot.log` reports `HYPRFLUX_TEST_BOOT_PASS`.
Both first-login and subsequent-session startup now pass for this exact image.
The corrected-image BIOS/SATA + swap install state is
`.qemu-tests/bios-j1uvj6i3/`.

Added a VM `--manual-layout` fixture that prepares an independent GPT layout,
then invokes actual embedded `step_disk_manual` validation and installs. UEFI
uses a 512 MiB ESP; BIOS uses a 2 MiB BIOS boot partition. No swap is supported
in this fixture. This is not human TUI/partition-shell acceptance.

Clean UEFI/VirtIO embedded manual-GPT installation **passed**:
`/tmp/opencode/waybar-fixed-manual-cached-install.log` reports
`HYPRFLUX_TEST_INSTALL_PASS`, state `.qemu-tests/uefi-bur1qq9g/`. Its serial log
confirms actual `Partitions verified.` and seeding 1440 cached package/signature
files. Metadata records `layout=manual-gpt`, `embedded=true`, `profile=desktop`.
Its **first desktop boot also passed**: `HYPRFLUX_TEST_BOOT_PASS` in
`/tmp/opencode/waybar-fixed-manual-first-boot.log`. Inspected the screenshot:
Waybar rendered and first-boot completion visible, with no config warning.

Measured source-snapshot-to-install completion: **11.5 minutes** for this cached
manual run versus **40.0 minutes** for prior cold UEFI/NVMe and **40.8 minutes**
for cold BIOS/SATA runs. This is observational timing across different runs,
not a controlled benchmark isolating cache effect.

The user subsequently approved removing only the two superseded pre-fix disks
`.qemu-tests/uefi-8yts3wbb/disk.qcow2` and
`.qemu-tests/bios-s7431poy/disk.qcow2`. Acquired their runner locks, saved image
metadata/removal notes, and removed those exact files. All their diagnostics,
screenshots/config backups remain; all three corrected-image test disks and
every ISO remain. Free space returned to 25 GiB.

Clean embedded **BIOS/SCSI manual-GPT** installation and first desktop boot
**passed**: `HYPRFLUX_TEST_INSTALL_PASS` in
`/tmp/opencode/waybar-fixed-bios-manual-cached-install.log`, and
`HYPRFLUX_TEST_BOOT_PASS` in
`/tmp/opencode/waybar-fixed-bios-manual-first-boot.log`.
State `.qemu-tests/bios-azk4x5d5/`; screenshot inspected. Install elapsed time
was 11.2 minutes from source snapshot to completion. No VM tasks remain running
at this checkpoint. Production ISO sources have not changed.

### Quick-test cache improvement

Added optional `--package-cache DIR`
for subsequent new/resumed runs: a separate read-only 9p share seeds regular
package/signature files into the target without overwriting existing cache
entries. Pacman still checks exact versions and signatures normally. Tests
cover skip-existing, partial-download and symlink behavior; all 39 tests,
ShellCheck and Python compilation pass. Real read-only 9p cache integration is
now verified by the successful manual-GPT installation above. Normal signature
validation was retained.

Under the completed UEFI run's lock, read-only-mounted that disk and copied
1440 package/signature files (1.8 GiB) into `.qemu-tests/package-cache/`. The
source disk was not modified, and no signatures were bypassed. This cache is
available to accelerate subsequent runs with `--package-cache`.

Added root-free manual-layout validation coverage (ten layout cases): valid
UEFI/ext4/vfat and BIOS GPT/MBR layouts pass; missing mounts, insufficient root
space, unsupported root/EFI filesystems, ambiguous parent disk and missing GPT
BIOS boot partition are rejected. This is mocked validation coverage, not a real
manual install or TUI-flow acceptance. Production scripts/image are unchanged.

## Historical build/recovery checkpoints (not current task state)

The old-image embedded BIOS/SATA installation passed:
`/tmp/opencode/final-embedded-bios-install.log` contains
`HYPRFLUX_TEST_INSTALL_PASS`, state `.qemu-tests/bios-s7431poy/`. It lacks the
new Waybar fixes; do not treat it as final-image acceptance.

The queued tmpfs rebuild failed because Docker's mount was non-executable:
package hooks reported `execv ... Permission denied`, then no initramfs existed.
No ISO was produced. The user explicitly approved deleting only `work/` and
`.test-tools/final-build.lHn5hp/`. Confirmed neither contained active mounts,
removed those two scratch trees, and reclaimed about 7.4 GiB (13 GiB free).
All ISOs, VM disks, source snapshots, package caches and test logs were retained.

Rebuild retry uses `--tmpfs /build-work:rw,exec,size=7g` and a new timestamped
output directory. Task `sh_19598e043001EhN09zBuY6eTc4`, host log
`/tmp/opencode/waybar-fix-iso-build-exec.log`. This retry succeeded and its
corrected-image UEFI acceptance is recorded above. No production installer
sources were edited during this build.

Added installed-boot assertions that temporary sudoers entries and shim paths
(including dangling links) are absent and `/usr/bin/systemctl` is ELF. Unit
coverage and the corrected-image UEFI guest acceptance run both pass.

**Focused fix validation passed:** `/tmp/opencode/uefi-waybar-json-fix-boot.log`
reports `HYPRFLUX_TEST_BOOT_PASS`. After resetting first-login completion, the
guest completed setup, retained Waybar, and exposed an actual Waybar layer after
the settling delay. Inspected its screenshot: rendered bar and setup-complete
notification, with no deprecation warning. This disk has focused fixes applied;
it is not an exact-image acceptance pass for the existing ISO.

Queued a new ISO build containing the validated JSONC and session-launch fixes:
task `sh_19449f75d001bCKTNB3TsFX23h`, host log
`/tmp/opencode/waybar-fix-iso-build.log`. It waits event-driven on the BIOS/SATA
run's `runner.lock` (no polling), then keeps that lock while building so do NOT
start a BIOS boot concurrently with the build. Work files use container tmpfs
after the VM finishes, avoiding another persistent 4+ GiB work tree. Output goes
to a timestamped `out/waybar-fix-*` subdirectory; old images/disks are preserved.
Space before queueing was about 9.9 GiB; a further clean install may need more
space once the current BIOS install and new image finish. No old evidence was
deleted. The build is memory-limited to 10 GiB (12 GiB including swap).

The verifier now also syncs journals/files before its terminal marker, so QEMU
shutdown does not discard the last diagnostics. Earlier post-test journal
inspection could not find a committed boot entry on the read-only mount.

**Concrete cause now captured:** the diagnostic Waybar launch rejects
`~/.config/waybar/Modules`: hardware module 16 replaces `hwmon-path` without a
trailing comma. Added a narrow post-module repair and actual JSON5 parsing of
all six active Waybar config/include files; malformed output is now fatal to
installation. Added `python-json5` (available in Arch extra) to required packages.
The proposed launcher also hit an unloaded-unit `reset-failed` error; made that
optional while keeping the actual service restart mandatory.

Earlier process-only boot checks could observe Waybar before its config parse
finished. Strengthened the verifier to recheck the process and require a real
Waybar compositor layer after the settling delay, before screenshot/success.

Applied artifacts generated by the updated production functions to the stopped
UEFI test disk, preserving broken `Modules` as `Modules-before-comma-fix` and
renaming the completion marker to `hyprflux-first-boot-done.before-comma-fix`.
Real `python-json5` in the isolated builder successfully parsed all six actual
guest files after repair. Updated only the test verifier otherwise; no checks
were bypassed. Focused reboot: `sh_19447cf29001V7FHlirgFvKcYZ`, host log
`/tmp/opencode/uefi-waybar-json-fix-boot.log`. All 35 regression tests and
ShellCheck pass. The existing ISO still lacks these new fixes.

The unchanged exact-image UEFI disk passed its second boot:
`/tmp/opencode/final-uefi-waybar-diagnostic.log` reports
`HYPRFLUX_TEST_BOOT_PASS` without invoking diagnostic recovery. This does not
erase its failed first boot; treat startup as intermittent and the image as
unaccepted.

Added a proposed reliability fix in the wrapper: a session-started Waybar user
service with journal logs, `Restart=on-failure`, and a five-start rate limit.
The session launcher synchronously imports Wayland/Hyprland environment and
waits for first-login GTK exports before starting the bar. It replaces the
pinned dots' direct unmanaged Waybar spawn. Tests verify ordering and bounded
restart configuration; all 34 tests and ShellCheck pass.

Focused VM validation is running using artifacts generated by that function on
the stopped UEFI test disk. Saved its previous startup configs as
`startup-before-waybar-service.lua` / `hyprland-before-waybar-service.lua` in the
run directory, and renamed the existing first-boot marker to
`hyprflux-first-boot-done.before-waybar-service` so setup must execute again.
No success marker was fabricated. Task `sh_19442da59001qItZJlYoqUxadE`, host log
`/tmp/opencode/uefi-waybar-service-boot.log`. This fix is NOT embedded in the
current ISO; a new image and full acceptance rerun will be necessary if it passes.

### Previous installed-desktop evidence

**Latest exact-image acceptance failure:** the embedded UEFI/NVMe install passed,
but its first installed boot failed because Waybar was absent after the 180 s
session wait. Hyprland and first-login GTK/audio configuration started. Do not
release this image based on earlier hot-loaded successes.

Failed evidence: `/tmp/opencode/final-embedded-uefi-boot.log` and the run's
archived serial logs; saved SDDM output at
`.qemu-tests/uefi-8yts3wbb/failed-wayland-session.log`. A read-only check confirms
the installed Waybar binary loads and prints its version, so no missing shared
library has been demonstrated.

Expanded only test failure diagnostics: if autostart has already failed, run a
bounded Waybar debug launch to capture errors, then retain the failed result.
This cannot turn a failed autostart into a passing acceptance test. Preserved
the prior verifier as `guest-verify-before-waybar-diagnostics.sh` on the host and
updated `/root/guest-verify.sh` on the stopped test disk. Diagnostic reboot:
`sh_194404a810015J7qV6ZivOPtkr`, `/tmp/opencode/final-uefi-waybar-diagnostic.log`.
The separate embedded BIOS/SATA installation remains running.

Clean BIOS/VirtIO installation `.qemu-tests/bios-0cgr5phq/` passed both
`HYPRFLUX_TEST_INSTALL_PASS` and `HYPRFLUX_TEST_BOOT_PASS`. Evidence:
`/tmp/opencode/bios-desktop-install.log`, `/tmp/opencode/bios-desktop-boot.log`,
and the run's `serial.log`/`desktop.png`. Inspected its screenshot: Waybar is
rendered and the first-boot completion notification is visible. `hyprctl
deprecated-config` reports `all good!`, validating the default-scale cleanup.
This was a new base installation, not a resumed or manually repaired disk.

A new ISO built successfully in `.test-tools/final-build.lHn5hp`, preserving the
previous build and ISO. Log: `/tmp/opencode/final-iso-build.log`. The build job's
post-build checksum command expected a local-date filename and exited 1; the
actual UTC-named image was produced successfully. Generated its sidecar
separately and verified `out/hyprflux-2026.10.31-x86_64.iso: OK`.
SHA256: `37fc0f64918ca8c9ccd6501d406aaa73cd86c929c078cf10e3d696faba12c584`.

Added `--embedded` to the VM runner to test `/root/hyprflux-install.sh` inside
the exact built ISO without hot-loading replacement installer scripts, and
record the image digest. Both firmware modes still need that final-image test.
The automated driver still replaces TUI prompts with test answers, so manual
flow acceptance is separate.

Exact-image tests now running:
- Clean UEFI/NVMe embedded-installer installation **passed**:
  `HYPRFLUX_TEST_INSTALL_PASS` in `/tmp/opencode/final-embedded-uefi-install.log`.
  State `.qemu-tests/uefi-8yts3wbb/`; its `image.sha256` matches the final ISO.
  Fresh-OVMF desktop boot is running: `sh_1943bfbd3001U7jKFwa7Lc2Pa5`,
  `/tmp/opencode/final-embedded-uefi-boot.log`.
- Clean BIOS/SATA embedded-installer installation now running:
  `sh_1943c1517001ufJgm9tzJ8BSi6`,
  `/tmp/opencode/final-embedded-bios-install.log`.
- Actual BIOS firmware-loader live smoke **passed**: `HYPRFLUX_TEST_SMOKE_PASS`
  in `/tmp/opencode/final-bios-firmware-smoke.log`; serial evidence:
  `.qemu-tests/bios-36i_k_y1/serial.log`.
- Actual UEFI/GRUB firmware-loader smoke **passed**: `HYPRFLUX_TEST_SMOKE_PASS`
  in `/tmp/opencode/final-uefi-firmware-smoke.log`; serial evidence:
  `.qemu-tests/uefi-djdyp17t/serial.log`.

The exact-image full install state is `.qemu-tests/uefi-8yts3wbb/`. Its serial
log explicitly confirms `Testing the ISO embedded installer at
/root/hyprflux-install.sh` and correct NVMe partition names (`nvme0n1p1/p2`).
It completed despite mirror-rating timeouts, validating target GRUB/root UUID,
initramfs disk modules and the real systemctl before reporting success.

Only one full installation is running. Disk space was 14 GiB after the UEFI install;
keep all old evidence and monitor the harness's 2 GiB safety floor. Do not treat
the build or checksum as final installation acceptance.

Latest-source UEFI integration and boot both passed:
`/tmp/opencode/uefi-resume-current-source.log` reports
`HYPRFLUX_TEST_INSTALL_PASS`, and `/tmp/opencode/uefi-current-source-boot.log`
reports `HYPRFLUX_TEST_BOOT_PASS`. Inspected the updated screenshot: Waybar is
rendered along the top edge. Early layer diagnostics preceded its surface
creation; the later screenshot confirms rendering.

The deprecation is `dwindle.special_scale_factor`. Added a narrow post-dotfile
normalization that removes only redundant default values of 1, preserving custom
non-default scales; regression coverage and ShellCheck pass. This newest change
still needs in-guest validation.

Started a **clean BIOS/VirtIO Desktop-profile installation** on a new disposable
disk, without resuming or modifying the UEFI disk:

```bash
python3 tests/qemu-smoke.py --install --bios --disk-bus virtio --profile desktop out/hyprflux-2026.10.30-x86_64.iso
```

Task: `sh_193f7048a001LtNlbbhPecllR6`;
host log: `/tmp/opencode/bios-desktop-install.log`. This tests current hot-loaded
source using the older live ISO; the final rebuilt image still needs its own
full acceptance tests.

### Earlier UEFI evidence and diagnosis

The focused corrected-disk test completed end to end with
`HYPRFLUX_TEST_BOOT_PASS` in `/tmp/opencode/uefi-desktop-boot-socket-fix.log`.
Inspected `.qemu-tests/uefi-bf7nedxy/desktop.png` (1280x800, 989 KiB): the actual
Hyprland desktop wallpaper is visible. Session checks confirmed SDDM,
NetworkManager, Hyprland, Waybar, first-login completion, no config errors,
PipeWire and WirePlumber. Fresh OVMF variables exercised the UEFI fallback path.

The screenshot shows a deprecated-config warning; collect its details before
release. Waybar was running, but its rendered bar is not visible in this early
capture. Added layer diagnostics and a short pre-capture settling delay.
This success is for a recovered test disk with the generated first-login fix,
not a clean install or certification of the old ISO's embedded installer.

Latest-source integration resume passed on the same disk, including the
first-login export fix and stricter package/file checks through the wrapper.
Task: `sh_193f37334001Z0tMvpUGS2pV5p`; host log:
`/tmp/opencode/uefi-resume-current-source.log` contains
`HYPRFLUX_TEST_INSTALL_PASS`. Repeating the installed boot with deprecation and
layer diagnostics: task `sh_193f57e29001bVYaqsvNojbg1L`, host log
`/tmp/opencode/uefi-current-source-boot.log`. Next: BIOS and rebuilt exact-image
installation acceptance.

The Desktop-profile resume completed with `HYPRFLUX_TEST_INSTALL_PASS` and
created `.qemu-tests/uefi-bf7nedxy/installed.ok`. It rebuilt the target initramfs,
validated its real systemctl and disk modules, matched GRUB's root UUID, and
reported `config ok`. A nonfatal `pipewire.sh` warning remains; actual audio
startup must pass the installed-session check.

Installation serial evidence is preserved at
`.qemu-tests/uefi-bf7nedxy/previous-attempts/1793482895640978214/serial.log`;
host result: `/tmp/opencode/uefi-resume-desktop.log`.

Started `python3 tests/qemu-smoke.py --boot .qemu-tests/uefi-bf7nedxy --3d`
with fresh UEFI variables. Host log: `/tmp/opencode/uefi-desktop-boot.log`;
background task: `sh_193e930e3001zfZo2D32lT0Ku3`. This boot failed validation:
SDDM and NetworkManager were active and Hyprland/Waybar processes existed, but
the first-boot completion marker was absent. Recovered first-boot logs show GTK
settings applied and PipeWire links created, with no completion marker.

Expanded test-only boot failure diagnostics to capture processes, user jobs,
first-boot log and journal before emitting the failure marker, including explicit
exit failures. Preserved the old verifier as
`.qemu-tests/uefi-bf7nedxy/guest-verify-before-diagnostics.sh` and updated only
`/root/guest-verify.sh` on the stopped test disk; no installer or desktop checks
were bypassed. A second boot is running to locate the stalled first-login task:
`sh_193eccbd3001dNNDSpEXeR5nbp`, host log
`/tmp/opencode/uefi-desktop-boot-diagnostics.log`.

The diagnostic boot also failed. It showed no blocked first-boot process or user
jobs: the script had finished unsuccessfully, not stalled. `nwg-look -a` tried
to restore `~/.local/share/nwg-look/gsettings`, absent on a fresh install. Changed
the generated script to `nwg-look -x` to export the settings just applied with
gsettings. The regression fixture now rejects `-a` and requires a GTK export.
All 28 tests and ShellCheck pass with this fix.

For a focused boot retest, regenerated the first-boot script verbatim from the
updated wrapper and installed it on the stopped test disk. Preserved the prior
script at `first-boot-before-export-fix.sh` and recorded the new script hash at
`first-boot-fix.sha256` inside the run directory. No marker was fabricated and no
acceptance check was relaxed. This is a focused fix test, not a fresh install or
exact-image certification; the full pipeline must run again with current source.
Boot task: `sh_193f04e19001MeO0Uzxw9stcHI`;
host log: `/tmp/opencode/uefi-desktop-boot-export-fix.log`.

That boot produced **`HYPRFLUX_TEST_BOOT_PASS`** in the guest: the completion
marker existed, Hyprland had no config errors, a 1280x800 DRM monitor was active,
and PipeWire/WirePlumber were active. The host runner then failed capturing the
EGL display via QMP (`no surface`), so this was not a successful end-to-end test.
Added required in-guest `grim` screenshot capture with bounded PNG/base64
transfer over serial and host decoding; old verifiers retain QMP fallback.
Regression tests cover incomplete, malformed and non-PNG transfers.

Updated only the test verifier on the stopped disk, preserving its previous
version as `guest-verify-before-guest-capture.sh`. Retest task:
`sh_193f189b2001T33uZ1szROWra3`; host log:
`/tmp/opencode/uefi-desktop-boot-guest-capture.log`. Awaiting end-to-end result
and screenshot inspection.

The guest-capture retest reached successful desktop/audio checks, then failed
before capture because `find -type s` attempted to stat user portal/FUSE mounts
as root. Replaced that with direct `wayland-*` socket checks (ignoring lock
files). Added a real Unix-socket regression test; all 30 tests and ShellCheck
pass. Preserved the prior verifier as `guest-verify-before-socket-glob.sh` and
installed the corrected verifier on the stopped test disk. Current boot task:
`sh_193f23e44001mue36M3VACXbZR`; host log:
`/tmp/opencode/uefi-desktop-boot-socket-fix.log`.

Other observed issues still to investigate: duplicate Swaync startup attempts,
GTK theme parser warnings, and missing RTKit service warnings from PipeWire.

### Recovery history

Command:

```bash
python3 tests/qemu-smoke.py --install --swap 4 --disk-bus scsi out/hyprflux-2026.10.30-x86_64.iso
```

State: `.qemu-tests/uefi-bf7nedxy/`.
The initial attempt completed base installation and system configuration, then
failed its first desktop-package transaction because the mirror reset the
`qt6-declarative` download connection. No desktop package changes were committed.
Recovered evidence: `.qemu-tests/uefi-bf7nedxy/recovered-wrapper.log`.

Added bounded package retries and fallback mirrors, safe reuse of clean pinned
checkouts, and `--resume` to preserve partitions/packages/downloads. Automated
error dialogs no longer wait for an Enter key.

Retry command:

```bash
python3 tests/qemu-smoke.py --resume .qemu-tests/uefi-bf7nedxy out/hyprflux-2026.10.30-x86_64.iso
```

That retry exhausted its three attempts after further mirror timeouts. Downloads
were retained (remaining download fell through 124.34 and 96.03 MiB). Added
mirror-priority rotation between retries, with a regression test proving no
servers are lost. Started another resume on the same test disk.

The following attempt encountered a stale pacman lock. Diagnosed that the test
harness emitted failure before syncing/unmounting, allowing QEMU to stop before
guest lock removal was persisted. Fixed failure cleanup and restored its EXIT
trap after sourcing the TUI library. Added fail-closed stale-lock recovery: it
refuses removal when a package manager is running or process inspection fails.

Previous host log: `/tmp/opencode/uefi-resume-safe-cleanup.log`.
The latest guest has confirmed safe stale-lock removal, reuse of the pinned
checkout, and entry into the desktop transaction with 95.74 MiB left to download.
It subsequently installed the core desktop and yay, and entered the HyprFlux
application bundle. Read-only VT2 diagnostics identified further network/DNS
timeouts in one package chunk, not a missing package or dependency conflict.

Added `qemu-console.py` to inspect the running VM without stopping installation.
An isolated probe against the guest's installed **Hyprland 0.57.0** found that
config verification now requires `XDG_RUNTIME_DIR`. Fixed final chroot validation
to create a short, private, user-owned runtime and clean it on success/failure.
The real guest source-config probe now reports `config ok` and
`HYPRFLUX_CONFIG_PROBE_RESULT=0`; regression tests cover runtime permissions,
short path length, and cleanup after both successful and failed verification.

That run was interrupted by a server restart. Its application batch timed out
before the AUR section, leaving Waybar missing. Added explicit Desktop/Full
profiles and required desktop-first ordering rather than allowing optional bulk
downloads to prevent a functional session.

Successful resume:

```bash
python3 tests/qemu-smoke.py --resume .qemu-tests/uefi-bf7nedxy --profile desktop out/hyprflux-2026.10.30-x86_64.iso
```

Completed background shell task: `sh_193cd2c86001QaQpcxWKBRtCkE`.
Host log: `/tmp/opencode/uefi-resume-desktop.log`.
This snapshot includes the runtime fix. All 85 required repository package names
exist in builder metadata.
Added wireless-regdb and its firmware files to live/target initramfs configuration.

The latest source additionally requires registered Waybar/wlogout packages and
checks their installed files. This last readiness change postdates the active
snapshot and must be included in the final exact-image test. Do not change the
active snapshot to bypass or alter validation.
The resumed guest has confirmed that it preserved the existing partitions and
packages and reached the desktop transaction. Its remaining download was
189.93 MiB versus the initial 321.21 MiB, demonstrating package-cache reuse.
Do not launch another full installation concurrently: host free space is limited.

Once installation reports success, run:

```bash
python3 tests/qemu-smoke.py --boot .qemu-tests/uefi-bf7nedxy --3d --render-node /dev/dri/renderD128
```

Then verify a BIOS installation and boot, manual layouts, and remaining hardware
checks from `tests/README.md`.

## Release caveat

The ISO's embedded installer predates the latest source edits. Hot-loaded VM
tests exercise their per-run source snapshot (`source.sha256`), not necessarily
the embedded installer. After fixes stabilize, rebuild and validate the final
exact image before publishing. Releases currently remain drafts.

Unrelated `node_modules/`, `package.json`, and `pnpm-lock.yaml` were not modified.
