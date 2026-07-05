#!/usr/bin/env bash
# Usage: wallpaper.sh [--set-only] <path>
# Sets wallpaper, generates Matugen palette (writes directly to config targets).
# Matugen's config.toml handles output paths and qs reload.
set -euo pipefail

SET_ONLY=false
if [ "${1:-}" = "--set-only" ]; then
  SET_ONLY=true
  shift
fi

WALL="$1"
[ -n "$WALL" ] && [ -f "$WALL" ] || { echo "wallpaper.sh: file not found: $WALL" >&2; exit 1; }

export PATH="$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if command -v awww &>/dev/null; then
  awww img "$WALL"
elif command -v feh &>/dev/null; then
  feh --bg-fill "$WALL"
fi

if ! command -v matugen &>/dev/null; then exit 0; fi
if [ "$SET_ONLY" = true ]; then exit 0; fi

matugen image "$WALL" -m dark --prefer darkness --type scheme-fidelity -c "$HOME/.config/matugen/config.toml" 2>/dev/null || true
