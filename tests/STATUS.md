# Hardening verification status

This is a progress checkpoint, **not production certification**.

## Deep exact-image KVM verification — 2026-11-06, complete

**Final outcome: all six clean VM cases PASS on one exact final ISO.**

| Profile | Firmware | Layout | Install | Desktop boot | Offline second boot | Visual review |
|---|---|---|---|---|---|---|
| Desktop | UEFI | Automatic, NVMe/swap | PASS | PASS | PASS | PASS |
| Desktop | BIOS | Automatic, SATA/swap | PASS | PASS | PASS | PASS |
| Desktop | UEFI | Manual GPT, SCSI | PASS | PASS | PASS | PASS |
| Desktop | BIOS | Manual GPT, VirtIO | PASS | PASS | PASS | PASS |
| Full | UEFI | Automatic, NVMe | PASS | PASS | PASS | PASS |
| Full | BIOS | Automatic, SATA/swap | PASS | PASS | PASS | PASS |

Final ISO:
`/drive-data/HyprFlux-ISO/production-final-20261106-build/out/build-20261105T224215Z-1/hyprflux-2026.11.05-x86_64.iso`

SHA256: `6fb9e974befcd6f00694ea1e016c1083850956f1524349ea66074bb1c550f7f0`.

Evidence directory: `/drive-data/HyprFlux-ISO/qemu-tests/production-final-20261106/`.
`acceptance-report.json` requires all six cases and reports no missing cases.
`results.json` is reconciled with independent `visual-review.json`: no screenshot
review remains pending. Final Full BIOS state `bios-fn6u35cl` also passes the
extended-package presence audit. All 108 builder regressions pass.

Additional final-image checks: real UEFI/BIOS ISO firmware loaders, offline live
keyring initialization, undersized real-ext4 rejection, embedded cyan/yellow TUI
preview, 4 GiB/swap/NTP-off install, actual SDDM password login, fresh-NVRAM EFI
fallback boots, system D-Bus XML, temporary-grant/shim cleanup, effective sudo
authentication, terminal windows/blur, cyan GTK/icon settings and virtual HDA
PipeWire streaming. Overlay-only signed Papirus reinstall hook plus inspected
Thunar/Firefox/Chromium UI also pass; that overlay never counts as a clean case.

**Not production certification:** physical Intel/AMD/NVIDIA, Wi-Fi, audible audio,
suspend/resume and external monitors remain untested. Human end-to-end TUI and
manual partition-shell acceptance are not replaced by these automated fixtures.
Browser screenshots certify launch/render only, not media or all app workflows.
Online repositories can change after testing. Publisher signing with a separately
trusted fingerprint remains outstanding; a checksum is not authentication.
No public release was published. Shared fixes are pushed upstream; accumulated
ISO changes remain uncommitted/unpushed. Historical running entries below are
checkpoint provenance, not the current completion state.

Final **Desktop BIOS manual PASS** (`bios-jpxqj63i`): clean manual GPT/VirtIO
install, desktop first boot and offline second cold boot. Terminal/blur and
actual-theme greeter screenshots inspected. All four Desktop layout/firmware
combinations and Full UEFI now pass on the final image (5/6 cases).
Final Full BIOS automatic checkpoint running as `sh_1ae575b72001f1X6ELuH16OESy`.
Acceptance reporting now explicitly requires all six cases (including Full BIOS)
and regression-checks maintenance-state exclusion. All 108 builder regressions
pass after that report-only change; the production ISO is unchanged.
UEFI installed boots use fresh OVMF variable templates on every invocation
(`tests/qemu-smoke.py`), exercising fallback EFI boot without retained NVRAM.

Final **Desktop UEFI manual PASS** (`uefi-y7lvv38t`): actual manual GPT/ext4
validation and clean SCSI install, strict desktop first boot and offline second
boot. Terminal/blur and actual-theme greeter screenshots inspected and retained.
Final matrix is now 4/6 cases passed. BIOS manual checkpoint running as
`sh_1ae47ad75001A65KdrtP3t6eBi`; Full BIOS remains after it.

Final **Desktop BIOS automatic PASS** (`bios-yw21uft2`): clean SATA/swap install,
strict first desktop boot and offline second cold boot. Terminal/blur and actual
SDDM-theme screenshots inspected and recorded in the independent visual ledger.
Evidence exported before the completed disposable disk was retired by workflow;
clean UEFI Desktop/Full disks are still retained for inspection.
UEFI manual-layout checkpoint running as `sh_1ae382b3f001IuuiMynGfLLOxl`;
BIOS manual and Full BIOS are next. Automated manual tests validate real GPT/ext4
and mount paths but do not certify a human's partition-shell/TUI interaction.

Final **Full UEFI PASS** (`uefi-jm1wehju`): clean install, strict desktop boot and
offline second cold boot, virtual audio, cleanup/sudo/D-Bus checks. Terminal and
actual-theme greeter screenshots inspected; visible terminal blur and prompts.
Exported full package audit confirms extended bundle installed, including
waybar-git, VS Code, 64gram, Vesktop, LocalSend, Kdenlive and CLI tools.
Package-log review retained in `full-uefi-package-audit.txt`: mirror-rating and
slow npm warnings recovered; chroot/display-deferred warnings remain visible.
Live package scriptlet reports the deliberately test-masked tty1 getty, while
the installed desktop boots successfully. No package failure was found in the
extended-bundle audit. Package presence does not certify every app's functionality.

Desktop BIOS automatic checkpoint now running as `sh_1ae2838f9001YKWFX8G9p1kRnq`.
Manual UEFI/BIOS and Full BIOS remain pending on the same exact final image.

Maintenance visual retest PASSES: explicit window-address focus and active-window
plus workspace assertions produce real Thunar, Firefox and Chromium screenshots.
Inspected all three: cyan folders visible in Thunar, browser UI rendered normally.
Evidence: final workflow `maintenance-focused-*.png`,
`maintenance-focused-evidence.tar`, and `maintenance-result.json`.
This is launch/render smoke, NOT webpage, media or hardware-acceleration coverage.
Earlier wallpaper-only screenshots remain retained/excluded; no production code
or clean backing disk changed. The overlay is never a clean matrix case.

Final maintenance overlay: real signed same-version Papirus reinstall executes
the actual hook and restores cyan successfully. Thunar, Firefox and Chromium all
map with normal sandboxing after the root-service fixture imports graphical
session DISPLAY/XAUTHORITY. This is not an ISO defect or clean matrix pass.
Screenshot inspection found wallpaper-only app captures, so visual acceptance
is explicitly withheld; retesting with window-address focus plus active window
and workspace assertions. Prior screenshots/logs are retained, not hidden.

Final-image Full UEFI clean install checkpoint is now running as
`sh_1ae04dfe7001eKgTNQSu9Bvv4z`; remaining BIOS/manual checkpoints still pending.

**Final hardened candidate built:**
`/drive-data/HyprFlux-ISO/production-final-20261106-build/out/build-20261105T224215Z-1/hyprflux-2026.11.05-x86_64.iso`
SHA256 `6fb9e974befcd6f00694ea1e016c1083850956f1524349ea66074bb1c550f7f0`.
Its UEFI/BIOS firmware, offline live/keyring/real-small-ext4 rejection, embedded
UI preview and CLEAN Desktop UEFI install/boot+offline second boot all pass.
Desktop uses 4 GiB, swap, NTP disabled, real SDDM password login and virtual HDA.
Strict sudo-auth, D-Bus, terminals/blur, cyan links and actual-theme greeter checks
pass; screenshots inspected and recorded in the FINAL workflow's visual ledger.
State: `uefi-je35ncr9`.

Stopped only the now-superseded intermediate Full coordinator/harness/VM to free
RAM for final-image testing. Its package installation had completed, but no boot
or final-image pass is claimed; cancellation/provenance remains in the old
workflow directory. The installed intermediate disk is not used for final tests.

Task `sh_1adfd5d74001ThH375f1NQe7W8` now runs the FINAL candidate's additional
maintenance/app smoke on a read-only-backed overlay of the clean Desktop disk.
It cannot change or fill the clean parent matrix case. After that checkpoint,
continue `production-final-20261106/continue.py full-uefi`, then Desktop BIOS,
both manual-layout cases, and Full BIOS, one resource-safe checkpoint at a time.

First candidate (`c798711be064a6a09b0dc419ae78daa70215c3ca811f1a44301e66f1db76ddeb`)
passed both firmware loaders, offline live/keyring/real low-space rejection,
embedded UI preview and clean Desktop UEFI/NVMe with 4 GiB/swap/NTP-off/real
password login/virtual HDA. Its second installed boot passed with networking
blocked. Terminal/greeter/UI screenshots were inspected; blur is visible on both
terminals and the actual theme renders. A normal Hyprland update-news dialog is
visible, not a configuration error. Effective unrestricted passwordless sudo is
also rejected. See that workflow's independent `visual-review.json` ledger.

The deeper audit found a failure-path gap: upstream `scripts/zsh.sh` can create
`/etc/sudoers.d/99-hyprflux-temp`, but the ISO outer cleanup covered only its own
grant. Added outer revocation and a regression fixture for that extra grant.
Added fail-closed installer postcondition validation for system D-Bus XML, so a
malformed policy is rejected before claiming a bootable desktop. No invalid file
is deleted or silently repaired. **108 builder regressions pass.**

Because this changes production code, the first image is explicitly superseded
for final acceptance; its bounded Full UEFI attempt `sh_1add7c5c5001x9A2RkPSOBNr3X`
may finish as intermediate evidence, never as the final image's pass.
`production-20261106/continue.py` now refuses further cases for the superseded
candidate. No repairs or old-image successes fill the new matrix.

Final-candidate task `sh_1ade063110016bDobAf1b6Ogoh` freezes the hardened source,
builds under `/drive-data/HyprFlux-ISO/production-final-20261106-build/`, and repeats
firmware/offline/UI/Desktop-first checks. Continue subsequent cases from
`.qemu-tests/production-final-20261106/continue.py` after each checkpoint.
The application/real-Papirus-upgrade-hook overlay test was deferred due to host
memory pressure; rerun the FINAL workflow's `maintenance.py` when the main test
VM has stopped. It uses a read-only-backed overlay and cannot count as a clean
matrix case or modify the clean parent disk. Thunar/Firefox/Chromium screenshots
and a signed same-version Papirus reinstall exercise actual app/hook behavior.

