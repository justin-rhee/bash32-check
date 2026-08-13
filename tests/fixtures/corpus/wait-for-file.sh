#!/usr/bin/env bash
# wait-for-file.sh - block until a path appears, or give up.
# Part of the test corpus. Written the way a real polling script gets written,
# and it scans clean, which is the point of it being here.
set -euo pipefail

TARGET="${1:-}"
TIMEOUT="${2:-60}"
[ -n "$TARGET" ] || { printf 'usage: wait-for-file.sh <path> [timeout-seconds]\n' >&2; exit 64; }

waited=0
while [ ! -e "$TARGET" ]; do
  if [ "$waited" -ge "$TIMEOUT" ]; then
    printf 'wait-for-file: gave up on %s after %ss\n' "$TARGET" "$TIMEOUT" >&2
    exit 1
  fi
  sleep 1
  waited=$((waited+1))
done

# The grep can legitimately find nothing, so it gets a fallback on the same line.
first_line="$(head -1 "$TARGET" || true)"
kind="$(grep -c . "$TARGET" 2>/dev/null || echo 0)"

printf 'wait-for-file: %s appeared after %ss (%s lines)\n' "$TARGET" "$waited" "$kind"
[ -z "$first_line" ] || printf '  first: %s\n' "$first_line"
