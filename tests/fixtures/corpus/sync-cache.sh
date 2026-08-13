#!/usr/bin/env bash
# sync-cache.sh - copy a cache directory to a mirror, newest wins.
# Part of the test corpus. Text rewriting here goes through sed rather than
# ${var//pattern/}, since the input is a whole file and not a short string.
set -euo pipefail

FROM="${1:-}"
TO="${2:-}"
[ -n "$FROM" ] && [ -n "$TO" ] || { printf 'usage: sync-cache.sh <from> <to>\n' >&2; exit 64; }
[ -d "$FROM" ] || { printf 'sync-cache: no source at %s\n' "$FROM" >&2; exit 1; }

mkdir -p "$TO"

copied=0
skipped=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  src="$FROM/$rel"
  dst="$TO/$rel"
  if [ -f "$dst" ] && [ ! "$src" -nt "$dst" ]; then
    skipped=$((skipped+1))
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  cp -p "$src" "$dst"
  copied=$((copied+1))
done <<EOF
$(cd "$FROM" && find . -type f -print | sed 's|^\./||')
EOF

printf 'sync-cache: %d copied, %d already current\n' "$copied" "$skipped"
