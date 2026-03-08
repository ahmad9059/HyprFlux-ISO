#!/bin/bash
# ============================================================================
# aur/build-aur.sh — Build AUR packages for the HyprFlux ISO
# ============================================================================
# This script clones AUR PKGBUILDs, builds them with makepkg, and generates
# a local pacman repository database at aur/repo/.
#
# Usage:
#   ./aur/build-aur.sh             # Build all packages
#   ./aur/build-aur.sh yay-bin     # Build a specific package
#
# Requirements:
#   - Must NOT be run as root (makepkg refuses root)
#   - Needs: base-devel, git, curl
#
# The generated repo is referenced by pacman.conf as [hyprflux].
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/repo"
PKGBUILDS_DIR="${SCRIPT_DIR}/PKGBUILDS"
BUILD_DIR="${SCRIPT_DIR}/build"

# AUR packages to build
AUR_PACKAGES=(
    yay-bin
    quickshell
    ttf-fantasque-nerd
    visual-studio-code-bin
    64gram-desktop-bin
    vesktop
    stacer-bin
    localsend-bin
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# =============================================================================
# Pre-flight checks
# =============================================================================
preflight() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run this script as root. makepkg refuses to run as root."
        log_info "Run as a normal user with sudo access (for dependency installation)."
        exit 1
    fi

    local missing=()
    for cmd in git makepkg repo-add curl; do
        command -v "${cmd}" &>/dev/null || missing+=("${cmd}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Install with: sudo pacman -S base-devel git curl"
        exit 1
    fi
}

# =============================================================================
# Clone or update a PKGBUILD from AUR
# =============================================================================
clone_pkgbuild() {
    local pkg="$1"
    local pkg_dir="${BUILD_DIR}/${pkg}"

    if [[ -d "${pkg_dir}" ]]; then
        log_info "Updating ${pkg}..."
        git -C "${pkg_dir}" pull --ff-only 2>/dev/null || {
            log_warn "Pull failed for ${pkg}, re-cloning..."
            rm -rf "${pkg_dir}"
            git clone "https://aur.archlinux.org/${pkg}.git" "${pkg_dir}"
        }
    else
        log_info "Cloning ${pkg} from AUR..."
        git clone "https://aur.archlinux.org/${pkg}.git" "${pkg_dir}"
    fi

    # Save PKGBUILD for reproducibility
    if [[ -f "${pkg_dir}/PKGBUILD" ]]; then
        mkdir -p "${PKGBUILDS_DIR}/${pkg}"
        cp "${pkg_dir}/PKGBUILD" "${PKGBUILDS_DIR}/${pkg}/PKGBUILD"
        # Also copy any .install, patches, etc.
        for f in "${pkg_dir}"/*.install "${pkg_dir}"/*.patch "${pkg_dir}"/*.sh; do
            [[ -f "$f" ]] && cp "$f" "${PKGBUILDS_DIR}/${pkg}/"
        done
    fi
}

# =============================================================================
# Build a single package
# =============================================================================
build_package() {
    local pkg="$1"
    local pkg_dir="${BUILD_DIR}/${pkg}"

    if [[ ! -f "${pkg_dir}/PKGBUILD" ]]; then
        log_error "No PKGBUILD found for ${pkg} in ${pkg_dir}"
        return 1
    fi

    log_info "Building ${pkg}..."

    # Build with makepkg
    # -s: install dependencies (needs sudo)
    # -r: remove build-time dependencies after build
    # -c: clean up work files after build
    # --noconfirm: don't ask questions
    # --needed: skip if already built
    (
        cd "${pkg_dir}"
        makepkg -src --noconfirm --needed 2>&1 | while IFS= read -r line; do
            echo "  [${pkg}] ${line}"
        done
    )

    # Copy built packages to repo
    local found=false
    for pkg_file in "${pkg_dir}"/*.pkg.tar.zst; do
        if [[ -f "${pkg_file}" ]]; then
            cp "${pkg_file}" "${REPO_DIR}/"
            log_ok "Built: $(basename "${pkg_file}")"
            found=true
        fi
    done

    if [[ "${found}" != true ]]; then
        # Try .pkg.tar.xz as fallback
        for pkg_file in "${pkg_dir}"/*.pkg.tar.xz; do
            if [[ -f "${pkg_file}" ]]; then
                cp "${pkg_file}" "${REPO_DIR}/"
                log_ok "Built: $(basename "${pkg_file}")"
                found=true
            fi
        done
    fi

    if [[ "${found}" != true ]]; then
        log_error "No package file produced for ${pkg}"
        return 1
    fi
}

# =============================================================================
# Generate the local repo database
# =============================================================================
generate_repo_db() {
    log_info "Generating repository database..."

    # Remove old database files
    rm -f "${REPO_DIR}"/hyprflux.db* "${REPO_DIR}"/hyprflux.files*

    # Add all packages to the repo
    local count=0
    for pkg_file in "${REPO_DIR}"/*.pkg.tar.{zst,xz}; do
        if [[ -f "${pkg_file}" ]]; then
            repo-add "${REPO_DIR}/hyprflux.db.tar.gz" "${pkg_file}"
            ((count++))
        fi
    done

    if [[ ${count} -eq 0 ]]; then
        log_error "No packages found in ${REPO_DIR}/"
        return 1
    fi

    log_ok "Repository database generated with ${count} packages"
}

# =============================================================================
# Main
# =============================================================================
main() {
    preflight

    echo "============================================"
    echo " HyprFlux AUR Package Builder"
    echo "============================================"

    mkdir -p "${REPO_DIR}" "${BUILD_DIR}" "${PKGBUILDS_DIR}"

    # Determine which packages to build
    local packages_to_build=()
    if [[ $# -gt 0 ]]; then
        packages_to_build=("$@")
    else
        packages_to_build=("${AUR_PACKAGES[@]}")
    fi

    local failed=()
    local succeeded=()

    for pkg in "${packages_to_build[@]}"; do
        echo ""
        echo "--- ${pkg} ---"
        if clone_pkgbuild "${pkg}" && build_package "${pkg}"; then
            succeeded+=("${pkg}")
        else
            log_error "Failed to build ${pkg}"
            failed+=("${pkg}")
        fi
    done

    echo ""
    echo "============================================"

    # Generate repo database
    generate_repo_db

    echo ""
    echo "============================================"
    echo " Build Summary"
    echo "============================================"
    echo -e " ${GREEN}Succeeded: ${#succeeded[@]}${NC}"
    for pkg in "${succeeded[@]}"; do
        echo -e "   ${GREEN}+${NC} ${pkg}"
    done
    if [[ ${#failed[@]} -gt 0 ]]; then
        echo -e " ${RED}Failed: ${#failed[@]}${NC}"
        for pkg in "${failed[@]}"; do
            echo -e "   ${RED}x${NC} ${pkg}"
        done
    fi
    echo ""
    echo " Repo: ${REPO_DIR}/"
    echo " Packages:"
    ls -lh "${REPO_DIR}"/*.pkg.tar.{zst,xz} 2>/dev/null | awk '{print "   "$NF" ("$5")"}'
    echo "============================================"

    if [[ ${#failed[@]} -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
