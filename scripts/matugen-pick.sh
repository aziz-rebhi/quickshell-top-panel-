#!/usr/bin/env bash
# Usage: matugen-pick.sh <wallpaper-path>
# Extracts candidate source colors from a wallpaper using matugen.
# Runs matugen for each source color index (0-3) in parallel.
# Outputs JSON to stdout with the candidate colors.
set -euo pipefail

WALL="$1"
[ -n "$WALL" ] && [ -f "$WALL" ] || { echo '{"error":"file not found"}' >&2; exit 1; }

export PATH="$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

if ! command -v matugen &>/dev/null; then
  echo '{"error":"matugen not found"}'
  exit 1
fi

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Run matugen for each source color index in parallel
for i in 0 1 2 3; do
  (
    matugen image "$WALL" -j hex --source-color-index "$i" -m dark --type scheme-fidelity --dry-run 2>/dev/null \
      | python3 -c "
import sys, json
try:
  data = json.load(sys.stdin)
  sc = data.get('colors', {}).get('source_color', {}).get('default', {}).get('color', '')
  if sc:
    print(sc)
except:
  pass
" 2>/dev/null > "$TMPDIR/$i.txt"
  ) &
done

wait

# Collect non-empty results in order
COLORS='[]'
for i in 0 1 2 3; do
  if [ -s "$TMPDIR/$i.txt" ]; then
    hex=$(tr -d ' \n\r' < "$TMPDIR/$i.txt")
    if printf '%s' "$hex" | grep -qE '^#[a-fA-F0-9]{6}$'; then
      if [ "$COLORS" = '[]' ]; then
        COLORS="[\"$hex\""
      else
        COLORS="$COLORS,\"$hex\""
      fi
    fi
  fi
done

if [ "$COLORS" != '[]' ]; then
  COLORS="$COLORS]"
fi

echo "$COLORS"
