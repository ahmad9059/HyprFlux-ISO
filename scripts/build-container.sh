#!/bin/bash
# Isolated Arch build tools: does not upgrade/install packages on the host.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cache_source=""
case "${1:-}" in
    '') ;;
    --with-package-cache) cache_source=/var/cache/pacman/pkg; shift ;;
    *) echo 'Usage: bash scripts/build-container.sh [--with-package-cache]' >&2; exit 2 ;;
esac
[[ $# == 0 ]] || { echo 'Unexpected build arguments.' >&2; exit 2; }
command -v docker >/dev/null || { echo 'Docker is required.' >&2; exit 1; }
# Use stdin so multi-gigabyte work/out directories are never sent as context.
docker build --pull -t hyprflux-iso-builder - < "$ROOT/tests/Dockerfile.builder"
docker run --rm --privileged \
    -e "HYPRFLUX_PACKAGE_CACHE=$cache_source" \
    -e "HYPRFLUX_CACHE_LIMIT_MIB=${HYPRFLUX_CACHE_LIMIT_MIB:-2048}" \
    -v "$ROOT:/project" \
    -v hyprflux-pacman-cache:/var/cache/pacman/pkg \
    hyprflux-iso-builder bash -c \
    'python -m unittest discover -s tests -v && bash build.sh' </dev/null
