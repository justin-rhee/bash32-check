#!/usr/bin/env bash
# render-report.sh - turn a run directory into a plain-text summary.
# Part of the test corpus. Builds its argument list as an array and expands it
# with the guard form, because a run with no sections is allowed. The one
# ${var//pattern/} in here is a legitimate use on a one-word string, so it
# earns a WARN and the corpus still scans clean.
set -euo pipefail

RUN_DIR="${1:-}"
[ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ] || { printf 'usage: render-report.sh <run-dir>\n' >&2; exit 64; }

sections=()
for candidate in summary timings failures notes; do
  [ -f "$RUN_DIR/$candidate.txt" ] || continue
  sections[${#sections[@]}]="$RUN_DIR/$candidate.txt"
done

printf 'report for %s\n' "$RUN_DIR"
printf '%s\n' '----------------------------------------'

if [ "${#sections[@]}" -eq 0 ]; then
  printf '(no sections found)\n'
  exit 0
fi

for section in ${sections[@]+"${sections[@]}"}; do
  title="$(basename "$section" .txt)"
  title="${title//_/ }"
  printf '\n[%s]\n' "$title"
  sed 's/^/  /' "$section"
done