The user requested autonomous thorough verification and authorized generated
artifact cleanup. No physical disks or unrelated/user interactive VMs are used.
Retired only unused superseded test qcow2 disks and old completed build scratch,
retaining serial logs, source snapshots, screenshots, metadata and the latest
prior ISO/clean Desktop disk. Recovered signed cache pairs before retiring the
old repaired Full disk; full logs were exported first. External free space rose
to about 103 GiB. Cleanup ledger: `production-artifact-cleanup.log`.

Investigated the upstream CI crash in isolated current-Arch containers: Hyprland
0.57.1's first root headless verify can segfault even on a minimal config, while
unprivileged checks parse successfully. Published focused upstream CI fix
`74735688a2703a717694518b5699e79991c33a74`; verification uses an isolated
unprivileged HOME/private short runtime, with no root compositor override.
A real intentional-invalid-config test must fail without segfault/retry.
All **9 upstream tests and the complete upstream CI PASS**:
https://github.com/ahmad9059/HyprFlux/actions/runs/42117448389
The ISO now pins this revision. This does not alter actual compositor startup.

Added read-only D-Bus policy checks and optional recorded virtual-HDA/PipeWire
streaming checks (null host output, NOT hardware audio certification). **106 ISO
builder regressions PASS, no skips**; ShellCheck and whitespace checks pass.
KVM/QMP preflight passes. All build/cache/temp/ISO/VM artifacts use `/drive-data`.

Task `sh_1adbf181f001YXoGnWS7eQSt0B` freezes the current source, builds a fresh
default-xz candidate with curated signed online cache, tests real UEFI/BIOS ISO
loaders, offline live/keyring/low-space guards, embedded UI preview, and then a
clean Desktop UEFI/NVMe 4 GiB/swap/NTP-off/password-login/virtual-audio install.
It also checks a second cold installed boot with guest external network blocked.
Evidence: `/drive-data/HyprFlux-ISO/qemu-tests/production-20261106/`.

Further checkpoints queued in that directory's `continue.py`: clean Full UEFI,
Desktop BIOS automatic, Desktop UEFI/BIOS manual, and Full BIOS. Each case uses
the SAME exact ISO, checks initial and offline second boots, and exports logs and
terminal/greeter screenshots before retiring only completed disposable disks if
needed. A repair/resume never fills a clean matrix slot. Failures remain failures
until diagnosed/retested; do not claim completion from the build/regressions.
No public release, publisher signing or physical-hardware certification is planned.

## Desktop ownership migration — 2026-11-06

At the user's request, moved shared desktop fixes out of the ISO and into the
actual HyprFlux source repo (`../HyprFlux`, not a reference checkout). The user
explicitly authorized focused upstream commits and pushes. Published to main:

- `42aabc062c3f294b95ae764409fea0d827b7a104`: Foot syntax/blur and palette generator,
  mirrored base-dots configs, shared Kitty launcher, cyan Papirus helper/hook,
  SDDM Qt dependencies, repeatable theme copy, and desktop regression tests/CI.
- `96535f47357b3b53ef03219bd6f4d65d0a3e174b`: remove the redundant/deprecated
  workspace scale from both source trees rather than stripping it in the ISO.

The ISO now pins the latter published SHA. Removed all three duplicate ISO
desktop-fix utilities, their target-copy/hook creation, the temporary theme-module
sed adaptation, Foot/default normalization, and the obsolete Waybar hwmon repair
(already fixed in upstream hardware detection). Retained read-only config and
package validation, strict guest desktop checks, and genuinely chroot/offline
session adaptations. Source ownership guidance is in AGENTS.md and phase 5.

**8 upstream tests pass (including real Foot parsing); 104 ISO builder tests
pass with no skips.** Config parity, color-generator freshness, ShellCheck and
whitespace checks pass. The upstream remote main SHA was verified after push.
GitHub CI's shared desktop tests pass, but its separate Hyprland headless
`--verify-config` command segfaults (exit 139). This failure is NOT suppressed or
claimed resolved: https://github.com/ahmad9059/HyprFlux/actions/runs/42107728102
Failed log: `/drive-data/HyprFlux-ISO/upstream-migration-ci-failure.log`.

No new ISO or installed-VM matrix was built/run for this ownership migration.
All existing images and Desktop/Full evidence below retain their old pins;
they do not certify this new source pin. The accumulated ISO-repo changes remain
uncommitted/unpushed; no unrelated user work was staged or discarded. Upstream
HyprFlux's working tree is clean after the focused published commits.

## Verification continued — 2026-11-05

**Final recovery outcome: PASS. No verification workflow remains running.**
After preserving the interrupted-install orphan files, Full passed the normal
strict boot verifier (`HYPRFLUX_TEST_BOOT_PASS`), real terminal/cyan-folder checks
and actual-theme greeter rendering. Full's strict application package audit had
already passed. Extracted and visually inspected both terminal/blur and themed
greeter screenshots, retained as `full-recovered-terminals-blur.png` and
`full-recovered-themed-greeter.png` in `desktop-fixes-20261103/`.

The corrected image now has: 105 builder tests passed, both firmware loaders
passed, CLEAN embedded Desktop install/boot passed with inspected screenshots,
and repaired/resumed Full package-audit/boot passed with inspected screenshots.
It does NOT have a clean Full pass or complete five-case/hardware acceptance.
The ISO is unchanged by diagnostic guest repairs and is available for user
testing; no release certification, commit, push or signing was performed.

D-Bus diagnosis found a specific interrupted-install orphan:
`/usr/share/dbus-1/system.d/com.redhat.tuned.conf` was zero bytes and not owned by
any registered package. All other regular system policy .conf files parsed as
XML. D-Bus/dbus-broker packages passed full package-file integrity checks. Saved
metadata/policies and ownership/parse evidence as `recovered-pacman-local.tar`,
`recovered-dbus-policies.tar`, and `invalid-dbus-policies.json` in the evidence
directory. Preserved only the empty unowned Tuned policy in the guest's existing
quarantine directory; did NOT weaken or remove a valid security policy.

Restored the original strict guest verifier. Task
`sh_1a86e38fe001d3UgZkRJZD6zvV` retries boot (not installation) with normal strict
desktop checks; log `full-recovered-boot-after-policy-quarantine-20261105.log`.
Production code/ISO remain unchanged; this disk is still repaired recovery
evidence, never a clean-install acceptance substitute.

The post-quarantine Full recovery completed and passed the strict application
package audit. Its subsequent boot FAILED: system D-Bus refused connections,
NetworkManager was inactive, and logind could not start user runtime/services.
No Hyprland user session started. Therefore this is NOT a working Full desktop,
even as recovered evidence. Result:
`full-continuation-20261105-after-quarantine.json`.

Task `sh_1a86d4de3001PbNICnUTooVQ2S` boots that same disposable disk only to
collect failed units, D-Bus unit configuration, package integrity and service
journal evidence. It intentionally reports diagnosis-only failure; it cannot
produce an acceptance pass. The original verifier is backed up as
`full-verifier-before-dbus-diagnosis.sh` before the diagnostic-only guest copy
replaces it. No production source or ISO has changed.

First recovery attempt failed closed on Electron file conflicts. Read-only export
of pacman local metadata established that `electron43-43.8.6-1/desc` and `files`
were empty (interrupted package extraction/registration), and no other registered
package claimed any path under `/usr/lib/electron43`, `/usr/bin/electron43`,
`/usr/share/licenses/electron43` or `/usr/share/pixmaps/electron43.png`.
Ownership evidence: `desktop-fixes-20261103/interrupted-electron-ownership.txt`;
original metadata archive: `interrupted-pacman-local.tar`.

Moved only those unowned Electron paths and the empty package record into
`/var/log/hyprflux-interrupted-electron43-20261105/` on the STOPPED disposable
Full VM disk. All contents preserved; no --overwrite, signature-policy change,
production-source change or host desktop mutation. Task
`sh_1a82150e90018VLq1E0sgWRJij` retries normal recovery and then boot verification.
Log: `desktop-fixes-20261103/continuation-20261105-after-quarantine.log`.
Even if successful, this repaired/interrupted Full installation is recovery
evidence only and remains excluded from clean exact-image acceptance.

The user stopped the previous Full install, then explicitly requested continuation.
The ISO and production-source checksums still match the completed Desktop
candidate: `/drive-data/HyprFlux-ISO/desktop-fixes-build/out/build-20261103T181615Z-1/hyprflux-2026.11.03-x86_64.iso`,
SHA256 `aee89718f1158c9079c76790e870c3d0c75b3229b92a802e0299baefd4c02bbd`.

105 builder tests, both firmware loaders and clean embedded Desktop install/boot
passed. Desktop terminal and actual-theme greeter screenshots were extracted
read-only from `uefi-v0uhnfby` and inspected: both Kitty and Foot show shell
prompts and blur; the SDDM theme renders without the previous missing-module
screen. Cyan GTK theme/folder-link assertions passed. Screenshots are retained as
`desktop-fixes-20261103/desktop-terminals-blur.png` and `desktop-themed-greeter.png`.

Task `sh_1a8191225001YV36IzMIqG8Kp0` performs a bounded recovery of interrupted
Full test disk `uefi-c62l44zz`, then boot/strict desktop checks if recovery succeeds.
No repartitioning or rebuild; the completed Desktop test is not repeated. Because
Full was interrupted and now resumed, this outcome must remain recovery evidence,
NOT a clean Full or five-case matrix pass. The earlier cancellation record is
preserved. Progress/results: `desktop-fixes-20261103/continuation-20261105.log`
and `full-continuation-20261105.json`, all under external storage.

## Desktop-theme and terminal regressions — source fixes, runtime verification

Combined diagnostic checks now PASS, including mapped default terminal windows,
cyan folder/GTK assertions, Foot's real checker and actual-theme greeter mapping.
The initial side-by-side screenshot proved Foot's background was still sharp:
Foot 1.28 defaults its ext-background-effect blur request off. Added blur=yes to
colors-dark while preserving alpha=0.80; the subsequent screenshot
`/drive-data/HyprFlux-ISO/terminals-blur-fixed.png` was visually inspected and
shows working blur. No global Hyprland blur override was required.

New-image workflow: `desktop-fixes-20261103/run.py` builds on external storage,
checks both firmware loaders, then attempts a clean embedded Desktop and Full
UEFI/NVMe install+boot once each, independently. The full five-case acceptance
matrix is NOT covered by this run. This section's old "not built" statement below
describes the start of investigation, not a completed corrected-image result.
Running task: `sh_1a2a02939001r42G6Ide13lk4j`. Durable log:
`/drive-data/HyprFlux-ISO/qemu-tests/desktop-fixes-20261103/workflow.log`.
Retired only the two inactive previous build work directories to make space;
their ISOs, checksums, source snapshots and acceptance evidence are preserved.

