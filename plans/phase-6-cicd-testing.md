# Phase 6: CI/CD, Testing & Release

## Goal

Set up automated ISO building via GitHub Actions, establish a testing workflow, and prepare the release pipeline. This phase ensures the project can be maintained and new ISOs can be built reliably.

---

## 6.1 GitHub Actions Workflow

The existing `.github/workflows/build-iso.yml` has a 3-job structure (build-aur, build-iso, release). We preserve the AUR pre-build infrastructure for future Approach B optimization but simplify the active workflow.

### Updated Workflow

```yaml
name: Build HyprFlux ISO

on:
  push:
    branches: [main]
    tags: ['v*']
  workflow_dispatch:

concurrency:
  group: iso-build-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-iso:
    name: Build ISO
    runs-on: ubuntu-latest
    container:
      image: archlinux:latest
      options: --privileged
    steps:
      - name: Install dependencies
        run: |
          pacman -Syu --noconfirm
          pacman -S --noconfirm --needed archiso git

      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Build ISO
        run: mkarchiso -v -w work -o out .

      - name: Get ISO info
        id: iso
        run: |
          ISO_FILE=$(ls out/*.iso | head -1)
          ISO_NAME=$(basename "$ISO_FILE")
          ISO_SIZE=$(du -h "$ISO_FILE" | cut -f1)
          echo "file=${ISO_FILE}" >> "$GITHUB_OUTPUT"
          echo "name=${ISO_NAME}" >> "$GITHUB_OUTPUT"
          echo "size=${ISO_SIZE}" >> "$GITHUB_OUTPUT"
          sha256sum "$ISO_FILE" > "${ISO_FILE}.sha256"

      - name: Upload ISO artifact
        uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.iso.outputs.name }}
          path: |
            ${{ steps.iso.outputs.file }}
            ${{ steps.iso.outputs.file }}.sha256
          retention-days: 14
          compression-level: 0

  # Future: Uncomment when switching to Approach B (pre-built AUR packages)
  # build-aur:
  #   name: Build AUR Packages
  #   runs-on: ubuntu-latest
  #   container:
  #     image: archlinux:latest
  #     options: --privileged
  #   steps:
  #     - uses: actions/checkout@v4
  #     - run: bash aur/build-aur.sh
  #     - uses: actions/upload-artifact@v4
  #       with:
  #         name: aur-packages
  #         path: aur/repo/

  release:
    name: Create Release
    runs-on: ubuntu-latest
    needs: [build-iso]
    if: startsWith(github.ref, 'refs/tags/v')
    permissions:
      contents: write
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Download ISO artifact
        uses: actions/download-artifact@v4
        with:
          path: artifacts/
          merge-multiple: true

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: ${{ github.ref_name }}
          name: "HyprFlux ${{ github.ref_name }}"
          body: |
            ## HyprFlux ${{ github.ref_name }}

            Pre-configured Hyprland desktop on Arch Linux.

            ### Download & Install
            ```bash
            # Write to USB
            sudo dd bs=4M if=hyprflux-*.iso of=/dev/sdX status=progress oflag=sync
            ```

            ### Features
            - TUI installer with Omarchy-style branding
            - Pre-configured Hyprland + Waybar + Rofi
            - NVIDIA GPU auto-detection
            - Both UEFI and Legacy BIOS boot
            - Auto or manual disk partitioning

            ### Verify
            ```bash
            sha256sum -c hyprflux-*.iso.sha256
            ```
          files: |
            artifacts/**/*.iso
            artifacts/**/*.sha256
          draft: false
          prerelease: false
```

**Changes from original plan:**
- Preserved AUR pre-build job as commented-out section (ready for Approach B)
- No changes to the `build-iso` or `release` jobs — they were already correct

---

## 6.2 Testing Workflow

### Local Testing with QEMU

The existing `test-qemu.sh` already handles UEFI and BIOS testing. It creates a 30GB virtual disk for installation testing.

**Testing checklist (manual, run for each build):**

