#!/bin/bash
# TEST VM ONLY. This file is never copied into the production live filesystem.
set -euo pipefail
[[ "${1:-}" == "" || "${1:-}" == --resume ]] || exit 96
test_exit() {
    local rc=$?
    if (( rc != 0 )); then
        if [[ -n "${_TEST_VM_CONFIRMED:-}" ]]; then
            # The host stops QEMU as soon as it sees the failure marker. Flush
            # guest lock-file removals and filesystem metadata BEFORE that.
            sync || true
            local target="${MOUNT_POINT:-/mnt/archinstall}"
            if mountpoint -q "$target"; then
                mkdir -p "$target/var/log/hyprflux-installer/failed-live" \
                    && cp -a "${INSTALL_LOG_DIR:-/var/log/hyprflux-installer}/." \
                        "$target/var/log/hyprflux-installer/failed-live/" || true
                umount -R "$target" || echo 'WARNING: failed to unmount test target during error cleanup'
            fi
            if [[ -n "${SWAP_PART:-}" ]]; then swapoff "$SWAP_PART" || true; fi
            sync || true
        fi
        echo "HYPRFLUX_TEST_FAILED preflight-or-install-exit=$rc"
    fi
}
trap test_exit EXIT
[[ $(systemd-detect-virt) == qemu || $(systemd-detect-virt) == kvm ]] || exit 90
grep -q 'hyprflux.test=1' /proc/cmdline || exit 93
disk=$(sed -n 's/.*hyprflux.testdisk=\([^ ]*\).*/\1/p' /proc/cmdline)
[[ "$disk" == vda || "$disk" == sda || "$disk" == nvme0n1 ]] || exit 91
disk="/dev/$disk"
[[ -b "$disk" && $(lsblk -dnro SIZE "$disk") == 40G ]] || exit 92
[[ $(lsblk -dnro TYPE | grep -c '^disk$') == 1 ]] || exit 94
test_swap=$(sed -n 's/.*hyprflux.testswap=\([^ ]*\).*/\1/p' /proc/cmdline)
[[ "$test_swap" =~ ^[0-8]$ ]] || exit 95
test_profile=$(sed -n 's/.*hyprflux.profile=\([^ ]*\).*/\1/p' /proc/cmdline)
[[ "$test_profile" == desktop || "$test_profile" == full ]] || exit 97
_TEST_VM_CONFIRMED=1

if [[ "${HYPRFLUX_TEST_EMBEDDED:-0}" == 1 ]]; then
    echo '==> Testing the ISO embedded installer at /root/hyprflux-install.sh'
    source /root/hyprflux-install.sh
else
    cp -a /run/hyprflux-source/airootfs/root /root/hyprflux-test
    source /root/hyprflux-test/hyprflux-install.sh
fi
# tui.sh installs its own EXIT trap; restore the test cleanup after sourcing it.
trap test_exit EXIT
trap 'echo "ERROR: installation command failed at line $LINENO"; exit 1' ERR
show_banner() { :; }
set_status() { echo "==> $*"; }
tui_wait() { :; }
start_progress() {
    INSTALL_LOG_DIR=/var/log/hyprflux-installer
    mkdir -p "$INSTALL_LOG_DIR"
    PROGRESS_LOG="$INSTALL_LOG_DIR/automated-install.log"
    if [[ -z "${_TEST_LOG_TAIL_PID:-}" ]]; then
        touch "$PROGRESS_LOG"
        tail --pid=$$ -n 0 -F "$PROGRESS_LOG" &
        _TEST_LOG_TAIL_PID=$!
    fi
    printf '==> %s\n' "$*"
}
stop_progress() { :; }
die() { echo "ERROR: $*"; tail -80 "$PROGRESS_LOG"; exit 1; }
tui_menu() { echo "$disk (40G) QEMU test disk"; }
tui_input() { if [[ "$1" == 'Swap size'* ]]; then echo "$test_swap"; else echo yes; fi; }
tui_yesno() { (( test_swap > 0 )); }
tui_spinner() { shift; "$@"; }
tui_success_box() { echo "$*"; }
tui_warning_box() { echo "$*"; }
tui_error() { echo "ERROR: $*"; }