User screenshots exposed gaps in the former acceptance criteria. All previous
desktop passes prove only the checks then implemented; they do not certify the
themed greeter, terminal usability, cyan folders or visible blur.

Confirmed against the pinned upstream and an isolated copy of the earlier clean
Desktop test disk (`theme-regression-diagnostic`, never the user's VM):

- Desktop omitted qt6-5compat; SDDM fell back after its actual theme failed the
  Qt5Compat.GraphicalEffects import. Dependency is now mandatory in both profiles.
  Installing the signed cached package in the diagnostic guest rendered the actual
  theme. Screenshot `/drive-data/HyprFlux-ISO/themed-greeter-diagnostic.png` inspected.
- The theme-module adaptation excluded the unavailable papirus-folders package,
  leaving no recoloring utility. A root helper now applies the cyan variants
  already shipped by signed Papirus, verifies folder links at every size, refreshes
  caches, and runs again through a Papirus upgrade hook. Diagnostic run changed
  385 variants. The green first-boot success icon is untouched.
- Foot's include was under colors-dark, used a relative path, and the included
  palette had hash-prefixed colors and bright8..15 keys. New post-module
  normalization fixes these, preserves alpha=0.80 and requires foot --check-config.
  The corrected config passed the real installed Foot 1.28 checker.
- Kitty failed even with --config NONE: VirtIO/virgl EGLConfig initialization,
  not its color config. LIBGL_ALWAYS_SOFTWARE=1 mapped a real Kitty window.
  A permanent local launcher applies that workaround only for DRM VirtIO devices,
  execs the untouched packaged binary, honors user overrides, and unsets its
  automatic workaround in Kitty child shells. Physical-GPU rendering is unchanged.
- Runtime Hyprland blur is already enabled (size 6). No speculative compositor
  override has been added. Terminal/blur screenshots remain to be inspected after
  the strict combined checks pass.

New boot acceptance requires Foot validation, actual cyan symlinks and GTK theme,
blur options, mapped default Kitty/Foot windows, and a mapped actual-theme QML
greeter with no import errors. Qt software rendering is used only for that QML
test to isolate theme dependencies from the separate virgl limitation; this is
not yet physical-GPU or exact-image certification. Logs/screenshots are retained
under /var/log/hyprflux-desktop-checks in test guests.

No corrected ISO has been built yet. The palette ISO remains unchanged.

## HyprFlux palette correction — built and boot checked

New corrected ISO:
`/drive-data/HyprFlux-ISO/hyprflux-colors-build/out/build-20261103T165126Z-1/hyprflux-2026.11.03-x86_64.iso`

SHA256: `cec4348a01f54cdc236c00ce20b0c729cd936277e85b941e43e83dff50092936`.
Build, UEFI and BIOS firmware smoke passed. Actual embedded UI screenshot
`uefi-mfa90f19/tui-preview.png` visually inspected: cyan logo, yellow loading line
and dim log tail. Pink/magenta input/selection styling is covered by regressions
and real-Gum tests. No workflow remains running. This palette-only rebuild has
not rerun the installed-profile matrix and is not release certified. Previous
green-image installation passes remain historical, not exact-image passes here.

User rejected Omarchy's green branding. Restored the original HyprFlux palette:
cyan ASCII wordmark (`1;36`), yellow loading/status text, Gum 212 pink/magenta
input/cursor/selection/filter-match accents, white headers, and no green selected
background. Kept the new responsive layout, static header, buffered logs and
console-safe spinner behavior. Green success messages/checkmark remain unchanged.

**100 builder tests PASS, no skips**, including a new palette regression.
Task `sh_1a2527fd90015OpT8OV45H8iJ7` builds a new image under
`/drive-data/HyprFlux-ISO/hyprflux-colors-build/`, then checks both firmware
loaders and captures its actual embedded UI for visual review. Logs:
`/drive-data/HyprFlux-ISO/qemu-tests/hyprflux-colors-20261103/`.
The previously supplied green ISO is unchanged. This palette-only image does
not inherit prior install acceptance; no new profile-matrix pass is claimed.

## Omarchy-style HyprFlux presentation — implemented; partial acceptance

**No acceptance workflow remains running.** The final independent attempts also
failed on network access: BIOS manual in bounded keyring preflight, UEFI manual
during essential-package transfer/signature retrieval, and BIOS automatic on
preflight/package download. The aggregate acceptance report correctly exits
nonzero with three missing cases. Clean Full automatic UEFI and Desktop automatic
UEFI remain passed for this exact image; do not reuse predecessor/manual/recovery
passes to fill the gaps. Failure logs and `acceptance.log` are in the UI evidence
directory. No release, commit, push or signing was performed.

In the failed UEFI manual case, both live and chroot DNS lookups succeeded in
the immediate failure diagnostics; geo core.db HTTPS returned 200 in 1.31/1.09 s
respectively despite earlier pacman resolution failures. This remains an
intermittent/sustained-transfer issue, not a proven BIOS, manual-layout, permanent
chroot-DNS or IPv6 fault. Do not keep starting fresh installs automatically while
the external download environment is unreliable. The completed user-facing UI
changes and both clean UEFI profile outcomes are usable evidence, NOT completion
of all release/hardware gates.

New UI candidate:
`/drive-data/HyprFlux-ISO/omarchy-ui-build/out/build-20261103T130612Z-1/hyprflux-2026.11.03-x86_64.iso`,
SHA256 `62dc2ebd5cb56696ab4fdf012565db42be0f2849df1c5eac0ebcb35a4e27553e`.
It passed both firmware loaders and CLEAN embedded Full UEFI/NVMe installation,
complete package audit and desktop boot (`uefi-p2llm2fb`), plus CLEAN embedded
Desktop UEFI/NVMe with 4 GiB RAM, NTP disabled, swap and real password login
(`uefi-g7bamohp`). Both desktop screenshots were inspected, including checkmarks.

Embedded UI was also rendered directly from `/root/lib/tui.sh` in this ISO and
visually inspected at `uefi-o1awz24r/tui-preview.png`. This uses synthetic preview
logs (not installation evidence), but verifies the actual image's presentation,
not hot-loaded code. The preview flag is explicitly excluded from acceptance.

Two BIOS automatic attempts failed on package-transfer/signing-preflight network
timeouts; the second failed before any disk setup. These are not successful BIOS
installs. Task `sh_1a1eab37f001RzYVPeImEMPtYF` gives each still-missing case one
independent attempt, with manual layouts first, retaining verified Full/UEFI passes
and continuing after individual failures. Log: `omarchy-ui-20261103/workflow-independent.log`.
Do not rerun passed cases or rebuild this unchanged image for network failures.

Retired superseded pre-UI Desktop and recovered Full disks while retaining their
metadata/logs/screenshots; the new clean Full and Desktop UEFI disks remain.
The host launcher follows the relocated `out` directory when finding images,
while still refusing symlink ISO files and accidental existing-disk overwrites.

Recovered Full boot passed (`uefi-6qo6vw_e`); screenshot inspected with working
Waybar/wallpaper and green success checkmark. It remains a resumed/hot-loaded,
IPv4-only diagnostic result, not clean-install acceptance.

Adapted the classic Omarchy presentation (reference
`b45e8464ef4cc094d6edec46faa2a3632a462dd4`) for HyprFlux: static green wordmark,
no author separator, green/cyan prompts, adaptive menu/filter height and compact
header, buffered dim arrow-prefixed log tail, resize-aware dynamic region, and
dot spinners with an ASCII-line fallback on Linux VTs whose font lacks Braille.
Stage logs remain intact, displayed control codes are sanitized, command status
propagates, and the progress monitor is now waitable (not disowned). MIT
attribution ships in `/usr/share/licenses/hyprflux-iso/omarchy-ui-MIT.txt`.

**99 builder tests PASS, no skips**, including real Gum Enter/Escape/menu/filter,
compact terminal, resize, retained-log/control-code handling, monitor cleanup
and failure propagation. ShellCheck and whitespace checks pass. A real live VM
source preview was visually inspected at `uefi-zhpg6jje/tui-preview.png`; the
earlier preview caught the missing Braille glyph and prompted the VT fallback.
Preview data is clearly labelled synthetic and is NOT installation acceptance.

Readonly export of the verified recovered guest's package cache yielded 1009
complete archive/signature pairs, merged into the external build cache without
importing unsigned AUR archives or replacing differing same-name files. Fresh
repository-version curation and normal installer signature checks remain active.
This richer embedded online-download seed may reduce mirror traffic; no offline
or measured speedup claim is made. Retired only completed obsolete build scratch,
preserving both prior ISOs and all small evidence.

Task `sh_1a1844d50001mU94IQ7RSQ3m7O` builds a fresh UI image and runs Full FIRST,
then all four Desktop install/boot cases and both firmware loaders, using default
QEMU network mode (IPv4-only was NOT a fix). Build/cache/temp/output/disks are on
`/drive-data`. Durable logs:
`/drive-data/HyprFlux-ISO/qemu-tests/omarchy-ui-20261103/`.
New-image acceptance is pending; release/hardware/signing gates remain open.

## Full-bundle timeout correction — acceptance running

Diagnostic recovery of `uefi-6qo6vw_e` completed with
`HYPRFLUX_TEST_INSTALL_PASS`, `HYPRFLUX_OPTIONAL_MISSING_NONE` and
`HYPRFLUX_FULL_PACKAGE_AUDIT_PASS`. Live and chroot startup DNS/HTTPS probes both
worked (geo core.db HTTP 200, about 1.19/0.94 s). Some later Rackspace DNS
requests still timed out, but cached-download progress/retries completed this
recovery. No permanent chroot DNS failure or IPv6-specific cause was established.

Task `sh_1a1711c6b001lNvqSAsfpPC9NZ` now checks recovered installed-system desktop
boot, log `stage-supervision-20261103/full-recovery-boot.log`. Machine metadata
remains `resumed=true`, `embedded=false`, `ipv4_network=true`; it MUST NOT count
toward the clean exact-image matrix. The successful Full recovery establishes
functional package recovery only; fresh Full acceptance is still pending.

IPv4-only sustained install failed with the SAME DNS timeouts, so it is not a
networking fix and no further fresh install is running. Task
`sh_1a13d61f8001VDb0c98GdEKOyp` instead resumes the already-configured failed
`uefi-6qo6vw_e` disk for bounded diagnostic recovery, preserving its partitions
and downloaded packages. This sets `resumed=true` and is excluded from clean
exact-image acceptance regardless of outcome. Live/chroot resolver lookups and
HTTPS probes now run before integration on resume and before unmount on failure,
so the failing context is captured rather than lost when QEMU stops. Log:
`stage-supervision-20261103/full-diagnostic-recovery.log`.

Short live-network diagnostics completed on both default dual-stack and IPv4-only
QEMU networks. All sequential mirror probes and five concurrent geo-mirror
requests returned HTTP 200 in both modes. Evidence is
`/drive-data/HyprFlux-ISO/network-comparison.log`. This does NOT establish IPv6
as the failure cause; sustained retrieval remains unverified. A controlled next
Full attempt uses `--ipv4-network` ONLY for QEMU and records it in metadata and
acceptance output. The production ISO, DNS and signature policy are unchanged.
Task: `sh_1a110afda001WvAx5e1VmMr7jm`; durable workflow log:
`stage-supervision-20261103/workflow-ipv4-control.log`. No current-image Full
acceptance is claimed until its package audit and desktop boot both pass.

The same-image mirror retry also failed during essential package retrieval with
DNS timeouts, before supervised Phase A. Repeated complete installation retries
are paused pending isolation. Readonly extraction from the failed guest shows
NetworkManager's QEMU-provided resolvers `10.0.2.3` and `fec0::3`; no arbitrary
public DNS override was installed. Host uses LAN router DNS. The target mirror
list contains Rackspace, geo.mirror.pkgbuild.com and MIT after retry rotation.

Task `sh_1a10d7f29001Yu1BYaWeFeB4KP` runs lightweight live VM network diagnostics
with default dual-stack and IPv4-only QEMU user networking, sequentially. It
collects DNS lookups, routes, normal/IPv4 HTTPS and parallel requests without
partitioning or claiming acceptance. See `network-default.log`,
`network-ipv4.log`, and `/drive-data/HyprFlux-ISO/network-diagnostic-workflow.log`.
These are test-harness changes only; the candidate ISO is unchanged.

Corrected candidate built successfully:
`/drive-data/HyprFlux-ISO/stage-supervision-build/out/build-20261103T091709Z-1/hyprflux-2026.11.03-x86_64.iso`,
SHA256 `b245d192de15867324a2be1dac538b6a41b8c27b2ca13fcf84c4da9d57a76775`.
UEFI and BIOS firmware smoke passed. First Full attempt failed during essential
repository-package download, BEFORE Phase A supervision: mirrors returned 404,
DNS timeouts and connection timeouts. No desktop acceptance is claimed from that
attempt. Host probes afterward retrieved core.db successfully from all three
configured fallback mirrors (HTTP 200; 1.97/2.74/7.38 seconds).

Task `sh_1a0e0a436001cnkbwz4B2QaEgz` re-verifies and retries the SAME ISO, retaining
firmware evidence and all failed attempt logs. Progress:
`stage-supervision-20261103/workflow-retry-mirrors.log`. No rebuild or signature
policy relaxation was performed for this network failure. Matrix remains pending.

The locale-default ISO (`1b5809f32877e7d7aaf374b18f6ac353c0c012a11951158c5d195f5eee90e898`)
passed all four embedded Desktop install/boot cases and both firmware loaders.
All four desktop screenshots were inspected; wallpaper, Waybar and green success
checkmark render correctly. Full failed its strict package audit: Codex and Free
Download Manager were absent. Do not claim that image passed the Full matrix.

Diagnosis: `01-hypr-pkgs.sh` exceeded the common 2400-second component timeout
during slow downloads. `su` shell termination did not stop all PTY/session
descendants; app installers continued during Phase B, making missing-app warnings
stale and preventing the final packages from completing before verification.

Added a Linux child-subreaper stage supervisor that cleans adopted and detached
descendants using pidfds on completion, timeout or interruption. Ordinary Phase A
budgets remain 2400 s; Full's bulk app stage gets 7200 s. Phase A timeouts or
interruptions now abort after tree cleanup instead of overlapping later stages.
The same supervisor wraps bounded critical AUR installs and Phase B modules.
The temporary runner is copied into chroot and removed by wrapper cleanup.

**92 builder tests PASS, no skips**, including real detached TERM-ignoring child,
orphan reaping and root `su` + `script` PTY timeout cleanup. ShellCheck, Python
syntax and whitespace checks pass. Superseded failed VM disks were retired with
metadata and diagnostic logs retained; successful Desktop evidence remains.

Task `sh_1a0b29f38001pSsajEVkY24Vdk` builds a new exact image from the changed
source, then tests Full FIRST and all four Desktop cases, plus both firmware
loaders. Build/cache/temporary/output/VM files remain on `/drive-data`.
Logs: `/drive-data/HyprFlux-ISO/qemu-tests/stage-supervision-20261103/`.
All new-image acceptance is pending. Omarchy UI implementation remains queued
after profile verification; read-only reference research is preserved at
`/drive-data/HyprFlux-ISO/omarchy-ui-reference-notes.md`.

## Root storage recovery — complete

Relocated both inactive interactive VM disks and project ISO output to
`/drive-data/HyprFlux-ISO/`, preserving contents and compatibility path links.
The interactive test launcher now defaults to `.qemu-tests/interactive/`, which
points to external storage in this workspace; all `.qcow2` files are Git-ignored.

The project's OpenCode snapshot store was checksum-synchronized to
`/drive-data/HyprFlux-ISO/opencode-snapshots/3365ccc0f42f97264580ade1793488b83d9275ba`
and linked at its original location. All snapshot history was preserved; no
session database or unrelated project store was removed. Temporarily paused
snapshot capture during relocation, then removed only the temporary local config
to restore the previous settings. Snapshot relocation recovered 33.07 GiB.
Final root free space: **44 GiB** (69% used); `/drive-data` free: **99 GiB**.
Verification log: `/drive-data/HyprFlux-ISO/snapshot-relocation-verified-sync.log`.

## Locale-default/profile verification — running

Latest continuation: `sh_19fdc30dc001EeMq7zbP2E7K6i` runs
`locale-profiles-20261103/resume.py`; logs are `workflow-resume-1.log`.
The new image built successfully and passed UEFI/BIOS firmware smoke:
`/drive-data/HyprFlux-ISO/locale-profile-build/out/build-20261103T050948Z-1/hyprflux-2026.11.03-x86_64.iso`,
SHA256 `1b5809f32877e7d7aaf374b18f6ac353c0c012a11951158c5d195f5eee90e898`.
Builder suite passed all 86 tests, including Gum. First Desktop installation
completed base/system configuration and generated en_US.UTF-8, then its new
test-only assertion rejected the trailing spaces in glibc's locale.gen entry.
Assertion corrected to accept whitespace but reject commented entries; host
suite now passes 87 tests (2 optional Gum skips). Production ISO is unchanged.

Root space was exhausted again; moved the idle generated libguestfs appliance
cache to `/drive-data/HyprFlux-ISO/guestfs-cache-preserved`. Test sockets now
honor TMPDIR, and host temporary/appliance-cache paths use external storage.
A failed ENOSPC source-test-file write was repaired from the preserved snapshot
and the complete host regression suite passed afterward. No user changes were
discarded. VM metric extraction now identifies the ext4 partition rather than
assuming partition 2 when swap is enabled. All previous attempt logs are retained.

Current continuation: `sh_19fd03c54001kNdCtqipuNrJ2p`, log
`locale-profiles-20261103/workflow-attempt-3.log`. The previous external build
reached the regression suite, but its `/tmp` was still on the full-root Docker
overlay; two seed tests hit the intentional 2 GiB free-space guard. Container
`/tmp` is now bound to `/drive-data/HyprFlux-ISO/build-tmp` as well. No ISO from
this change has passed acceptance yet. All failed-attempt logs remain preserved.

Storage correction: the first rebuild stopped before compilation because the root
filesystem had no user-available space. Copied and byte-compared this project's
Docker package cache to `/drive-data/HyprFlux-ISO/package-cache`, then removed only
the old `hyprflux-pacman-cache` volume, recovering about 1.5 GiB. Unrelated Docker
images/volumes and the interactive VM were not touched. Task
`sh_19fcf9aff001n0kMaTaEoECiiH` now builds a frozen copy of current working sources
using the existing tested builder image in
`/drive-data/HyprFlux-ISO/locale-profile-build/`. Build scratch, ISO output,
package cache and test VM disks are all on `/drive-data`; progress is in
`locale-profiles-20261103/workflow-attempt-2.log` under the external test directory.
The previous task/log below is historical.

At the user's request, removed the locale-selection TUI step. Fresh installations
default to `en_US.UTF-8`; review shows the locale and notes it can be changed after
installation. Timezone and keyboard selection remain. Profile descriptions now
explain Desktop and Full separately, including Full's extra downloads/apps.

Host checks: **86 tests, OK (2 optional Gum skips)**, ShellCheck and whitespace
checks passed. The installation fixture now executes the actual profile selection
function for both choices, checks the installer's default instead of overriding
it, and verifies target `locale.gen`/`locale.conf` before desktop integration.

New VM state storage: `/drive-data/HyprFlux-ISO/qemu-tests/`, linked from the
project's `.qemu-tests` so the existing test tools keep their containment checks.
Historical evidence was copied there and also retained in
`/drive-data/HyprFlux-ISO/historical-evidence-backup/`. The user's currently running
interactive VM and its `hyprflux-new-test.qcow2` were not touched.

Task `sh_19fccf929001bX9W3V6ZLBU0QL` builds a fresh explicit-zstd image and runs
the five-case matrix including both Desktop and Full, plus both firmware loaders.
VM disks and evidence remain on `/drive-data`; build scratch and ISO output keep
their existing project locations. Logs:
`/drive-data/HyprFlux-ISO/qemu-tests/locale-profiles-20261103/`.
No new-image acceptance is claimed yet; the PASS below is for the previous image.

## Latest exact-image automated acceptance — PASS

Post-acceptance cleanup at the user's request removed all remaining generated
VM disks (including the Full disk) and extracted boot payloads from `.qemu-tests`.
Reclaimed approximately 23 GiB; 149 MiB of logs, screenshots and metadata remain.
The ISO is untouched. Retained Full metrics were extracted before disk removal;
historical disk-retention statements below describe the pre-cleanup checkpoint.

Image: `out/build-20261103T010141Z-1/hyprflux-2026.11.03-x86_64.iso`

SHA256: `a573bbdc1e413827cc64f3f9557587647cce324547a62551947d4c439991019e`

The corrected explicit-zstd image passed both real firmware-loader smoke tests,
offline UEFI/BIOS live boot at 4 GiB (keyring without NTP plus real undersized
ext4 rejection), and the complete embedded, unmodified five-case matrix:

| Profile/layout | Firmware / disk | Install + desktop boot | Evidence state |
|---|---|---|---|
| Desktop automatic, 4 GiB, NTP disabled, real password login | UEFI / NVMe, 4 GiB swap | PASS | `uefi-zjs81yt8` |
| Desktop automatic | BIOS / SATA, 4 GiB swap | PASS | `bios-939syshr` |
| Desktop manual GPT | UEFI / SCSI | PASS | `uefi-lk_zsva9` |
| Desktop manual GPT | BIOS / virtio | PASS | `bios-agz21orx` |
| Full automatic + extended package audit | UEFI / NVMe | PASS | `uefi-44yegkht` |

All states are under `.qemu-tests/`. All five desktop screenshots have been
visually inspected: wallpaper and Waybar render; green Papirus success checkmarks
are visible in the Desktop captures. The Full capture shows the running desktop
after its notification expired. Real password entry was injected only after the
greeter-ready marker, without test autologin, and reached the desktop. However,
QMP greeter capture failed with `no surface`; **no greeter screenshot was inspected**.

Full audit reports `HYPRFLUX_OPTIONAL_MISSING_NONE` and
`HYPRFLUX_FULL_PACKAGE_AUDIT_PASS`. All five runtime protocol probes reject the
official Waybar 0.15 legacy workspace packet while accepting Lua dispatch and
restoration; retain `waybar-git`. All installs seeded 377 package/signature pairs.
Readonly extraction from the retained Full disk confirms 976,485,351 bytes
seeded in 3.925 s; base stage 177 s / 124,846,831 interface receive bytes and
desktop integration 3,023 s / 3,382,253,841 receive bytes. These are one-run
measurements, not A/B network-savings or cold-boot-speed claims.

Builder regression suite: **84 tests, all PASS, no skips**. Host suite: 84 tests,
2 Gum-dependent skips. ShellCheck and `git diff --check` passed. Installation
logs include a nonfatal systemd post-install preset warning about the test-masked
live `getty@tty1` generator unit; this is not an error-free-log claim. Installed
desktop and required package postconditions nevertheless passed.

Completed Desktop disks and older generated ISOs were automatically retired;
logs/screenshots/metadata and the final Full disk remain. About 16 GiB was free
after completion. Durable workflow, matrix report, benchmark and extracted Full
metrics are in `.qemu-tests/audit-acceptance-20261103/`. Earlier sections below
are historical checkpoints, not current blockers.

**Remaining release gates:** human end-to-end TUI operation, physical
Intel/AMD/supported NVIDIA testing, Wi-Fi/audio playback, suspend/resume and
external displays. Publisher signing still needs a real private key and trusted
public fingerprint. Compression defaults remain xz; this accepted candidate uses
the explicitly selected zstd recipe. No commit, push or release was performed;
releases must remain drafts until the remaining gates pass.

### Mirror-preflight ordering correction

Both offline firmware-mode cases (direct-kernel UEFI/BIOS guests, 4 GiB RAM)
passed offline-shell/keyring and real undersized-ext4 rejection checks on the
superseded candidate. The subsequent embedded Desktop install stopped BEFORE
disk setup: live pacman had no configured mirror servers. Keyring preflight had
been moved before the existing mirror initialization, exposing this dependency.
Production preflight now runs the bounded mirror refresher (with HTTPS fallback)
before keyring refresh. Tests enforce that ordering and cover a commented-only
mirrorlist when reflector times out. The automated fixture now treats cancellation
as failure instead of exiting successfully and leaving the host waiting.

Host regressions: **84 tests, OK (2 optional Gum tests skipped)**; ShellCheck
passed. Production source changed, so previous image passes are historical only.
Task `sh_19eed0914001bUnNy28pNgKKFf` builds a corrected explicit-zstd image and
restarts all exact-image gates, reusing only the artifact-compression measurements.
See `workflow-mirror-fix.log`; superseded candidate metadata and every attempt's
logs are preserved. No new-image firmware/install/desktop pass is claimed yet.

### Acceptance continuation — 2026-11-03

The first continuation exposed a second fixture issue: a blanket `read` override
broke banner line parsing before the real low-space guard. The override now
simulates only the bare `read -r` keypress and delegates other reads to Bash.
The regression now executes the real manual prompt/banner/capacity code with
only tty/mount/capacity resources simulated, rather than a stubbed rejection.
All 83 tests pass (2 skipped). Task `sh_19e455bca001Zu6zhJS2YpXB9d` continues
the unchanged candidate; durable output is `workflow-resume-2.log`. Earlier
failed-attempt logs remain intact. No new matrix results are claimed yet.

The xz baseline and explicit zstd candidate built successfully. The candidate is
`out/build-20261102T215230Z-1/hyprflux-2026.11.02-x86_64.iso`, SHA256
`4c6c27e3374d583325a4c800dad1e1b6b0cc5323a2bd5f846a8ea9559ebaaa7c`.
Its real UEFI and BIOS firmware-loader smoke tests passed. Offline UEFI at
4 GiB reached the network-recovery shell and completed keyring initialization
without waiting for NTP, but the low-space fixture then failed: the installer's
ERR trap intercepted the fixture's expected nonzero exit despite `set +e`.
The fixture now captures that rejection in a conditional and prints its diagnostic
log. Production installer source and the candidate image are unchanged.

Regression suite after this test-only correction: **83 tests, OK (2 skipped)**.
Task `sh_19e4414af001oYF2zXdDmqvyo6` resumes the same checksum-verified image,
preserving prior logs and firmware results; see `workflow-resume-1.log` in the
audit-acceptance directory. The remaining offline/install/desktop matrix is pending.

Actual two-thread artifact benchmark: rootfs xz/zstd compression 511.336/55.177 s,
extraction 18.133/15.968 s, size 1,998,979,072/2,072,940,544 bytes. Main-initramfs
xz-9e/zstd-3 compression 17.721/0.138 s, decompression 0.379/0.053 s, size
13,312,316/17,695,482 bytes. These are artifact measurements, not cold USB boot
or installation-speed claims; default compression remains xz.

## Audit remediation and unattended acceptance — 2026-11-03

User authorized automatic cleanup of obsolete generated artifacts without
further questions. Source, unrelated files and physical disks remain out of
scope. Retired the completed pre-audit Full test disk (`uefi-bh42p__v`) and
completed pre-audit source-test disk (`bios-bijaj80s`), saving metadata/removal
notes and preserving all logs/screenshots. Also reclaimed orphaned extracted
boot payloads only in unlocked states without retained disks. Free space reached
42 GiB. The prior BIOS/SATA source install and desktop boot passed; screenshot
inspected, including green success checkmark. That result predates these fixes.

### Implemented (new source; pending new-image acceptance)

- Storage inspection captures/checks command status, rejects unmounted mapped/
  RAID holders, and fails closed on missing topology/live ancestry information.
  Manual root/ESP must be plain partitions; crypt/LVM/RAID ancestors are rejected.
- Signing-key service has a 120-second bound, no time-sync ordering dependency,
  and no enabled indefinite time-wait-sync service. The TUI explicitly confirms
  an unsynchronized displayed clock and performs bounded keyring/network checks
  **before** automatic disk setup. TLS and package signature policy are intact.
- Full recovery clears old missing-applications reports when all tracked apps
  are present. Branding writes a real `/etc/os-release` override atomically,
  retains vendor metadata, and includes `ID_LIKE=arch`.
- CI uses the same `build.sh` and optional-cache path as local builds, with an
  explicit matching compression choice and Bash shell. Releases remain drafts.
- Optional ISO detached signing supports a configured publisher key, private
  passphrase descriptor, signature verification and fail-early required-signing
  mode. CI keys are imported into an ephemeral external keyring then removed.
  No real publisher key has been supplied; development candidates remain unsigned.
  Real ephemeral-key tests verify signatures and reject tampered payloads.
- Cache curation syncs fresh repository metadata into an isolated database
  without changing host package databases; excludes stale/foreign versions,
  deduplicates packages and prioritizes base/Desktop payloads. Seed counts,
  bytes and timing plus stage elapsed/interface receive counters are recorded.
  These counters are not asserted to equal package-network savings.
- Full requires more workspace headroom (32 GiB available root, 33 GiB automatic
  disk before swap). Release tests additionally audit the advertised Full apps
  and all packages previously affected by batch fallback.
- Added 4 GiB RAM and NTP-disabled test options, offline boot/keyring smoke,
  real undersized ext4 rejection, and real SDDM password-login mode without
  autologin. Workspace-dispatch protocol probing evaluates official Waybar's
  legacy packet versus Lua. Keep `waybar-git` until compatibility is demonstrated:
  inspected upstream 0.15.0 code uses legacy dispatch, while current development
  code has explicit Lua translation required by the pinned HyprFlux setup.
- Added actual rootfs/main-initramfs xz/zstd measurement tooling and an explicit
  zstd build recipe. Defaults remain xz pending measured candidate validation;
  a small fixture confirmed benchmark operation, not performance superiority.

### Checks and running workflow

Host suite: **82 tests discovered, OK (2 optional Gum tests skipped)**. Prior
isolated real-Gum tests passed; the updated builder now includes Gum so all
checks run there. ShellCheck (existing SC2034 exclusion), Bash/Python syntax,
whitespace checks and real ephemeral GPG tamper rejection passed.

Workflow `sh_19e2e12ce001pF1SHtJMPKxcVJ` runs
`.qemu-tests/audit-acceptance-20261103/run.py`. Durable progress/logs/results are
in `.qemu-tests/audit-acceptance-20261103/`. It builds an xz baseline, measures the
actual rootfs/initramfs, optionally builds/tests zstd only within recorded speed/
size thresholds, then tests both firmware loaders, offline UEFI/BIOS at 4 GiB,
NTP-disabled 4 GiB password-login installation, the four Desktop layouts and a
Full installation/package audit. It preserves evidence and retires completed
test disks to avoid filling the host; only the final Full disk is retained.

No competing build/install should run. On completion inspect greeter/desktop
screenshots and protocol/cache/timing records. Automated success is not physical
Intel/AMD/NVIDIA, Wi-Fi/audio playback, suspend/resume or external-display signoff.
Real release authenticity still requires the publisher's private signing key and
independently published public fingerprint; never substitute the disposable test
key or claim that a SHA256 sidecar alone authenticates an ISO.

## Read-only upstream-guidance audit — 2026-11-03

Audited build/profile/CI, firmware configuration, live services, automatic and
manual storage validation, pacman/cache behavior, wrapper cleanup/postconditions,
desktop defaults and release acceptance. No production code was changed during
this audit or in the already-frozen running installation test.

### Highest-priority findings (not fixed yet)

1. **Automatic storage checks fail open on an inspection error.**
   `disk_is_installable()` reads `lsblk` mount output through process
   substitution; an error is indistinguishable from an empty mount list.
   Reproduced by extracting the actual function, mocking only block-device
   existence and `lsblk`/`findmnt`: failed mount inspection still returns success.
   No real disk was used. Capture and check inspection status; also reject
   unsupported active device-mapper/RAID holders before wiping.
2. **Manual validation accepts unsupported encrypted root.** A mocked ext4 root
   at `/dev/mapper/cryptroot` with one physical ancestor passes the actual manual
   validation function and real `parent_disk()` implementation. Current final
   initramfs hooks do not configure encrypted-root unlocking. Reject unsupported
   block stacks explicitly rather than relying only on filesystem type and a
   single physical ancestor. Reproduction touched only a temporary directory.
3. **Keyring startup has an unbounded NTP dependency.** The live
   `pacman-init.service` is ordered after `time-sync.target`, while enabled
   `systemd-time-wait-sync.service` has `TimeoutStartSec=infinity`. Base setup
   synchronously starts keyring initialization after disk setup. HTTPS may work
   on networks that block NTP, leaving this step waiting indefinitely. Unit
   ordering/timeout confirmed; the blocked-NTP failure mode still needs a VM
   reproduction. Add a bounded, explicit time/keyring preflight before wiping,
   retaining clock/certificate/signature checks.

### Other concrete gaps and focused improvements

- Full-profile recovery can leave stale `missing-applications.txt`: the wrapper
  writes it when packages are missing, but does not remove it when a subsequent
  Full run finds none missing. This can produce false warning notifications.
- Branding omits `ID_LIKE=arch`. On targets where `/etc/os-release` is a symlink,
  the current output redirection follows it and overwrites the vendor file.
  Demonstrated with a relative-symlink fixture, not asserted for every target.
  Use a deliberate `/etc` override and retain derivative compatibility metadata.
- CI directly invokes `mkarchiso`, bypassing the local cache-enabled build path.
  Local tested artifacts and CI release artifacts therefore need separate exact
  digest acceptance; the speed feature is not automatically in CI-built images.
- Core desktop setup requires floating `waybar-git`/`wlogout` AUR packages and
  allows three 30-minute attempts. Evaluate official stable Waybar against the
  pinned configs before making source compilation a hard requirement. Do not
  replace it blindly or weaken signatures; AUR availability and compilation
  failures are different from official mirror failures.
- Embedded cache selection is alphabetical and accepts multiple old versions.
  Prefer current base/Desktop dependencies and record cache hit/download bytes;
  the number of seeded archives alone does not demonstrate acceleration.
- xz SquashFS and extreme xz live-initramfs compression merit a measured zstd
  A/B test after the active VM finishes. Do not change defaults without measuring
  build time, USB/VM boot time and resulting image size.
- Release authenticity is currently a SHA256 file, not a signed release artifact.
  Add a detached signature when a release signing key is available. Archiso's
  rootfs signing flags do not themselves sign the downloadable ISO file.
- Existing VM autologin is not a password-based SDDM login test. Additional
  release cases should cover blocked NTP, offline live boot/network setup,
  exhausted target space, 4 GiB memory, supported GPU hardware, suspend/resume
  and real display hotplug. Full-profile minimum disk space needs measurement
  including package caches and AUR build working space.

### Existing decisions supported by current upstream guidance

Keep archiso rather than rewriting the image builder; retain UEFI/BIOS firmware
tests, mount-safe work cleanup, real systemctl, final initramfs validation,
standard signed package caching, moderate download parallelism, pinned HyprFlux
source, fresh-NVRAM boot checks, and draft releases. Hyprland still documents
preferred/native monitor fallback and warns against hard-coded DRM card numbers.
The current preferred-mode rule is appropriate; automatic HiDPI scaling is an
optional UX evaluation, not a reason to force live-session resolutions.

Sources checked:
- https://wiki.archlinux.org/title/Archiso
- https://man.archlinux.org/man/mkarchiso.1.en.txt (archiso 92)
- https://wiki.archlinux.org/title/System_maintenance
- https://www.freedesktop.org/software/systemd/man/latest/systemd-time-wait-sync.service.html
- https://www.freedesktop.org/software/systemd/man/latest/os-release.html
- https://wiki.hypr.land/configuring/core/monitors/ (latest-git documentation;
  version-specific syntax must still be verified against the installed release)
