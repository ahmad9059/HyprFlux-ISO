#!/bin/bash
# Isolated Arch build tools: does not upgrade/install packages on the host.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v docker >/dev/null || { echo 'Docker is required.' >&2; exit 1; }
# Use stdin so multi-gigabyte work/out directories are never sent as context.
docker build --pull -t hyprflux-iso-builder - < "$ROOT/tests/Dockerfile.builder"
docker run --rm --privileged \
    -v "$ROOT:/project" \
    -v hyprflux-pacman-cache:/var/cache/pacman/pkg \
    hyprflux-iso-builder bash -c \
    'python -m unittest discover -s tests -v && bash build.sh' </dev/null
