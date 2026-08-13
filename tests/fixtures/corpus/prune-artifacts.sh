#!/usr/bin/env bash
# prune-artifacts.sh - delete build output older than a cutoff.
# Part of the test corpus. Every grep that can come up empty carries its
# fallback on the same line, which is what keeps this file clean.
set -euo pipefail

ROOT="${1:-build}"
DAYS="${2:-14}"

[ -d "$ROOT" ] || { printf 'prune-artifacts: nothing at %s\n' "$ROOT"; exit 0; }

keep_list="${ROOT}/.keep"
protected="$(grep -v '^#' "$keep_list" 2>/dev/null || true)"

removed=0
while IFS= read -r victim; do
  [ -n "$victim" ] || continue
  case "$protected" in
    *"$victim"*) continue ;;
  esac
  rm -rf "$victim"
  removed=$((removed+1))
done <<EOF
$(find "$ROOT" -mindepth 1 -maxdepth 1 -mtime "+$DAYS" 2>/dev/null || true)
EOF

printf 'prune-artifacts: removed %d entr(ies) under %s\n' "$removed" "$ROOT"