- https://github.com/hyprwm/hyprland-wiki/blob/main/content/configuring/extra/multi-gpu.md
- https://wiki.archlinux.org/title/NVIDIA
- https://github.com/pierres/archiso-manager
- Pacman upstream configuration/cache documentation queried through Context7.

Recommended implementation order: storage fail-closed checks, unsupported
manual-stack rejection, bounded time/keyring setup, stale warning cleanup and
branding metadata, then measured cache/AUR/compression optimization. These are
audit findings, not new production-certification results.

## Focused reliability changes — 2026-11-03 (source only)

At the user's request, removed only four superseded cache-candidate
`disk.qcow2` files (`uefi-bwrykszy`, `bios-xvb713zv`, `uefi-gihp5g7i`,
`bios-px8x27vl`) and the two older ISO/checksum pairs under
`out/build-20261101T211053Z-1/` and `out/full-audit-fix-20261101T093630Z/`.
Locks were acquired and disk metadata/removal notes saved. Source, diagnostics,
screenshots, newest ISO and newest Full VM were preserved. Free space recovered
from 673 MiB to about 27 GiB. Older matrix results remain historical evidence,
not bootable retained VMs.

Small production fixes:
- Escape from text input no longer submits a default. Required timezone,
  locale, keyboard, hostname, username and password prompts cancel cleanly.
