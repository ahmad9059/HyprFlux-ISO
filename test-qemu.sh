#!/bin/bash
# ============================================================================
# test-qemu.sh — Test the HyprFlux ISO in QEMU
# ============================================================================
# Quick-launch the most recently built ISO in a QEMU virtual machine.
#
# Usage:
#   ./test-qemu.sh                 # UEFI boot (default)
#   ./test-qemu.sh --bios          # Legacy BIOS boot
#   ./test-qemu.sh --headless      # No window; installer over serial console
#   ./test-qemu.sh --software      # GTK window, software rendering (no GL)
#   ./test-qemu.sh --gl            # GTK window, OpenGL acceleration
#   ./test-qemu.sh path/to.iso     # Specific ISO file
#
# Display mode is auto-selected when no flag is given:
#   - no DISPLAY/WAYLAND_DISPLAY  -> headless (serial console, like --headless)
#   - display available           -> GL window; auto-falls back to software
#                                   rendering if GL fails to initialize
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
RAM="8G"
CPUS="4"
DISPLAY_MODE="auto"          # auto | gl | software | headless
SERIAL_MODE=false           # --serial: guest console on the terminal (paste-friendly)
# Default test disk lives next to the script (user-writable). Override with --disk=.
DISK_IMAGE="${SCRIPT_DIR}/hyprflux-test-disk.qcow2"
USE_VNC=false

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
  --headless)
    DISPLAY_MODE="headless"
    ;;
  --software)
    DISPLAY_MODE="software"
    ;;
  --gl)
    DISPLAY_MODE="gl"
    ;;
  --vnc)
    USE_VNC=true
    ;;
  --serial)
    # Guest console on the terminal (stdio). Copy/paste from the host works
    # natively: select text on the host and paste into this terminal — it
    # goes straight into the guest console (ttyS0 autologin runs the
    # installer there too).
    SERIAL_MODE=true
    ;;
  --disk=*)
    DISK_IMAGE="${arg#--disk=}"
    ;;
  --ram=*)
    RAM="${arg#--ram=}"
    ;;
  --cpus=*)
    CPUS="${arg#--cpus=}"
    ;;
  --help | -h)
    echo "Usage: ./test-qemu.sh [OPTIONS] [ISO_FILE]"
    echo ""
    echo "Options:"
    echo "  --bios        Boot in Legacy BIOS mode"
    echo "  --uefi        Boot in UEFI mode (default)"
    echo "  --headless    No window — installer runs over the serial console"
    echo "                (the HyprFlux installer auto-launches on ttyS0)"
    echo "  --software    GTK window with software rendering (no GL)"
    echo "  --gl          GTK window with OpenGL acceleration (default when"
    echo "                a display is available and GL works)"
    echo "  --vnc         Also expose VNC on :0 (works with --headless)"
    echo "  --serial      Guest console on the terminal - host copy/paste works"
    echo "                natively (installer auto-launches on ttyS0)"
    echo "  --disk=PATH   Test disk path (default: ./hyprflux-test-disk.qcow2)"
    echo "  --ram=SIZE    RAM size (default: 8G)"
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

