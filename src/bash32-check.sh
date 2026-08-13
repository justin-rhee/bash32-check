#!/usr/bin/env bash
# bash32-check.sh - a line-based detector for the handful of shell shapes that
# behave differently under bash 3.2 with `set -euo pipefail` than they do under
# bash 4+. It is not a shell linter. It looks for five specific shapes, three of
# which abort a running script on bash 3.2 and are reported as BLOCK.
#
# Usage: bash32-check.sh <file.sh> [<file.sh>...]
# Exit:  0 no BLOCK findings (WARNs allowed) | 1 any BLOCK finding | 64 usage
#
# The five shapes, numbered in the order I hit them:
#
#   BLOCK, each one proven to abort a real script:
#     M1  a variable piped into `grep -q`. Once the producer has more than the
#         pipe buffer to write and grep matches early, grep exits, the producer
#         takes SIGPIPE, and pipefail turns that into a failed pipeline even
#         though the match succeeded.
#     M3  an unguarded "${arr[@]}" on an empty array. Under `set -u` bash 3.2
#         treats that as an unbound variable and exits. bash 4.4 fixed it. The
#         guard form ${arr[@]+"${arr[@]}"} is exempt because it is the fix.
#     M5  a variable assigned from a $(...) that contains grep, with no ||
#         fallback on the line. When grep finds nothing the assignment fails,
#         set -e exits, and any fallback written on a later line never runs.
#
#   WARN, real shapes with legitimate uses, never blocks:
#     M2  ${var//pattern/} global substitution, which is quadratic in bash 3.2
#         and takes over a minute on inputs that are instant in bash 4.
#     M4  a multi-command ( cmd1; cmd2 ) || compound. set -e does not apply
#         inside the subshell, so a failure partway through is swallowed.
#
# WARN never affects the exit code. A check that blocks on a heuristic gets
# waived everywhere within a week, and then the BLOCK findings get waived too
# because that is the habit people have learned.
#
# Waiver: any finding line carrying `# bash32-ok: <reason>` is skipped. The
# reason is for whoever reads the diff, not for this script. Whole-line comments
# are skipped without a waiver.
#
# Scope: point it at production scripts. Test files assert over small fixed
# strings by construction, so M1 and M2, which are both about input size, fire
# on them constantly and mean nothing.
set -euo pipefail

[ $# -ge 1 ] || { printf 'usage: bash32-check.sh <file.sh> [<file.sh>...]\n' >&2; exit 64; }

M1_RE='(printf|echo)[^|]*\$[^|]*\|[[:space:]]*grep[[:space:]].*-[A-Za-z]*q'  # bash32-ok: regex literal, not code
M3_RE='"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"'                                  # bash32-ok: regex literal, not code
M5_RE='=[[:space:]]*"?\$\([^)]*grep'                                         # bash32-ok: regex literal, not code
M2_RE='\$\{[A-Za-z_][A-Za-z0-9_]*//'                                         # bash32-ok: regex literal, not code
M4_RE='\([^()]*;[^()]*\)[[:space:]]*\|\|'                                    # bash32-ok: regex literal, not code

BLOCKS=0
WARNS=0
FILES=0

# scan_one <file> <mech-id> <tier> <regex>
scan_one() {
  file="$1"; mech="$2"; tier="$3"; re="$4"
  hits="$(grep -nE "$re" "$file" || true)"
  [ -n "$hits" ] || return 0
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    lineno="${hit%%:*}"
    content="${hit#*:}"
    # trim leading whitespace, then skip whole-line comments
    t="${content#"${content%%[![:space:]]*}"}"
    case "$t" in '#'*) continue ;; esac
    # inline waiver
    case "$content" in *"bash32-ok:"*) continue ;; esac
    # per-mechanism exemptions
    case "$mech" in
      M3) case "$content" in *'[@]+'*) continue ;; esac ;;   # guard form present
      M5) case "$content" in *'||'*) continue ;; esac ;;     # fallback present
    esac
    printf '%s %s %s:%s: %s\n' "$tier" "$mech" "$file" "$lineno" "$t"
    if [ "$tier" = "BLOCK" ]; then BLOCKS=$((BLOCKS+1)); else WARNS=$((WARNS+1)); fi
  done <<EOF
$hits
EOF
  return 0
}

for f in "$@"; do
  if [ ! -f "$f" ]; then
    printf 'bash32-check: not a file, skipped: %s\n' "$f" >&2
    continue
  fi
  FILES=$((FILES+1))
  scan_one "$f" M1 BLOCK "$M1_RE"
  scan_one "$f" M3 BLOCK "$M3_RE"
  scan_one "$f" M5 BLOCK "$M5_RE"
  scan_one "$f" M2 WARN  "$M2_RE"
  scan_one "$f" M4 WARN  "$M4_RE"
done

printf 'bash32-check: %d BLOCK, %d WARN across %d file(s)\n' "$BLOCKS" "$WARNS" "$FILES"
[ "$BLOCKS" -eq 0 ]
