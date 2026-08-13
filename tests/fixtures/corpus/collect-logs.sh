#!/usr/bin/env bash
# collect-logs.sh - gather log files into one bundle.
# Part of the test corpus. Uses the empty-array guard form on purpose, because
# a run that matches nothing is the normal case here.
set -euo pipefail

SRC="${1:-.}"
OUT="${2:-bundle.log}"

logs=()
while IFS= read -r path; do
  logs[${#logs[@]}]="$path"
done <<EOF
$(find "$SRC" -maxdepth 2 -name '*.log' 2>/dev/null || true)
EOF

: > "$OUT"
for log in ${logs[@]+"${logs[@]}"}; do
  printf '===== %s =====\n' "$log" >> "$OUT"
  cat "$log" >> "$OUT"
done

printf 'collect-logs: %d file(s) into %s\n' "${#logs[@]}" "$OUT"