# KVM availability: require it, but degrade gracefully when absent
# (e.g. running inside a VM without nested virtualization).
KVM_OPT=""
if [[ -e /dev/kvm ]] && [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
  KVM_OPT="-enable-kvm -cpu host"
else
  echo "Warning: /dev/kvm not usable — running without hardware acceleration (slow)."
  KVM_OPT="-cpu max"
fi

echo "Testing ISO: ${ISO_FILE}"
echo "Boot mode:   ${BOOT_MODE^^}"
echo "RAM:         ${RAM}"
echo "CPUs:        ${CPUS}"

# ============================================================================
# Display environment sanity check
# ============================================================================
# GTK windows need a reachable display. The classic failure: running under
# sudo(8) — it strips XDG_RUNTIME_DIR (Wayland sockets live under
# /run/user/<uid> and are only discoverable via XDG_RUNTIME_DIR) and can
# inherit a stale DISPLAY whose X socket no longer exists. Detect and
# repair; if a display is genuinely unreachable, explain and go headless
# (the installer's TUI is fully usable over the serial console).
broken_display=""
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    if [[ -n "${SUDO_USER:-}" ]]; then
      # Recover the sudo caller's runtime dir so Wayland works as root too.
      export XDG_RUNTIME_DIR="/run/user/$(id -u "${SUDO_USER}" 2>/dev/null || echo 1000)"
      echo "Note: sudo stripped XDG_RUNTIME_DIR — re-exported for ${SUDO_USER}."
    else
      broken_display="XDG_RUNTIME_DIR is unset (Wayland display unusable)"
    fi
  fi
  if [[ ! -S "${XDG_RUNTIME_DIR:-/nonexistent}/${WAYLAND_DISPLAY}" ]]; then
    broken_display="Wayland socket ${XDG_RUNTIME_DIR:-?}/${WAYLAND_DISPLAY} not found"
  fi
fi
# X11 fallback check (only when Wayland is absent/unusable)
if [[ -z "${broken_display:-}" && -z "${WAYLAND_DISPLAY:-}" && -n "${DISPLAY:-}" ]]; then
  [[ -e "/tmp/.X11-unix/X${DISPLAY#:}" ]] \
    || broken_display="X display ${DISPLAY} has no server socket (/tmp/.X11-unix/X${DISPLAY#:})"
fi
if [[ -n "${broken_display:-}" ]]; then
  echo "Warning: ${broken_display}"
  echo "         Running headless instead — the HyprFlux installer is fully"
  echo "         interactive over the serial console (ttyS0 autologin)."
  DISPLAY_MODE="headless"
fi

# ============================================================================
# Display mode selection
# ============================================================================
if [[ "${DISPLAY_MODE}" == "auto" ]]; then
  if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    DISPLAY_MODE="headless"
    echo "Display mode: headless (no DISPLAY/WAYLAND_DISPLAY found)"
  else
    DISPLAY_MODE="gl"
    echo "Display mode: gl (auto)"
  fi
else
  echo "Display mode: ${DISPLAY_MODE}"
fi

# Build the base QEMU command (display/video added per mode)
build_qemu_cmd() {
  local mode="$1"
  QEMU_CMD=(
    qemu-system-x86_64
    -m "${RAM}"
    -smp "${CPUS}"
    -cdrom "${ISO_FILE}"
    -boot d
  )
  # KVM options expand to two args when available
  if [[ -n "${KVM_OPT}" ]]; then
    # shellcheck disable=SC2206
    QEMU_CMD+=(${KVM_OPT})
  fi

  case "${mode}" in
  headless)
    # No window: the installer's TUI is fully usable over the serial
    # console (ttyS0 autologin), so stdio is interactive.
    QEMU_CMD+=(-display none -serial stdio -monitor none)
    QEMU_CMD+=(-device virtio-vga)
    if [[ "${USE_VNC}" == true ]]; then
      QEMU_CMD+=(-vnc :0)
    fi
    ;;
  software)
    QEMU_CMD+=(-display gtk,show-menubar=off,show-tabs=off)
    QEMU_CMD+=(-device virtio-vga)
    ;;
  gl)
    QEMU_CMD+=(-display gtk,gl=on,show-menubar=off,show-tabs=off)
    QEMU_CMD+=(-device virtio-vga-gl)
    ;;
  esac

  # Serial console on the terminal (for modes that don't already have it):
  # enables host->guest copy/paste through the terminal emulator.
  if [[ "${SERIAL_MODE:-false}" == true ]] && [[ "${mode}" != "headless" ]]; then
    QEMU_CMD+=(-serial stdio -monitor none)
  fi

  # SPICE vdagent channel - clipboard sharing with graphical sessions inside
  # the guest (needs spice-vdagent in the guest; the live ISO ships it now).
  QEMU_CMD+=(
    -device virtio-serial-pci
    -chardev qemu-vdagent,id=vdagent,clipboard=on,name=vdagent
    -device virtserialport,chardev=vdagent,name=com.redhat.spice.0
  )

  QEMU_CMD+=(
    -device virtio-net-pci,netdev=net0
    -netdev user,id=net0
    -device intel-hda
    -device hda-duplex
    -usb
    -device usb-tablet
  )

  # UEFI firmware
  if [[ "${BOOT_MODE}" == "uefi" ]]; then
    if [[ ! -f "${OVMF_CODE}" ]]; then
      echo "Error: OVMF firmware not found at ${OVMF_CODE}"
      echo "Install it: sudo pacman -S edk2-ovmf"
      exit 1
    fi
    OVMF_VARS_COPY="/tmp/hyprflux-ovmf-vars.fd"
    cp "${OVMF_VARS}" "${OVMF_VARS_COPY}"
    QEMU_CMD+=(
      -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}"
      -drive if=pflash,format=raw,file="${OVMF_VARS_COPY}"
    )
  fi

  # Install target disk
  QEMU_CMD+=(
    -drive file="${DISK_IMAGE}",if=virtio,format=qcow2
  )
}

