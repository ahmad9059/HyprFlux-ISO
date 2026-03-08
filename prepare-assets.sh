#!/bin/bash
# prepare-assets.sh — Download external assets needed for the ISO build
# Run this before mkarchiso to fetch assets that can't be committed to the repo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIROOTFS="${SCRIPT_DIR}/airootfs"

echo "=== Preparing external assets ==="

# --- Bibata-Modern-Classic Hyprcursor ---
BIBATA_URL="https://github.com/LOSEARDES77/Bibata-Cursor-hyprcursor/releases/download/1.0/hypr_Bibata-Modern-Classic.tar.gz"
BIBATA_DEST="${AIROOTFS}/usr/share/icons/Bibata-Modern-Classic"

if [[ ! -d "${BIBATA_DEST}" ]]; then
    echo "Downloading Bibata-Modern-Classic hyprcursor..."
    mkdir -p "${BIBATA_DEST}"
    curl -fsSL "${BIBATA_URL}" | tar -xz -C "${BIBATA_DEST}" --strip-components=1
    echo "Done: Bibata cursor"
else
    echo "Skip: Bibata cursor already exists"
fi

# --- Additional wallpapers (optional, from wallpapers-bank) ---
WALLPAPER_DIR="${AIROOTFS}/usr/share/wallpapers"
WALLPAPER_REPO="https://github.com/ahmad9059/wallpapers-bank"

if [[ "${FETCH_WALLPAPERS:-0}" == "1" ]]; then
    echo "Downloading additional wallpapers from wallpapers-bank..."
    TMPDIR=$(mktemp -d)
    git clone --depth 1 "${WALLPAPER_REPO}" "${TMPDIR}/wallpapers-bank"
    # Copy only a curated selection (first 20 images, skip very large ones)
    find "${TMPDIR}/wallpapers-bank" -maxdepth 1 -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -size -5M | head -20 | while read -r img; do
        cp "$img" "${WALLPAPER_DIR}/"
    done
    rm -rf "${TMPDIR}"
    echo "Done: Additional wallpapers"
else
    echo "Skip: Additional wallpapers (set FETCH_WALLPAPERS=1 to download)"
fi

# --- Web App PWA Icons ---
ICON_DIR="${AIROOTFS}/usr/share/icons/hicolor/256x256/apps"
WEBAPPS_CONF="${SCRIPT_DIR}/references/HyprFlux/config/webapps.conf"

echo "Downloading web app PWA icons..."
mkdir -p "${ICON_DIR}"

_download_webapp_icon() {
    local url="$1"
    local name="$2"
    local icon_path="${ICON_DIR}/webapp-${name}.png"

    if [[ -f "${icon_path}" ]]; then
        echo "  Skip: ${name} (already exists)"
        return
    fi

    echo "  Downloading icon for ${name}..."

    # Try Homarr dashboard-icons CDN (light -> dark -> plain)
    local variant
    for variant in "-light" "-dark" ""; do
        if curl -fsSL --max-time 10 \
            "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/${name}${variant}.png" \
            -o "${icon_path}" 2>/dev/null; then
            if file --mime-type "${icon_path}" 2>/dev/null | grep -q "image/png"; then
                echo "  OK: ${name} (Homarr${variant:-/plain})"
                return
            fi
            rm -f "${icon_path}"
        fi
    done

    # Fallback: Google S2 favicon API
    if curl -fsSL --max-time 10 \
        "https://www.google.com/s2/favicons?sz=128&domain=${url}" \
        -o "${icon_path}" 2>/dev/null; then
        if file --mime-type "${icon_path}" 2>/dev/null | grep -q "image/png"; then
            echo "  OK: ${name} (Google S2)"
            return
        fi
        rm -f "${icon_path}"
    fi

    # Fallback: direct favicon.ico from site
    if curl -fsSL --max-time 10 \
        "${url}/favicon.ico" \
        -o "${icon_path}" 2>/dev/null; then
        if file --mime-type "${icon_path}" 2>/dev/null | grep -q "image/"; then
            echo "  OK: ${name} (direct favicon)"
            return
        fi
        rm -f "${icon_path}"
    fi

    echo "  WARN: No icon found for ${name}"
}

if [[ -f "${WEBAPPS_CONF}" ]]; then
    while IFS= read -r line; do
        [[ "${line}" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        IFS="|" read -r _name _url _icon <<< "${line}"
        _download_webapp_icon "${_url}" "${_icon}"
    done < "${WEBAPPS_CONF}"
else
    echo "  WARN: webapps.conf not found at ${WEBAPPS_CONF}, skipping icon downloads."
    echo "  You can manually place PNG icons in ${ICON_DIR}/webapp-<name>.png"
fi

echo "Done: Web app icons"

echo "=== Asset preparation complete ==="
