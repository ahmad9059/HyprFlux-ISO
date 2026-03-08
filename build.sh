#!/bin/bash
# ============================================================================
# build.sh — HyprFlux ISO Build Script
# ============================================================================
# Wraps mkarchiso with pre-build steps:
#   1. Build AUR packages (if not already built)
#   2. Download external assets (Bibata cursor, PWA icons)
#   3. Fix pacman.conf local repo path to be absolute
#   4. Run mkarchiso to produce the ISO
#
# Usage:
#   sudo ./build.sh              # Full build
#   sudo ./build.sh --skip-aur   # Skip AUR package build
#   sudo ./build.sh --clean      # Clean work dir before building
#
# The ISO will be placed in ./out/
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/work"
OUT_DIR="${SCRIPT_DIR}/out"
AUR_REPO_DIR="${SCRIPT_DIR}/aur/repo"
PACMAN_CONF="${SCRIPT_DIR}/pacman.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Parse arguments
SKIP_AUR=false
CLEAN=false
for arg in "$@"; do
    case "${arg}" in
        --skip-aur) SKIP_AUR=true ;;
        --clean)    CLEAN=true ;;
        --help|-h)
            echo "Usage: sudo ./build.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-aur    Skip AUR package building"
            echo "  --clean       Remove work directory before building"
            echo "  --help        Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: ${arg}"
            exit 1
            ;;
    esac
done

# =============================================================================
# Pre-flight
# =============================================================================
echo -e "${BOLD}"
echo "  ╦ ╦┬ ┬┌─┐┬─┐╔═╗┬  ┬ ┬─┐ ┬"
echo "  ╠═╣└┬┘├─┘├┬┘╠╣ │  │ │┌┴┬┘"
echo "  ╩ ╩ ┴ ┴  ┴└─╚  ┴─┘└─┘┴ └─"
echo "        ISO Builder"
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo ./build.sh)"
    exit 1
fi

if ! command -v mkarchiso &>/dev/null; then
    log_error "mkarchiso not found. Install archiso: sudo pacman -S archiso"
    exit 1
fi

# =============================================================================
# Step 0: Clean work directory if requested
# =============================================================================
if [[ "${CLEAN}" == true ]]; then
    log_info "Cleaning work directory..."
    rm -rf "${WORK_DIR}"
    log_ok "Work directory cleaned"
fi

# =============================================================================
# Step 1: Build AUR packages
# =============================================================================
if [[ "${SKIP_AUR}" == true ]]; then
    log_info "Skipping AUR package build (--skip-aur)"
else
    if [[ -f "${AUR_REPO_DIR}/hyprflux.db.tar.gz" ]]; then
        local_pkg_count=$(find "${AUR_REPO_DIR}" -name "*.pkg.tar.*" 2>/dev/null | wc -l)
        log_info "AUR repo already exists with ${local_pkg_count} packages"
        log_info "To rebuild, delete ${AUR_REPO_DIR}/ and run again"
    else
        log_info "Building AUR packages..."
        # AUR packages must be built as non-root
        # Find the real user who invoked sudo
        REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo nobody)}"
        if [[ "${REAL_USER}" == "root" ]] || [[ "${REAL_USER}" == "nobody" ]]; then
            log_warn "Cannot determine non-root user for AUR build."
            log_warn "Run 'aur/build-aur.sh' manually as a regular user first, then:"
            log_warn "  sudo ./build.sh --skip-aur"
        else
            log_info "Building AUR packages as user '${REAL_USER}'..."
            sudo -u "${REAL_USER}" "${SCRIPT_DIR}/aur/build-aur.sh"
        fi
    fi
fi

# Verify AUR repo exists
if [[ ! -f "${AUR_REPO_DIR}/hyprflux.db.tar.gz" ]]; then
    log_warn "AUR repository not found at ${AUR_REPO_DIR}/"
    log_warn "AUR packages will not be available in the ISO."
    log_warn "The build will continue but packages from [hyprflux] repo will fail."

    read -rp "Continue anyway? [y/N] " response
    if [[ ! "${response}" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# =============================================================================
# Step 2: Download external assets
# =============================================================================
log_info "Preparing external assets..."
bash "${SCRIPT_DIR}/prepare-assets.sh"

# =============================================================================
# Step 3: Fix pacman.conf local repo path
# =============================================================================
# The pacman.conf has a placeholder or hardcoded path for the [hyprflux] repo.
# We need to make it point to the absolute path of our repo directory.
log_info "Updating pacman.conf repo path..."

PACMAN_CONF_BUILD="${WORK_DIR}/pacman.conf.build"
mkdir -p "${WORK_DIR}"

# Create a build-time copy with the correct absolute path
sed "s|Server = file:///.*aur/repo|Server = file://${AUR_REPO_DIR}|" \
    "${PACMAN_CONF}" > "${PACMAN_CONF_BUILD}"

log_ok "pacman.conf updated with repo path: file://${AUR_REPO_DIR}"

# =============================================================================
# Step 4: Build ISO
# =============================================================================
log_info "Building ISO with mkarchiso..."
log_info "  Profile:  ${SCRIPT_DIR}"
log_info "  Work dir: ${WORK_DIR}"
log_info "  Output:   ${OUT_DIR}"
echo ""

mkarchiso -v \
    -C "${PACMAN_CONF_BUILD}" \
    -w "${WORK_DIR}" \
    -o "${OUT_DIR}" \
    "${SCRIPT_DIR}"

echo ""
echo "============================================"
echo -e "${GREEN}${BOLD} ISO Build Complete!${NC}"
echo "============================================"

# Show the built ISO
ISO_FILE=$(ls -t "${OUT_DIR}"/*.iso 2>/dev/null | head -1)
if [[ -n "${ISO_FILE}" ]]; then
    ISO_SIZE=$(du -h "${ISO_FILE}" | cut -f1)
    echo ""
    echo "  ISO:  ${ISO_FILE}"
    echo "  Size: ${ISO_SIZE}"
    echo ""
    echo "  Test with QEMU:"
    echo "    ./test-qemu.sh"
    echo ""
    echo "  Write to USB:"
    echo "    sudo dd bs=4M if=${ISO_FILE} of=/dev/sdX status=progress oflag=sync"
else
    log_warn "No ISO file found in ${OUT_DIR}/"
fi

echo "============================================"