copy_test_package_cache() {
    local source="$1" destination="$2" package copied=0
    mkdir -p "$destination"
    for package in "$source"/*.pkg.tar.zst "$source"/*.pkg.tar.xz \
        "$source"/*.pkg.tar.zst.sig "$source"/*.pkg.tar.xz.sig; do
        [[ -f "$package" && ! -L "$package" ]] || continue
        [[ ! -e "$destination/${package##*/}" && ! -L "$destination/${package##*/}" ]] || continue
        cp --reflink=auto -- "$package" "$destination/" || return 1
        copied=$((copied + 1))
    done
    printf '==> Seeded %s cached package/signature files; pacman will validate them normally.\n' "$copied"
}

seed_test_package_cache() {
    [[ "${HYPRFLUX_TEST_PACKAGE_CACHE:-0}" == 1 ]] || return 0
    mkdir -p /run/hyprflux-pkgcache
    mount -t 9p -o trans=virtio,version=9p2000.L,ro hyprflux-pkgcache /run/hyprflux-pkgcache
    copy_test_package_cache /run/hyprflux-pkgcache "$MOUNT_POINT/var/cache/pacman/pkg"
}

prepare_manual_layout_fixture() {
    # Only called after the VM-only, single 40 GiB disk guards above pass.
    # A separate fixture, not step_disk_auto, exercises pre-existing mounts.
    local prefix root_partition boot_partition attempt
    prefix=$(get_part_prefix "$disk") || return 1
    root_partition="${prefix}2"
    boot_partition="${prefix}1"
    sgdisk -o "$disk" || return 1
    if [[ "$INSTALL_BOOT_MODE" == uefi ]]; then
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:EFI "$disk" || return 1
    else
        sgdisk -n 1:0:+2M -t 1:ef02 -c 1:BIOS "$disk" || return 1
    fi
    sgdisk -n 2:0:0 -t 2:8300 -c 2:Root "$disk" || return 1
    partprobe "$disk" || return 1
    udevadm settle || return 1
    for ((attempt=0; attempt<30; attempt++)); do
        [[ -b "$root_partition" && -b "$boot_partition" ]] && break
        sleep 1
    done
    [[ -b "$root_partition" && -b "$boot_partition" ]] || return 1
    mkfs.ext4 -F "$root_partition" || return 1
    mkdir -p "$MOUNT_POINT" || return 1
    mount -t ext4 "$root_partition" "$MOUNT_POINT" || return 1
    if [[ "$INSTALL_BOOT_MODE" == uefi ]]; then
        mkfs.fat -F32 "$boot_partition" || return 1
        mkdir -p "$MOUNT_POINT/boot" || return 1
        mount -t vfat "$boot_partition" "$MOUNT_POINT/boot" || return 1
    fi
}

run_test_manual_layout() {
    echo '==> Testing manual GPT layout validation (automated shell fixture, not human TUI acceptance).'
    read() { :; }
    bash() { prepare_manual_layout_fixture; }
    step_disk_manual
    unset -f read bash
}

