#!/bin/bash
# build.sh -- Build the HyprFlux ISO
#
# Usage:
#   sudo bash build.sh
#
# Requirements:
#   - archiso package installed
#   - Must be run as root
#   - Run from the repo root (where profiledef.sh lives)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/work"
OUT_DIR="${SCRIPT_DIR}/out"

# --------------------------------------------------------------------------
# Preflight checks
# --------------------------------------------------------------------------

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (mkarchiso requires it)."
    echo "Usage: sudo bash build.sh"
    exit 1
fi

# Check archiso is installed
if ! command -v mkarchiso &>/dev/null; then
    echo "Error: archiso is not installed."
    read -rp "Install it now? [y/N]: " ans
    if [[ "${ans,,}" == "y" ]]; then
        pacman -S --noconfirm archiso
    else
        exit 1
    fi
fi

# Verify we're in the right directory (profiledef.sh must exist)
if [[ ! -f "${SCRIPT_DIR}/profiledef.sh" ]]; then
    echo "Error: profiledef.sh not found in ${SCRIPT_DIR}"
    echo "Are you running this from the repo root?"
    exit 1
fi

# --------------------------------------------------------------------------
# Clean previous build artifacts
# --------------------------------------------------------------------------
echo "==> Cleaning previous build artifacts..."
rm -rf "${WORK_DIR}" "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

# --------------------------------------------------------------------------
# Build ISO
# --------------------------------------------------------------------------
echo "==> Building HyprFlux ISO..."
echo "    This will take 5-15 minutes depending on internet speed and disk I/O."
echo ""

mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${SCRIPT_DIR}"

# --------------------------------------------------------------------------
# Report results
# --------------------------------------------------------------------------
ISO_FILE=$(find "${OUT_DIR}" -maxdepth 1 -name '*.iso' -print -quit 2>/dev/null)

if [[ -n "$ISO_FILE" ]]; then
    ISO_SIZE=$(du -h "$ISO_FILE" | cut -f1)
    echo ""
    echo "============================================"
    echo "  Build Complete"
    echo "============================================"
    echo "  ISO:  ${ISO_FILE}"
    echo "  Size: ${ISO_SIZE}"

    # Generate SHA256
    sha256sum "$ISO_FILE" > "${ISO_FILE}.sha256"
    echo "  SHA256: $(cut -d' ' -f1 "${ISO_FILE}.sha256")"
    echo "============================================"
    echo ""

    # Offer to clean work directory (saves ~5-10GB disk space)
    read -rp "Clean work directory to free disk space? [Y/n]: " clean_ans
    if [[ "${clean_ans,,}" != "n" ]]; then
        echo "==> Cleaning work directory..."
        rm -rf "${WORK_DIR}"
        echo "    Done. Saved $(du -sh "${WORK_DIR}" 2>/dev/null | cut -f1 || echo 'several GB') of disk space."
    fi
else
    echo ""
    echo "Error: No ISO file found in ${OUT_DIR}/"
    echo "Check the build output above for errors."
    exit 1
fi