#### Boot Tests
- [ ] UEFI boot: `./test-qemu.sh --uefi` -- systemd-boot menu appears, boots to installer
- [ ] BIOS boot: `./test-qemu.sh --bios` -- syslinux menu appears, boots to installer
- [ ] Auto-login works (no password prompt on tty1)
- [ ] Banner displays correctly (proper alignment, colors)
- [ ] pacman keyring is initialized (`pacman-key --list-keys`)

#### Network Tests
- [ ] Ethernet auto-connects in QEMU (user networking)
- [ ] WiFi menu shows (will show no networks in QEMU -- expected)
- [ ] Manual network option drops to shell and returns

#### Installer Flow Tests
- [ ] Welcome dialog shows and Cancel exits cleanly
- [ ] Timezone auto-detection works (or manual selection)
- [ ] Locale selection works
- [ ] Keyboard layout selection works
- [ ] Hostname validation rejects invalid names
- [ ] Username validation rejects invalid names
- [ ] Password mismatch is caught, empty password rejected
- [ ] Disk selection shows QEMU disk

#### Partitioning Tests
- [ ] **Auto UEFI**: Creates EFI + Root (no swap)
- [ ] **Auto UEFI + swap**: Creates EFI + Swap + Root
- [ ] **Auto BIOS**: Creates BIOS boot + Root
- [ ] **Manual mode**: Drops to shell, verifies mounts on return
- [ ] Disk format confirmation requires typing "yes"

#### Installation Tests
- [ ] reflector optimizes mirrors
- [ ] pacstrap completes without errors
- [ ] fstab is generated correctly
- [ ] chroot configuration runs (timezone, locale, GRUB)
- [ ] HyprFlux repos clone successfully in chroot
- [ ] systemctl shim works (no errors from --now calls)
- [ ] yay installs successfully as non-root user
- [ ] Arch-Hyprland scripts complete (with shim)
- [ ] HyprFlux dotsSetup modules complete
- [ ] Module 08 (GTK) is deferred to first-boot
- [ ] Module 17 (optional packages) is skipped
- [ ] SDDM, Bluetooth, NetworkManager services enabled
- [ ] First-boot fixup script is in place

#### Post-Install Tests
- [ ] Unmount succeeds
- [ ] Reboot prompt shows
- [ ] After reboot: SDDM login screen appears
- [ ] Login with created user
- [ ] First-boot fixup runs automatically (GTK theme + audio)
- [ ] Hyprland desktop loads (Waybar, wallpaper, etc.)
- [ ] Terminal (Kitty) works with zsh
- [ ] Rofi launches with Super key
- [ ] Audio works (PipeWire via first-boot service)

### Automated Smoke Test (future)

A basic automated test using QEMU + expect/pexpect:

```bash
# Future: automated-test.sh
# Uses QEMU serial console + expect to:
# 1. Boot ISO
# 2. Wait for installer prompt
# 3. Send automated responses
# 4. Verify installation completes
# 5. Reboot and verify SDDM starts
```

This is a nice-to-have for later. Manual testing is sufficient for initial development.

---

## 6.3 Release Process

### Version Scheme

```
v1.0.0-alpha   -- First working ISO (Phases 1-5 complete)
v1.0.0-beta    -- After testing and bug fixes
v1.0.0         -- First stable release
v1.1.0         -- Feature additions (e.g., AUR pre-building, offline mode)
```

### Release Steps

1. Test the ISO thoroughly (all checklist items above)
2. Update version references if any
3. Tag the release: `git tag v1.0.0-alpha`
4. Push the tag: `git push origin v1.0.0-alpha`
5. GitHub Actions automatically builds and creates the release
6. Verify the release ISO downloads and checksums match

---

## 6.4 `.gitignore` Updates

The existing `.gitignore` is mostly correct. Ensure it covers:

```gitignore
# Reference repos (local-only clones, not tracked)
references/

# Build artifacts
work/
out/
*.iso
*.sha256

# AUR build artifacts
aur/repo/
aur/build/
aur/logs/

# Downloaded assets
airootfs/usr/share/icons/Bibata-Modern-Classic/
airootfs/usr/share/icons/hicolor/

# Agent/editor config
.agents/
.opencode/
skills-lock.json

# Plan files (tracked separately if desired)
# plans/  -- uncomment if you don't want plans in git
```

---

## 6.5 Directory Structure (Final)