- Automatic-disk reselection uses the outer menu loop rather than recursion;
  refusing/cancelling the wipe prompt or cancelling swap-size input cannot reach
  partitioning. Explicit blank submission still accepts a text default.
- Live pacman configuration enables five concurrent transfers before pacstrap;
  target configuration receives the same bounded setting. Repository definitions,
  signature policy and download timeouts are untouched.
- Connectivity probing has an eight-second per-endpoint bound and tries the
  official package mirror if the Arch homepage fails, without disabling TLS.

**64 root-free checks passed** before adding two optional real-Gum PTY tests.
The real host pacman-config parser accepted the modified configuration with
`ParallelDownloads=5`; signature policy and repository lists matched the
original. Live HTTPS connectivity probe passed. ShellCheck (existing SC2034
cross-function-variable exclusion), shell syntax and whitespace checks passed.

Real-Gum isolated-container checks run as `sh_19dbad4f7001YDA5bU6WaJoUHo`;
durable log `.qemu-tests/real-tui-check-20261103.log`. Initial disposable-PTY
experiment lacked terminal dimensions; updated the test fixture to provide a
40x120 terminal and reply to cursor-position queries. Do not call that initial
fixture timeout a production prompt failure.

The corrected real-Gum PTY run **completed successfully**: both explicit Enter
and Escape tests pass (2 tests, 0.201 seconds). Final host discovery reports
66 tests, OK with only those 2 Gum-dependent checks skipped on the host; all
64 other checks pass. Thus both optional checks were also executed successfully
in the isolated container. `git diff --check` remains clean.