INSTALL_TIMEZONE=UTC
INSTALL_LOCALE=en_US.UTF-8
INSTALL_KEYMAP=us
INSTALL_HOSTNAME=hyprflux-test
INSTALL_USERNAME=fluxcheck
# Public, disposable VM-only credentials. Never used in a production image.
INSTALL_PASSWORD=hyprflux-test-only
INSTALL_BOOT_MODE=$(detect_boot_mode)
INSTALL_HAS_NVIDIA=no
INSTALL_PROFILE="$test_profile"
check_internet || die 'VM network unavailable'
if [[ "${1:-}" == --resume ]]; then
    # Only recover this harness's known, already-configured test installation.
    # Never rerun partitioning, mkfs, pacstrap, useradd or password setup.
    ROOT_PART=$(lsblk -nrpo NAME,PARTLABEL "$disk" | awk '$2 == "Root" {print $1}')
    EFI_PART=$(lsblk -nrpo NAME,PARTLABEL "$disk" | awk '$2 == "EFI" {print $1}')
    SWAP_PART=$(lsblk -nrpo NAME,PARTLABEL "$disk" | awk '$2 == "Swap" {print $1}')
    [[ -b "$ROOT_PART" && $(blkid -s TYPE -o value "$ROOT_PART") == ext4 ]]
    mkdir -p "$MOUNT_POINT"
    mount -t ext4 "$ROOT_PART" "$MOUNT_POINT"
    grep -Fxq "HYPRFLUX_REF=$HYPRFLUX_REF" "$MOUNT_POINT/etc/hyprflux-install-release"
    arch-chroot "$MOUNT_POINT" id fluxcheck
    if [[ "$INSTALL_BOOT_MODE" == uefi ]]; then
        [[ -b "$EFI_PART" ]]
        mount -t vfat "$EFI_PART" "$MOUNT_POINT/boot"
    fi
    if [[ -n "$SWAP_PART" ]]; then swapon "$SWAP_PART"; fi
    INSTALL_DISK="$disk"
    cp "$SCRIPT_DIR/lib/configure-initramfs.sh" "$MOUNT_POINT/root/configure-initramfs.sh"
    echo '==> Resuming desktop integration; existing partitions and packages preserved.'
else
    if [[ "${HYPRFLUX_TEST_MANUAL_LAYOUT:-0}" == 1 ]]; then
        run_test_manual_layout
    else
        step_disk_auto
    fi
    seed_test_package_cache
    step_base_install
    step_configure_system
fi
if [[ "${1:-}" == --resume ]]; then seed_test_package_cache; fi
step_install_hyprflux

[[ $(cat "$MOUNT_POINT/etc/hyprflux-install-profile") == "$INSTALL_PROFILE" ]]
echo "HYPRFLUX_INSTALLED_PROFILE=$INSTALL_PROFILE"
if [[ -s "$MOUNT_POINT/var/log/hyprflux-installer/missing-applications.txt" ]]; then
    echo HYPRFLUX_OPTIONAL_MISSING_BEGIN
    cat "$MOUNT_POINT/var/log/hyprflux-installer/missing-applications.txt"
    echo HYPRFLUX_OPTIONAL_MISSING_END
else
    echo HYPRFLUX_OPTIONAL_MISSING_NONE
fi

# Test-only autologin lets us check a real SDDM -> Hyprland session after reboot.
mkdir -p "$MOUNT_POINT/etc/sddm.conf.d"
cat > "$MOUNT_POINT/etc/sddm.conf.d/99-test-autologin.conf" <<'EOF'
[Autologin]
User=fluxcheck
Session=hyprland.desktop
EOF
cp /run/hyprflux-source/tests/guest-verify.sh "$MOUNT_POINT/root/guest-verify.sh"
cat > "$MOUNT_POINT/etc/systemd/system/hyprflux-test-verify.service" <<'EOF'
[Unit]
After=display-manager.service
[Service]
Type=oneshot
ExecStart=/bin/bash /root/guest-verify.sh
StandardOutput=tty
StandardError=tty
TTYPath=/dev/ttyS0
[Install]
WantedBy=graphical.target
EOF
arch-chroot "$MOUNT_POINT" systemctl enable hyprflux-test-verify.service
# Exercise production cleanup. Suppress only its confirmation keystroke; the
# actual reboot is executed, with QEMU's -no-reboot stopping the test VM.
read() { return 0; }
systemctl() {
    if [[ "$1" == reboot ]]; then echo HYPRFLUX_TEST_INSTALL_PASS; sleep 1; fi
    command systemctl "$@"
}
step_cleanup_reboot