```
hyprflux-iso/
├── .github/
│   └── workflows/
│       └── build-iso.yml              # CI/CD
├── airootfs/
│   ├── etc/
│   │   ├── hostname
│   │   ├── locale.conf
│   │   ├── locale.gen
│   │   ├── passwd                     # root shell = zsh
│   │   ├── motd
│   │   ├── shadow
│   │   ├── mkinitcpio.conf.d/
│   │   │   └── archiso.conf
│   │   ├── mkinitcpio.d/
│   │   │   └── linux.preset           # archiso-only preset
│   │   └── systemd/
│   │       ├── journal.conf.d/
│   │       │   └── volatile-storage.conf
│   │       ├── logind.conf.d/
│   │       │   └── do-not-suspend.conf
│   │       └── system/
│   │           ├── pacman-init.service
│   │           ├── multi-user.target.wants/  # symlinks
│   │           └── getty@tty1.service.d/
│   │               └── autologin.conf
│   └── root/
│       ├── .zlogin
│       ├── hyprflux-install.sh        # ~500 lines (THE installer)
│       └── lib/
│           ├── tui.sh                 # TUI framework
│           ├── common.sh              # Shared utilities
│           └── hyprflux-chroot-wrapper.sh  # Chroot integration
├── efiboot/
│   └── loader/
│       ├── loader.conf
│       └── entries/
│           ├── 01-hyprflux-x86_64-linux.conf
│           └── 02-hyprflux-x86_64-linux-ram.conf
├── grub/
│   └── grub.cfg
├── syslinux/
│   ├── syslinux.cfg
│   ├── archiso_sys.cfg
│   ├── archiso_sys-linux.cfg
│   ├── archiso_head.cfg
│   └── archiso_tail.cfg
├── build.sh                           # Master build script
├── profiledef.sh                      # archiso profile
├── packages.x86_64                    # Live env packages
├── pacman.conf                        # Build-time pacman config
├── test-qemu.sh                       # QEMU test launcher
├── instructions.md                    # Original requirements
├── .gitignore
└── plans/                             # Phase plans (this folder)
    ├── phase-1-archiso-profile.md
    ├── phase-2-boot-configuration.md
    ├── phase-3-tui-framework.md
    ├── phase-4-installer-logic.md
    ├── phase-5-hyprflux-integration.md
    └── phase-6-cicd-testing.md
```

**Total new files:** ~25 files
**Total new code:** ~1400 lines (installer ~500, TUI lib ~200, chroot wrapper ~450, build/config ~150, shims ~100)
**Existing code change:** ~6 lines in HyprFlux `install.sh` (optional, for future standalone ISO mode)

---

## Estimated Implementation Time (All Phases)

| Phase | Time | Description |
|-------|------|-------------|
| Phase 1 | 30-45 min | archiso profile setup |
| Phase 2 | 20-30 min | Boot configs (UEFI + BIOS) |
| Phase 3 | 1-2 hours | TUI framework + branding |
| Phase 4 | 2-4 hours | Installer logic (the big one) |
| Phase 5 | 4-6 hours | HyprFlux chroot wrapper integration |
| Phase 6 | 1 hour | CI/CD workflow update |
| **Total** | **~9-15 hours** | Full implementation |

---

## Validation Steps

1. Push to GitHub, verify CI builds the ISO
2. Download CI-built ISO, test in QEMU
3. Create a test tag (e.g., `v0.1.0-test`), verify release is created
4. Download release ISO and verify SHA256 checksum
5. Full installation test from release ISO

---

## Future Enhancements (Post v1.0)

1. **Pre-built AUR packages** -- bake wallust, wlogout, etc. into the ISO (Approach B, infrastructure already in workflow)
2. **Offline mode** -- include all packages in the ISO for no-internet installs
3. **Custom kernel** -- linux-zen or custom config for better desktop performance
4. **Themed boot screen** -- Custom GRUB/syslinux theme with HyprFlux branding
5. **Automated testing** -- QEMU + expect scripts for CI smoke tests
6. **Secure Boot** -- Sign the ISO for Secure Boot compatibility
7. **A/B update system** -- In-place updates without re-installing