Current-source **hot-loaded**, not embedded-image, Desktop BIOS/SATA + swap
install/desktop-boot workflow runs as `sh_19dbb6add001Lm4mJ1LC5s4pOO`. Durable
logs `.qemu-tests/reliability-20261103/{desktop-install.log,desktop-boot.log}`.
No competing installation/build should run. The retained 2026-11-02 ISO is
unchanged and does not yet include these source fixes.

## Icon-enabled ISO: Full install and desktop boot passed

Follow-up workflow `sh_19d154dd5001x8ZdJwVJ9uUUN7` completed successfully on
`out/build-20261102T153842Z-1/hyprflux-2026.11.02-x86_64.iso`, SHA256
`e969e0ae6c70c02157561c0ab9be43e1ba555037a08dac0f01ea8977d06a584c`.
State `.qemu-tests/uefi-bh42p__v/`: clean embedded Full UEFI/NVMe install and first
desktop boot both **PASS**. Screenshot inspected: green Papirus checkmark is
visible beside "First-boot setup complete!", Waybar is rendered, and no config
warning is apparent. No hot-loaded repair or external package cache was used.

Archived installation log confirms 404 embedded package pairs seeded,
`HYPRFLUX_INSTALLED_PROFILE=full`, `HYPRFLUX_OPTIONAL_MISSING_NONE`, and all 103433
Papirus files present. No error or failed-component entries found. Durable logs:
`.qemu-tests/cache-icon-workflow/{full-install.log,full-desktop-boot.log,acceptance-report.json}`.

Both firmware boot tests passed on this same ISO. The exact-image report still
lists four Desktop cases missing: those passed on the preceding cache image,
not this rebuilt digest. Do not claim a complete latest-image VM matrix or
physical-hardware certification. The green-icon requirement is verified on the
actual installed desktop, not just the standalone SVG preview.

### Prior workflow and space recovery history

User approved removing only completed `work/` build scratch. Acquired the build
lock, rechecked mount absence and untracked-only scope, then removed that exact
tree. `df -h` reported 28 GiB available. ISOs, VM disks and evidence
were preserved. Follow-up task `sh_19d154dd5001x8ZdJwVJ9uUUN7` now verifies the
new ISO checksum and runs the pending clean embedded Full UEFI/NVMe install and
desktop boot, without an external cache share. Durable output stays in
`.qemu-tests/cache-icon-workflow/{full-install.log,full-desktop-boot.log,acceptance-report.json}`.
Original stopped workflow is retained as historical evidence; do not rerun it
from the beginning or rebuild another ISO concurrently.

Workflow stopped safely **before Full installation** at its free-space guard:
20.61 GiB available versus 26 GiB required. This is not an installer failure.
All four compactions passed `qemu-img check` and content comparison, retaining
bootable disks. New icon-enabled ISO built and SHA256 verified:
`out/build-20261102T153842Z-1/hyprflux-2026.11.02-x86_64.iso` (2.7 GiB), digest
`e969e0ae6c70c02157561c0ab9be43e1ba555037a08dac0f01ea8977d06a584c`.
Both actual firmware boot tests passed. Full install/desktop boot and the
notification screenshot remain pending on this new image. Completed build
scratch `work/` uses approximately 6.7 GiB and has no active mounts; reclaiming
that scratch tree would allow the guarded Full test without deleting ISOs,
VM disks, logs or screenshots.

