#!/bin/bash
# ============================================================================
# test-qemu.sh — Test the HyprFlux ISO in QEMU
# ============================================================================
# Quick-launch the most recently built ISO in a QEMU virtual machine.
#
# Usage:
#   ./test-qemu.sh              # UEFI boot (default)
#   ./test-qemu.sh --bios       # Legacy BIOS boot
#   ./test-qemu.sh path/to.iso  # Specific ISO file
#
# Requirements:
#   - qemu-desktop (or qemu-full)
#   - edk2-ovmf (for UEFI boot)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/out"

# Defaults
BOOT_MODE="uefi"
ISO_FILE=""
RAM="4G"
CPUS="4"
DISPLAY_OPT="-display gtk,gl=on"

# OVMF firmware paths (Arch Linux)
OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS="/usr/share/edk2/x64/OVMF_VARS.4m.fd"

# Parse arguments
for arg in "$@"; do
    case "${arg}" in
        --bios)
            BOOT_MODE="bios"
            ;;
        --uefi)
            BOOT_MODE="uefi"
            ;;
        --ram=*)
            RAM="${arg#--ram=}"
            ;;
        --cpus=*)
            CPUS="${arg#--cpus=}"
            ;;
        --help|-h)
            echo "Usage: ./test-qemu.sh [OPTIONS] [ISO_FILE]"
            echo ""
            echo "Options:"
            echo "  --bios        Boot in Legacy BIOS mode"
            echo "  --uefi        Boot in UEFI mode (default)"
            echo "  --ram=SIZE    RAM size (default: 4G)"
            echo "  --cpus=N      Number of CPUs (default: 4)"
            echo "  --help        Show this help"
            exit 0
            ;;
        *.iso)
            ISO_FILE="${arg}"
            ;;
        *)
            echo "Unknown option: ${arg}"
            exit 1
            ;;
    esac
done

# Find ISO if not specified
if [[ -z "${ISO_FILE}" ]]; then
    ISO_FILE=$(ls -t "${OUT_DIR}"/*.iso 2>/dev/null | head -1)
    if [[ -z "${ISO_FILE}" ]]; then
        echo "Error: No ISO found in ${OUT_DIR}/"
        echo "Run ./build.sh first to build the ISO."
        exit 1
    fi
fi

if [[ ! -f "${ISO_FILE}" ]]; then
    echo "Error: ISO file not found: ${ISO_FILE}"
    exit 1
fi

echo "Testing ISO: ${ISO_FILE}"
echo "Boot mode:   ${BOOT_MODE^^}"
echo "RAM:         ${RAM}"
echo "CPUs:        ${CPUS}"
echo ""

# Build QEMU command
QEMU_CMD=(
    qemu-system-x86_64
    -m "${RAM}"
    -smp "${CPUS}"
    -cdrom "${ISO_FILE}"
    -boot d
    -enable-kvm
    -cpu host
    -device virtio-vga-gl
    -device virtio-net-pci,netdev=net0
    -netdev user,id=net0
    -device intel-hda
    -device hda-duplex
    -usb
    -device usb-tablet
    ${DISPLAY_OPT}
)

# Add UEFI firmware if needed
if [[ "${BOOT_MODE}" == "uefi" ]]; then
    if [[ ! -f "${OVMF_CODE}" ]]; then
        echo "Error: OVMF firmware not found at ${OVMF_CODE}"
        echo "Install it: sudo pacman -S edk2-ovmf"
        exit 1
    fi

    # Create a writable copy of OVMF_VARS for this session
    OVMF_VARS_COPY="/tmp/hyprflux-ovmf-vars.fd"
    cp "${OVMF_VARS}" "${OVMF_VARS_COPY}"

    QEMU_CMD+=(
        -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}"
        -drive if=pflash,format=raw,file="${OVMF_VARS_COPY}"
    )
fi

# Add a virtual disk for installation testing
QEMU_CMD+=(
    -drive file=/tmp/hyprflux-test-disk.qcow2,if=virtio,format=qcow2
)

# Always recreate the test disk for a fresh install
echo "Creating fresh 30G test disk..."
rm -f /tmp/hyprflux-test-disk.qcow2
qemu-img create -f qcow2 /tmp/hyprflux-test-disk.qcow2 30G

echo "Launching QEMU..."
exec "${QEMU_CMD[@]}"
