#!/bin/bash
# Optional detached release signature. A checksum alone is not authentication.
set -euo pipefail
key="${HYPRFLUX_SIGNING_KEY:-}"
if [[ -z "$key" ]]; then
    if [[ "${HYPRFLUX_REQUIRE_SIGNATURE:-0}" == 1 ]]; then
        echo 'A release signing key is required but HYPRFLUX_SIGNING_KEY is unset.' >&2
        exit 1
    fi
    echo 'Unsigned development build: release signing key not configured.'
    exit 0
fi
command -v gpg >/dev/null || { echo 'GnuPG is required for release signing.' >&2; exit 1; }
gpg --batch --list-secret-keys "$key" >/dev/null 2>&1 \
    || { echo 'Configured release secret key is unavailable.' >&2; exit 1; }
[[ "${1:-}" == --check ]] && exit 0
[[ $# == 1 && -f "$1" && ! -L "$1" ]] || { echo 'Usage: sign-iso.sh ISO_FILE' >&2; exit 2; }
image="$1"
signature=$(mktemp "${image}.asc.XXXXXXXX")
trap 'rm -f -- "$signature"' EXIT
# Passphrase uses a private descriptor, never a command argument or build log.
gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
    --armor --local-user "$key" --detach-sign --output "$signature" "$image" \
    3<<<"${HYPRFLUX_SIGNING_PASSPHRASE:-}"
gpg --batch --verify "$signature" "$image"
mv -fT -- "$signature" "${image}.asc"
echo "Verified detached release signature: ${image}.asc"