User approved verified lossless compaction of the four completed cache-candidate
VM disks. Workflow `sh_19ce59509001SbBXbkbBHI48vj` runs
`.qemu-tests/cache-icon-workflow/run.py`: lock/check/compare each disk before
atomic replacement, preserve all ISOs/evidence, rebuild with embedded package
cache and the green notification icon, verify both firmware boots, then run a
clean embedded Full UEFI/NVMe installation and desktop boot. It stops if free
space is insufficient; no disk deletion is authorized by this workflow.

Durable logs: `.qemu-tests/cache-icon-workflow/` (including `workflow.log`,
`compaction.log`, `iso-build.log`, firmware/install/boot logs, and eventual
`image.json`/`result.json`). Do not start competing builds/installations.
On completion inspect the new desktop screenshot for the green success icon
and audit Full-profile package results; this is not yet a completed test.

## First-boot notification icon — source update

The successful first-boot notification now passes an explicit icon to
`notify-send`: a user-local copy of Papirus' `dialog-ok-apply.svg` using its green
positive-color class. The packaged icon theme is not modified; warning/retry
notifications do not receive the success checkmark. A standard theme-icon
fallback preserves notification delivery if the SVG cannot be prepared.

All **56 regression tests pass**, including success icon arguments, preserved
Papirus source and unchanged retry behavior. Rendered the actual installed
Papirus SVG with librsvg and visually confirmed the green checkmark. Shell
syntax and whitespace checks pass. This change is **not embedded in the current
cache candidate** and requires a later ISO rebuild; do not attribute current
embedded-image VM tests to this cosmetic source update.

## Cache candidate acceptance update — 2026-11-02

Expanded workflow `sh_19bcfaf62001TWCRnjLr4zfr8f` **completed successfully**:

| Desktop case | State | Install + desktop boot |
| --- | --- | --- |
| BIOS/SATA automatic + swap | `.qemu-tests/bios-xvb713zv/` | PASS |
| UEFI/SCSI manual GPT | `.qemu-tests/uefi-gihp5g7i/` | PASS |
| BIOS/VirtIO manual GPT | `.qemu-tests/bios-px8x27vl/` | PASS |

Together with `.qemu-tests/uefi-bwrykszy/`, all four Desktop paths pass on this
exact digest. All screenshots inspected: rendered Waybar, first-login completion
and no apparent config warning. Each archived install log confirms 383 embedded
package pairs seeded; no error/failed-component entries were found. Report
`.qemu-tests/cache-candidate-acceptance-report.json` has only Full UEFI automatic
missing. Host free space is **7.9 GiB**: do not start another full installation
or ISO rebuild without reclaiming space. The green success-icon change remains
source-only and is not visible in these older candidate screenshots.

Candidate `out/build-20261101T211053Z-1/hyprflux-2026.11.01-x86_64.iso`, digest
`faeda8bffa4a1f19992b75202ea9174d5157bab309fd3577dad29c02f3759c22`:

- Actual UEFI/GRUB firmware boot **PASS**, `.qemu-tests/uefi-1ka76mv4/serial.log`.
- Actual BIOS/Syslinux firmware boot **PASS**, `.qemu-tests/bios-musgqwud/serial.log`.
- Clean embedded Desktop UEFI/NVMe automatic installation and first desktop boot
  **PASS**, `.qemu-tests/uefi-bwrykszy/`. Screenshot inspected: rendered Waybar,
  first-login completion and no apparent configuration warning.
- Archived installation serial log confirms **383 package pairs seeded from the
  ISO**, `HYPRFLUX_OPTIONAL_MISSING_NONE`, `HYPRFLUX_TEST_INSTALL_PASS`; no error
  or failed-component entries were found. No external package-cache share was
  supplied. The desktop boot serial log contains `HYPRFLUX_TEST_BOOT_PASS`.

The prior workflow completed successfully (persistent harness output:
`/home/ahmad/.local/share/opencode/shell/3365ccc0f42f97264580ade1793488b83d9275ba/sh_198fecb4f001SovhuUlHAvas2n.out`).
Temporary `/tmp/opencode` logs disappeared between sessions; underlying state
logs/screenshots remain. Store the regenerated exact-image report at
`.qemu-tests/cache-candidate-acceptance-report.json` rather than relying on /tmp.

Expanded Desktop acceptance workflow `sh_19bcfaf62001TWCRnjLr4zfr8f` now runs
sequential clean embedded BIOS/SATA automatic + swap, UEFI/SCSI manual GPT, and
BIOS/VirtIO manual GPT installations and desktop boots, without external package
seeding. Each new install requires 12 GiB host free space; no new compaction or
disk deletion is performed. Logs: `/tmp/opencode/cache-{bios-auto,uefi-manual,bios-manual}-{install,boot}.log`.
Full-profile acceptance on this digest remains untested. Do not treat the
previous ISO's complete matrix as acceptance of this new image.

Fixed a test-launcher regression caused by nested build outputs: automatic ISO
discovery now searches `out/` and its build directories, ignores symlinks and
requires a completion checksum sidecar. This does not replace checksum
verification. Root-free regression suite: **56 PASS**; shell syntax and
`git diff --check` PASS. These launcher-only changes do not require rebuilding
the ISO. No controlled speedup or physical-hardware compatibility claim is made.

## New acceleration changes — 2026-11-02 (not in the accepted ISO)

Added optional ISO package-cache staging/target seeding with archive/signature
pairs, SHA256 integrity validation, a configurable 2 GiB staging limit, target
free-space reserve, no-overwrite behavior and online fallback. Package selection
and signature enforcement remain pacman's responsibility; upstream HyprFlux
transactions use the seeded standard target cache. This is not offline mode.

Builds now preserve accepted ISOs and use unique output directories. Container
builds expose `--with-package-cache`. Added read-only PCI/DRM hardware inventory;
native display selection remains deferred to the installed desktop, without
persisting live card numbers or guessed resolutions.

Root-free tests: **55 passed**; shell syntax and `git diff --check` passed.
Real host-cache staging/seeding also passed: 65 signed package pairs (53,595,244
bytes), with identical hashes in the target cache. Container pacman read the
seeded Archiso package metadata and `pacman-key --verify` reported a good trusted
signature from David Runge. This verifies transfer/signature preservation, not
an installation-speed benchmark. A mocked builder contract test passed: staged
cache reached mkarchiso, source profile stayed untouched, and the accepted ISO
survived both successful and deliberately failed rebuilds. ShellCheck passed
with existing unused-cross-function-variable warning SC2034 excluded.

Cache-enabled candidate build **completed** as task
`sh_198f363e4001iLuT2S06PPTb10`;
log `/tmp/opencode/cache-candidate-build-20261102.log`. Image:
`out/build-20261101T211053Z-1/hyprflux-2026.11.01-x86_64.iso` (2.2 GiB), SHA256
`faeda8bffa4a1f19992b75202ea9174d5157bab309fd3577dad29c02f3759c22`.
The builder used the host's UTC clock for filenames; these are the new
2026-11-02 source changes despite the filename date. The previous accepted ISO
remains untouched. Build-root integrity check passed for all **383 signed
package pairs / 986,274,771 bytes**; both helper files match current source.

Acceptance workflow `sh_198fecb4f001SovhuUlHAvas2n` runs checksum verification,
actual UEFI/BIOS firmware smoke, then a clean embedded Desktop UEFI/NVMe install
and first desktop boot. **No external package-cache share is supplied.** Logs:
`/tmp/opencode/cache-candidate-{uefi-smoke,bios-smoke,install,first-boot}.log`.
Do not run another installation concurrently or relabel older VM evidence.
Inspect cache-seed logs, screenshot and timings before making performance claims.

Upstream HEAD inspected at `0f62647d95178eefa7cf8cd1b66760e93a260ef7` (two commits
ahead of the tested pin); changed modules are Plymouth and hardware-temperature
configuration. The ISO continues to pin the accepted revision rather than
silently adopting untested upstream changes. Existing initramfs normalization
and Waybar parsing protections remain in place.
The 2026-11-01 ISO/matrix below does **not** validate these new source changes.

## Verified

- `python3 -m unittest discover -s tests -v`: **45 tests passed**.
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

## Latest candidate: exact-image VM install/boot matrix complete

`/tmp/opencode/latest-acceptance-report.json` reports
`vm_install_boot_matrix_complete: true`, `missing_vm_cases: []` for digest
`51cdbcc23d547295471b3ae7278fe0e1a705b9bfd0dd66dca3618e7375ba1f71`.
Every row used the embedded installer, not a hot-loaded repair:

| Profile / firmware | Storage / layout | Install + first desktop boot | Evidence state |
| --- | --- | --- | --- |
| Full / UEFI | NVMe automatic | PASS | `.qemu-tests/uefi-zvvcizrz/` |
| Desktop / BIOS | SATA automatic + 4 GiB swap | PASS | `.qemu-tests/bios-42o1wga8/` |
| Desktop / UEFI | VirtIO automatic | PASS | `.qemu-tests/uefi-74xui7ty/` |
| Desktop / UEFI | NVMe manual GPT, 512 MiB ESP | PASS | `.qemu-tests/uefi-9zhtya4j/` |
| Desktop / BIOS | SCSI manual GPT, 2 MiB BIOS boot | PASS | `.qemu-tests/bios-onew47d0/` |

All five screenshots were inspected: rendered Waybar and first-login
completion, without apparent config warnings. Both firmware-loader smoke tests
also passed. Required cleanup, actual Waybar layers and audio user services were
checked by the guest verifier. All retained disks were compacted only after
qemu-img checks and guest-content equality comparison; they remain bootable.

Workflow `sh_196cd9eeb0012RlIElO6zpRVoV` finished successfully, including
`acceptance-report.py --require-vm-matrix`. Log:
`/tmp/opencode/latest-matrix-workflow.log`. Free space after completion: 16 GiB.
These VM results do not constitute physical-hardware certification.

### Interactive TUI: nondestructive flow passed

Started an isolated live-ISO TUI inspection with an untouched embedded installer,
normal tty1 root autologin, no guest-driver prompt overrides, and a new disposable
40 GiB disk. Only `console=tty1`, disabled live Plymouth and masked serial getty
select the console; no production installer source was replaced. Task
`sh_196ffcf810014w6a3ZMGG1t3YA` completed; launcher log:
`/tmp/opencode/interactive-tui.log`.

Evidence state: `.qemu-tests/tui-dnufrweq/`. Exercised welcome cancellation and
restart, timezone/locale search, keyboard selection, invalid hostname/username
rejection, password mismatch/retry, Full profile selection and settings review.
The disk menu offered only the disposable `/dev/vda` (40 GiB). Entering `no` at
the literal `yes` wipe prompt returned to partition-mode selection; Escape
cancelled installation cleanly. QEMU was then stopped via QMP. With its runner
lock acquired, `qemu-img compare` against a separate new blank 40 GiB qcow2
reported **Images are identical**: no guest disk contents changed.

