#!/usr/bin/env bash
# verify-checksums.sh - compare a manifest of hashes against what is on disk.
# Part of the test corpus. The bounded grep -q pipe here is waived, since the
# thing being piped is one short line and can never fill a pipe buffer.
set -euo pipefail

MANIFEST="${1:-checksums.txt}"
[ -f "$MANIFEST" ] || { printf 'verify-checksums: no manifest at %s\n' "$MANIFEST" >&2; exit 1; }

bad=0
total=0
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  want="${entry%% *}"
  path="${entry#* }"
  total=$((total+1))
  if [ ! -f "$path" ]; then
    printf 'missing  %s\n' "$path"
    bad=$((bad+1))
    continue
  fi
  got="$(shasum -a 256 "$path" | cut -d' ' -f1)"
  if printf '%s' "$got" | grep -q "^$want\$"; then  # bash32-ok: one 64-char line
    continue
  fi
  printf 'changed  %s\n' "$path"
  bad=$((bad+1))
done < "$MANIFEST"

printf 'verify-checksums: %d checked, %d bad\n' "$total" "$bad"
[ "$bad" -eq 0 ]