# Always recreate the test disk for a fresh install: delete any previous
# qcow2 first (clean start every run), then create a new one.
# Failure handling is deliberate: /tmp has the sticky bit, so a stale
# root-owned file from an earlier `sudo` run makes a fixed /tmp name
# un-creatable. Fall back to a unique per-user name with numbered retries.
create_test_disk() {
  local path="$1"
  rm -f "${path}" 2>/dev/null || true
  qemu-img create -f qcow2 "${path}" 40G >/dev/null 2>&1
}

if ! create_test_disk "${DISK_IMAGE}"; then
  uid=$(id -u)
  DISK_IMAGE="${TMPDIR:-/tmp}/hyprflux-test-disk-${uid}.qcow2"
  if ! create_test_disk "${DISK_IMAGE}"; then
    for i in 1 2 3 4 5; do
      DISK_IMAGE="${TMPDIR:-/tmp}/hyprflux-test-disk-${uid}-${i}.qcow2"
      if create_test_disk "${DISK_IMAGE}"; then
        break
      fi
    done
  fi
  echo "Configured disk path not usable — using ${DISK_IMAGE}"
fi

try_modes=("${DISPLAY_MODE}")
if [[ "${DISPLAY_MODE}" == "gl" ]]; then
  try_modes+=("software" "headless")
fi

# Launch the fallback chain. Candidate modes run in the background: if QEMU
# dies within 8s it is a display-init failure (GL/GTK) — move to the next
# mode. The last candidate runs in the foreground and never falls through.
first=1
for mode in "${try_modes[@]}"; do
  if [[ $first -ne 1 ]]; then
    echo ""
    echo "Retrying with display mode: ${mode}"
  fi
  first=0

  if [[ "${mode}" == "${try_modes[-1]}" ]]; then
    build_qemu_cmd "${mode}"
    echo ""
    echo "Launching QEMU (${mode})..."
    exec "${QEMU_CMD[@]}"
  fi

  build_qemu_cmd "${mode}"
  echo ""
  echo "Launching QEMU (${mode})..."
  set +e
  "${QEMU_CMD[@]}" &
  qemu_pid=$!
  sleep 8
  if kill -0 "${qemu_pid}" 2>/dev/null; then
    # Still running — display initialized fine. Wait for user exit.
    wait "${qemu_pid}"
    exit $?
  fi
  wait "${qemu_pid}" 2>/dev/null
  rc=$?
  set -e
  echo "  (QEMU exited quickly with code ${rc} — display backend failed)"
done