Screenshots `tui-01-welcome.png` through `tui-14-cancelled.png` (username error
captured as `tui-07-invalid-username.txt`), `tui-result.json`, and
`blank-disk-comparison.txt` retain the evidence. Some headless VGA captures
partially refreshed the banner; logical `/dev/vcsu1` capture confirmed it was
present. This was nondestructive TUI coverage, not an end-to-end interactive
installation; destructive installs are covered by the automated matrix above.

### Remaining release gate: physical hardware

Actual physical Intel/AMD/NVIDIA, Wi-Fi/audio playback, suspend/resume and
external-display acceptance will still require spare hardware.

### Latest-image build and test details

New image built and checksum verified:
`out/full-audit-fix-20261101T093630Z/hyprflux-2026.11.01-x86_64.iso`.
SHA256: `51cdbcc23d547295471b3ae7278fe0e1a705b9bfd0dd66dca3618e7375ba1f71`.
Build evidence: `/tmp/opencode/full-audit-fix-iso-build.log` ends in `Done!` and
`hyprflux-2026.11.01-x86_64.iso: OK`.

Before building, the latest current-source Full integration and desktop boot
both passed: `/tmp/opencode/full-profile-offline-audit-resume.log` contains
`HYPRFLUX_TEST_INSTALL_PASS`, and
`/tmp/opencode/full-profile-offline-audit-boot.log` contains
`HYPRFLUX_TEST_BOOT_PASS`. No failed-component summary or missing AUR apps were
reported; Papirus is installed. These were repaired/hot-loaded results, not a
clean acceptance result for this new image.

The user approved deleting only the four superseded Desktop `disk.qcow2` files
in `uefi-_nvgsobl`, `bios-j1uvj6i3`, `uefi-bur1qq9g`, `bios-azk4x5d5`. Acquired
their locks, saved current image metadata/removal notes, and removed those
exact files. All logs, screenshots, source snapshots and previous compaction
proof remain; those four old VMs are no longer bootable. No ISOs were removed.
Space returned to about 26 GiB.

The user-approved Full VM compaction completed: 23.15 -> 12.68 GiB allocated,
same guest contents verified (`/tmp/opencode/full-vm-compaction.log`). Free
space reached 36.03 GiB before the clean test.

Clean **embedded UEFI/NVMe Full-profile** installation of the new image
**passed**: `HYPRFLUX_TEST_INSTALL_PASS` in
`/tmp/opencode/final-full-embedded-install.log`. Its **first desktop boot also
passed**: `HYPRFLUX_TEST_BOOT_PASS` in `/tmp/opencode/final-full-first-boot.log`.
State `.qemu-tests/uefi-zvvcizrz/`. Screenshot inspected: rendered Waybar,
first-login completion, and no config warning.

The Full bulk transactions failed twice, then per-package fallback recovered.
A read-only post-install audit queried all 27 packages flagged by the batch
failure, all 12 tracked Full apps, and Papirus: every query succeeded. Evidence:
`.qemu-tests/uefi-zvvcizrz/full-package-audit.txt`. `swww` resolves to the
installed `awww` replacement. No missing AUR apps or failed-component summary
remain, and Papirus checks 103433 files with zero missing. These transient batch
errors are not being mistaken for unrecovered package failures.

Completed acceptance runs on this newest digest:
- Clean embedded Desktop BIOS/SATA + 4 GiB swap install **passed**:
  `sh_196b0df28001QsKB4lkfo2cyaG`, `/tmp/opencode/final-desktop-bios-install.log`.
- Actual UEFI/GRUB firmware smoke **passed**: `HYPRFLUX_TEST_SMOKE_PASS` in
  `/tmp/opencode/final-audited-uefi-smoke.log`, state
  `.qemu-tests/uefi-uq8rvbbv/`.
- Actual BIOS/Syslinux firmware smoke **passed**: `HYPRFLUX_TEST_SMOKE_PASS` in
  `/tmp/opencode/final-audited-bios-smoke.log`, state
  `.qemu-tests/bios-_4k2w7xk/`.

The latest Desktop BIOS/SATA + swap installation and **first desktop boot both
passed**: `HYPRFLUX_TEST_INSTALL_PASS` in
`/tmp/opencode/final-desktop-bios-install.log`, and `HYPRFLUX_TEST_BOOT_PASS` in
`/tmp/opencode/final-desktop-bios-first-boot.log`. State
`.qemu-tests/bios-42o1wga8/`; screenshot inspected with rendered Waybar and
first-login completion.

Added `tests/acceptance-report.py`. It computes the exact ISO digest, excludes
repaired/other-image states and requires install completion plus boot marker and
PNG evidence. Current report `/tmp/opencode/latest-acceptance-report.json`
confirms all five required latest-image cases pass, with no missing cases. It
does not certify screenshot contents, firmware smoke or physical hardware.
All 45 tests and Python compilation pass; no production ISO inputs changed.

The user approved deleting only the superseded
`.qemu-tests/uefi-50k95lyz/disk.qcow2` and verified lossless compaction of retained
and new completed acceptance disks as needed. Acquired that older disk's lock,
saved metadata/removal note, and removed that exact file. Its logs and audits
remain; the latest Full VM is retained. Free space returned to 17 GiB.

Workflow `sh_196cd9eeb0012RlIElO6zpRVoV` completed
`/tmp/opencode/finish-latest-matrix.py` sequentially: compact retained Full and
Desktop BIOS disks with compare proof, then clean embedded Desktop UEFI/VirtIO
automatic, UEFI/NVMe manual-GPT, and BIOS/SCSI manual-GPT installs. Each is booted
and compacted after passing; all latest VMs remain bootable. It requires 12 GiB
free before each install and monitors a 2 GiB floor during conversions. No
original is replaced before equality checks pass.

Workflow log: `/tmp/opencode/latest-matrix-workflow.log`.
Current operation: `/tmp/opencode/latest-matrix-progress.json`.
Per-case logs: `/tmp/opencode/latest-matrix-{uefi-auto,uefi-manual,bios-manual}-{install,boot}.log`.
Its final `acceptance-report.py --require-vm-matrix` passed. All three new
screenshots were inspected.

No installation or TUI VM remains running. Earlier four-path Desktop matrix
results below belong to the older digest and are not being relabeled as
latest-image acceptance. Physical-hardware acceptance remains outstanding.

## Earlier Waybar candidate: four Desktop VM install/boot paths passed

### Active next gate: exact-image Full profile

Latest focused offline-audit resume also **passed** installation and boot, with
no failed-component summary and no recorded missing AUR apps. See the latest
candidate section above for the rebuilt image and queued clean test.

**Papirus fix passed focused integration and desktop boot:**
`/tmp/opencode/full-profile-papirus-repair.log` reports
`HYPRFLUX_TEST_INSTALL_PASS`, installs `papirus-icon-theme`, and checks 103433
theme files with zero missing. The adapted module reports success, target
profile remains Full, and no missing AUR apps are recorded.
`/tmp/opencode/full-profile-papirus-boot.log` reports
`HYPRFLUX_TEST_BOOT_PASS`. These are hot-loaded repair results, not new-image
certification.

The warning audit drove further explicit offline corrections:
- Required audio packages are now queried in chroot and validated with `-Qk`;
  user activation stays in first-login setup, rather than running upstream's
  `systemctl --user` script in an offline chroot.
- ISO final validation checks actual installed package names and commands,
  replacing the legacy checker with obsolete package names. It now additionally
  checks the original essential tools and `awww-daemon`.
- Batch upstream scripts receive `TERM=xterm-256color`. Reproduced a silent
  set-e/tput exit with `TERM=dumb`, while the supported terminal setup succeeds.
- Optional Chaotic-AUR bootstrap is explicitly not run: ISO profiles use
  official repositories plus the existing direct AUR helper installation. The
  tested 12 Full apps installed through that route without Chaotic-AUR.

All 44 tests and ShellCheck pass. A fresh current-source Full integration resume
is running: `sh_19673634e001YkHMKEJgYO4RFu`,
`/tmp/opencode/full-profile-offline-audit-resume.log`. The existing candidate ISO
does not embed these fixes; it must be rebuilt and retested after validation.

#### Original Full run and audit

**Full-profile install and first desktop boot passed** on the exact candidate:
`HYPRFLUX_TEST_INSTALL_PASS` in
`/tmp/opencode/corrected-iso-full-profile-install.log`, and
`HYPRFLUX_TEST_BOOT_PASS` in `/tmp/opencode/corrected-iso-full-first-boot.log`.
State `.qemu-tests/uefi-50k95lyz/`; screenshot inspected. Target recorded
`HYPRFLUX_INSTALLED_PROFILE=full` and no recorded missing AUR apps. A separate
read-only package query confirmed all 12 tracked Full applications installed;
saved evidence: `full-app-audit.txt` in the run directory.

**Warning audit found a real defect:** module 04 requests `papirus-folders` from
official repositories, where it is unavailable; the whole transaction fails,
leaving `papirus-icon-theme` absent. The source fix now makes the icon theme
mandatory and adapts a temporary copy of module 04 to install only the official
icon package. The pinned upstream module is left untouched; temporary copy
cleanup is trapped, and final package validation checks the installed theme.
All 42 tests and ShellCheck pass. This fix is NOT in the existing ISO yet.

Other warnings remain: `initial.sh`, `pipewire.sh`, and upstream
`02-Final-Check.sh`. PipeWire and WirePlumber actually passed guest runtime
checks. The upstream final check references obsolete names (`rofi-wayland`,
`swww`, repository `waybar` rather than installed alternatives). Initial setup
and these script exits still need classification; do not silently suppress them.

A focused current-source Full resume is running to validate the icon fix:
`sh_1966d2b90001okJ4IilskwvcU8`, `/tmp/opencode/full-profile-papirus-repair.log`.
This uses hot-loaded updated integration, not embedded-image acceptance. The
runner now archives original image/machine metadata and explicitly marks resumed
states `embedded=false, resumed=true`, preventing an old exact-image label from
being retained after source changes. Original Full results are in archived
attempt logs; the current mutable disk must not be presented as unmodified ISO
evidence. After validation, rebuild and retest the new candidate.

All four approved compactions completed and compared identical; total free
space reached 30.91 GiB before Full installation. Per-disk `compaction.json`
and `/tmp/opencode/completed-vm-compaction.log` retain the verification results.

#### Full-test setup history

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
