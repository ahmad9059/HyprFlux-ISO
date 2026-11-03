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
OUT_DIR="${SCRIPT_DIR}/out/build-$(date -u +%Y%m%dT%H%M%SZ)-$$"
PROFILE_DIR="$SCRIPT_DIR"
STAGED_PROFILE=""
export HYPRFLUX_COMPRESSION="${HYPRFLUX_COMPRESSION:-xz}"
[[ "$HYPRFLUX_COMPRESSION" == xz || "$HYPRFLUX_COMPRESSION" == zstd ]] \
    || { echo 'HYPRFLUX_COMPRESSION must be xz or zstd.' >&2; exit 2; }
cleanup_profile() {
    if [[ -n "$STAGED_PROFILE" ]]; then
        rm -rf -- "$STAGED_PROFILE"
    fi
}
trap cleanup_profile EXIT

# --------------------------------------------------------------------------
# Preflight checks
# --------------------------------------------------------------------------

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (mkarchiso requires it)."
    echo "Usage: sudo bash build.sh"
    exit 1
fi

# Serialise builds before either one can clean the shared work tree.
exec 9>"${SCRIPT_DIR}/.hyprflux-build.lock"
flock -n 9 || { echo 'Error: Another ISO build is running.' >&2; exit 1; }

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

# Fail before expensive/destructive build preparation if signing was requested
# but the release key is unavailable. Keys are never staged into the profile.
bash "${SCRIPT_DIR}/scripts/sign-iso.sh" --check

# --------------------------------------------------------------------------
# Clean previous build artifacts
# --------------------------------------------------------------------------
# Safety: an interrupted build leaves mount binds inside work/x86_64/airootfs.
# rm -rf'ing a mounted tree can silently delete the BOUND host data, so abort
# with instructions instead (see the Arch Wiki archiso warning).
if findmnt -rn -o TARGET | awk -v root="$WORK_DIR" \
    '$0 == root || index($0, root "/") == 1 {found=1} END {exit !found}'; then
    echo "Error: Previous build is still mounted (interrupted build?)."
    echo "Unmount it first:"
    echo "    findmnt ${WORK_DIR}/x86_64/airootfs"
    echo "    umount -R ${WORK_DIR}/x86_64/airootfs"
    exit 1
fi

echo "==> Cleaning previous build artifacts..."
rm -rf "${WORK_DIR}"
mkdir -p "${OUT_DIR}"

# Optional acceleration, not an offline installation mode. Keep generated cache
# content out of the source profile and preserve every prior candidate ISO.
if [[ -n "${HYPRFLUX_PACKAGE_CACHE:-}" || "$HYPRFLUX_COMPRESSION" == zstd ]]; then
    command -v python3 >/dev/null || { echo 'Python 3 is required for package-cache staging.' >&2; exit 1; }
    STAGED_PROFILE=$(mktemp -d "${TMPDIR:-/tmp}/hyprflux-profile.XXXXXXXX")
    for entry in profiledef.sh pacman.conf packages.x86_64 airootfs efiboot grub syslinux; do
        cp -a -- "${SCRIPT_DIR}/${entry}" "${STAGED_PROFILE}/"
    done
    if [[ -n "${HYPRFLUX_PACKAGE_CACHE:-}" ]]; then
        # Sync metadata into an EMPTY isolated database. Do not partially
        # upgrade or change the native build host's installed/sync databases.
        mkdir -p "${STAGED_PROFILE}/cache-db/local" "${STAGED_PROFILE}/cache-db/sync"
        echo '==> Refreshing isolated cache metadata (host package database unchanged)...'
        timeout --kill-after=5s 180 pacman --config "${SCRIPT_DIR}/pacman.conf" \
            --dbpath "${STAGED_PROFILE}/cache-db" --logfile "${STAGED_PROFILE}/cache-db/pacman.log" \
            -Sy --noconfirm
        pacman --config "${SCRIPT_DIR}/pacman.conf" --dbpath "${STAGED_PROFILE}/cache-db" -Sl \
            > "${STAGED_PROFILE}/repository-packages.txt"
        python3 "${SCRIPT_DIR}/airootfs/root/lib/package-cache.py" stage \
            "$HYPRFLUX_PACKAGE_CACHE" "${STAGED_PROFILE}/airootfs/opt/hyprflux/package-cache" \
            --limit-mib "${HYPRFLUX_CACHE_LIMIT_MIB:-2048}" \
            --repository-list "${STAGED_PROFILE}/repository-packages.txt"
        cp "${STAGED_PROFILE}/airootfs/opt/hyprflux/package-cache/manifest.json" \
            "${OUT_DIR}/package-cache-manifest.json"
    fi
    if [[ "$HYPRFLUX_COMPRESSION" == zstd ]]; then
        sed -i 's/^COMPRESSION=.*/COMPRESSION="zstd"/; s/^COMPRESSION_OPTIONS=.*/COMPRESSION_OPTIONS=(-T2 -3)/' \
            "${STAGED_PROFILE}/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
    fi
    PROFILE_DIR="$STAGED_PROFILE"
fi

# --------------------------------------------------------------------------
# Build ISO
# --------------------------------------------------------------------------
echo "==> Building HyprFlux ISO..."
echo "    This will take 5-15 minutes depending on internet speed and disk I/O."
echo ""

mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${PROFILE_DIR}"

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
    (cd "$OUT_DIR" && sha256sum "$(basename "$ISO_FILE")" > "$(basename "$ISO_FILE").sha256")
    bash "${SCRIPT_DIR}/scripts/sign-iso.sh" "$ISO_FILE"
    echo "  SHA256: $(cut -d' ' -f1 "${ISO_FILE}.sha256")"
    echo "============================================"
    echo ""

    # Offer to clean work directory (saves ~5-10GB disk space)
    clean_ans=n
    if [[ -t 0 ]]; then
        read -rp "Clean work directory to free disk space? [Y/n]: " clean_ans || clean_ans=n
    fi
    if [[ "${clean_ans,,}" != "n" ]]; then
        saved_size=$(du -sh "${WORK_DIR}" 2>/dev/null | cut -f1 || echo "several GB")
        echo "==> Cleaning work directory..."
        rm -rf "${WORK_DIR}"
        echo "    Done. Freed ${saved_size} of disk space."
    fi
else
    echo ""
    echo "Error: No ISO file found in ${OUT_DIR}/"
    echo "Check the build output above for errors."
    exit 1
fi
