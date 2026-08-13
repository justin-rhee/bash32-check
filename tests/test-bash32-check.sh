#!/usr/bin/env bash
# test-bash32-check.sh - offline test suite for bash32-check.sh.
#   bash tests/test-bash32-check.sh
#
# No network, no credentials, nothing installed. Everything is built inside one
# throwaway directory that is removed on exit.
#
# Two things worth knowing before reading it.
#
# The fixture lines are assembled with printf %s substitution for the word
# g r e p, so this file's own source never contains the M1 or M5 shapes. The M3
# and M4 shapes do appear literally, which is fine, because the detector is
# meant for production scripts and this is a test file.
#
# The last section is an oracle: it takes the lines the detector called BLOCK,
# runs each one as a real script, and checks that it really does abort. That
# only proves anything on bash older than 4.4. Newer bash fixed the empty-array
# crash, so on a 4.4+ runner the oracle would fail a working tool. It is skipped
# there, out loud, and the rest of the suite still runs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHK="$HERE/../src/bash32-check.sh"
CORPUS="$HERE/fixtures/corpus"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/b32.XXXXXX")"
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

PASS=0
FAIL=0
SKIP=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
skip() { SKIP=$((SKIP+1)); printf '  skip  %s (%s)\n' "$1" "$2"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want [$3] got [$2])"; fi; }
has()  { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing [$3])" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1 (unexpectedly contains [$3])" ;; *) ok "$1" ;; esac; }

echo "== fixture: all five shapes fire, the exempt ones stay dark =="
FX="$WORK/fx.sh"
{
  printf '#!/usr/bin/env bash\n'
  printf 'set -euo pipefail\n'
  printf 'big="x"; blob="y"; files=(a b); sm="ok"\n'
  printf 'printf "%%s" "$big" | %s -q needle\n' grep
  printf 'for f in "${files[@]}"; do : "$f"; done\n'
  printf 'x="$(cat f | %s pat | head -1)"\n' grep
  printf 'y="${blob//pattern/}"\n'
  printf '( step_one; step_two ) || echo fallback\n'
  printf 'printf "%%s" "$sm" | %s -q ok # bash32-ok: bounded input\n' grep
  printf 'for g in ${files[@]+"${files[@]}"}; do : "$g"; done\n'
  printf '# printf "$big" | %s -q incomment\n' grep
} > "$FX"
OUT="$(bash "$CHK" "$FX" 2>&1)"; rc=$?
check "fixture exits 1 because BLOCKs are present" "$rc" "1"
has  "M1 fires BLOCK"          "$OUT" "BLOCK M1 "
has  "M3 fires BLOCK"          "$OUT" "BLOCK M3 "
has  "M5 fires BLOCK"          "$OUT" "BLOCK M5 "
has  "M2 fires WARN"           "$OUT" "WARN M2 "
has  "M4 fires WARN"           "$OUT" "WARN M4 "
has  "findings name the file and line" "$OUT" "$FX:4:"
has  "summary is exact"        "$OUT" "bash32-check: 3 BLOCK, 2 WARN across 1 file(s)"
hasnt "waivered line stays dark"       "$OUT" "bash32-ok: bounded input"
hasnt "guard form stays dark"          "$OUT" '[@]+'
hasnt "whole-line comment stays dark"  "$OUT" "incomment"

echo "== clean and warn-only files =="
CLEAN="$WORK/clean.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'v="ok"\nprintf "%%s\\n" "$v"\n'
} > "$CLEAN"
COUT="$(bash "$CHK" "$CLEAN" 2>&1)"; rc=$?
check "clean file exits 0" "$rc" "0"
has   "clean summary"      "$COUT" "bash32-check: 0 BLOCK, 0 WARN across 1 file(s)"

WONLY="$WORK/warnonly.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\nblob="y"\n'
  printf 'y="${blob//pattern/}"\n'
} > "$WONLY"
WOUT="$(bash "$CHK" "$WONLY" 2>&1)"; rc=$?
check "warn-only file exits 0, a WARN never blocks" "$rc" "0"
has   "warn-only summary" "$WOUT" "bash32-check: 0 BLOCK, 1 WARN across 1 file(s)"

echo "== arguments =="
bash "$CHK" >/dev/null 2>&1; rc=$?
check "no arguments exits 64" "$rc" "64"
MOUT="$(bash "$CHK" "$WORK/nope.sh" "$CLEAN" 2>&1)"; rc=$?
check "a missing path is skipped, the rest still scan" "$rc" "0"
has   "the skip is reported"  "$MOUT" "not a file, skipped"
has   "the real file counted" "$MOUT" "across 1 file(s)"

echo "== known misses stay missed, so the README stays true =="
MISS="$WORK/misses.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'cat big.txt | %s -q needle\n' grep
  printf 'printf "%%s" "$big" \\\n'
  printf '  | %s -q needle\n' grep
  printf 'for f in ${files[@]}; do : "$f"; done\n'
  printf 'x="$(%s pat file)" # a fallback goes here later || not yet\n' grep
} > "$MISS"
XOUT="$(bash "$CHK" "$MISS" 2>&1)"; rc=$?
check "four real defects, none of them caught" "$rc" "0"
has   "and the summary says so" "$XOUT" "bash32-check: 0 BLOCK, 0 WARN across 1 file(s)"

echo "== positive control: five shapes planted into a working script =="
PLANT="$WORK/planted.sh"
cp "$CORPUS/wait-for-file.sh" "$PLANT"
{
  printf 'planted_big="x"; planted_files=(a b); planted_blob="y"\n'
  printf 'printf "%%s" "$planted_big" | %s -q needle\n' grep
  printf 'for pf in "${planted_files[@]}"; do : "$pf"; done\n'
  printf 'px="$(cat f | %s pat | head -1)"\n' grep
  printf 'py="${planted_blob//pattern/}"\n'
  printf '( planted_one; planted_two ) || echo fallback\n'
} >> "$PLANT"
POUT="$(bash "$CHK" "$PLANT" 2>&1)"; rc=$?
check "planted script exits 1" "$rc" "1"
has "M1 found among real code" "$POUT" "BLOCK M1 "
has "M3 found among real code" "$POUT" "BLOCK M3 "
has "M5 found among real code" "$POUT" "BLOCK M5 "
has "M2 found among real code" "$POUT" "WARN M2 "
has "M4 found among real code" "$POUT" "WARN M4 "

echo "== standing invariant: the bundled corpus scans clean =="
TOUT="$(bash "$CHK" "$CORPUS"/*.sh 2>&1)"; rc=$?
check "six working scripts, no BLOCK findings" "$rc" "0"
has   "one legitimate WARN rides along without blocking" "$TOUT" "0 BLOCK, 1 WARN across 6 file(s)"

echo "== oracle: every BLOCK line really does abort =="
# bash 4.4 fixed the empty-array crash that M3 is about, so on a newer bash the
# oracle scripts below would pass and the assertions would fail on a detector
# that is working correctly. Read the version off the bash that will run them.
ORACLE_BASH="/bin/bash"
[ -x "$ORACLE_BASH" ] || ORACLE_BASH="$(command -v bash)"
OB_VER="$("$ORACLE_BASH" -c 'printf "%s.%s" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"')"
OB_MAJOR="${OB_VER%%.*}"
OB_MINOR="${OB_VER#*.}"
ORACLE_APPLIES=0
if [ "$OB_MAJOR" -lt 4 ]; then
  ORACLE_APPLIES=1
elif [ "$OB_MAJOR" -eq 4 ] && [ "$OB_MINOR" -lt 4 ]; then
  ORACLE_APPLIES=1
fi
ORACLE_WHY="$ORACLE_BASH is $OB_VER, which fixed these; the oracle only means something below 4.4"

# run_oracle <name> <script-path> <want-zero|want-nonzero>
run_oracle() {
  local name="$1" path="$2" want="$3" out rc2
  out="$("$ORACLE_BASH" "$path" 2>&1)"; rc2=$?
  if [ "$want" = "want-nonzero" ]; then
    if [ "$rc2" -ne 0 ]; then ok "$name (exit $rc2)"; else bad "$name (exit 0, it did not abort)"; fi
  else
    if [ "$rc2" -eq 0 ]; then ok "$name (exit 0)"; else bad "$name (exit $rc2, expected clean)"; fi
  fi
  ORACLE_OUT="$out"
}

M1O="$WORK/oracle-m1.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'big="needle\n'
  printf '$(seq 1 40000)"\n'
  printf 'printf "%%s" "$big" | %s -q needle\n' grep
  printf 'echo REACHED\n'
} > "$M1O"
M3O="$WORK/oracle-m3.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'files=()\n'
  printf 'for f in "${files[@]}"; do : "$f"; done\n'
  printf 'echo REACHED\n'
} > "$M3O"
M5O="$WORK/oracle-m5.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'cd "$(dirname "$0")"\n'
  printf 'printf "%%s\\n" alpha beta > data.txt\n'
  printf 'x="$(cat data.txt | %s zzz | head -1)"\n' grep
  printf 'echo REACHED\n'
} > "$M5O"
GUARDO="$WORK/oracle-guard.sh"
{
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  printf 'files=()\n'
  printf 'for f in ${files[@]+"${files[@]}"}; do : "$f"; done\n'
  printf 'echo REACHED\n'
} > "$GUARDO"

# Every oracle script is a line the detector flags, so the detector must agree.
OOUT="$(bash "$CHK" "$M1O" "$M3O" "$M5O" 2>&1)"; rc=$?
check "the detector blocks all three oracle scripts" "$rc" "1"
has   "three BLOCKs, nothing else" "$OOUT" "bash32-check: 3 BLOCK, 0 WARN across 3 file(s)"
GOUT="$(bash "$CHK" "$GUARDO" 2>&1)"; rc=$?
check "the detector passes the guard-form script" "$rc" "0"

if [ "$ORACLE_APPLIES" -eq 1 ]; then
  run_oracle "M1: the pipe aborts even though grep matched" "$M1O" want-nonzero
  hasnt "M1: the next line never ran" "$ORACLE_OUT" "REACHED"
  run_oracle "M3: the empty array aborts" "$M3O" want-nonzero
  has   "M3: and says why" "$ORACLE_OUT" "unbound variable"
  run_oracle "M5: the empty grep aborts" "$M5O" want-nonzero
  hasnt "M5: it aborts with nothing printed" "$ORACLE_OUT" "REACHED"
  run_oracle "the guard form runs clean" "$GUARDO" want-zero
  has   "the guard form reached the end" "$ORACLE_OUT" "REACHED"
  WORACLE="$WORK/oracle-warn.sh"
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\nblob="a-b-c"\n'
    printf 'y="${blob//-/_}"\n'
    printf 'echo REACHED\n'
  } > "$WORACLE"
  run_oracle "a WARN-only script runs clean" "$WORACLE" want-zero
  has "the WARN-only script reached the end" "$ORACLE_OUT" "REACHED"
else
  skip "M1: the pipe aborts even though grep matched" "$ORACLE_WHY"
  skip "M1: the next line never ran"                  "$ORACLE_WHY"
  skip "M3: the empty array aborts"                   "$ORACLE_WHY"
  skip "M3: and says why"                             "$ORACLE_WHY"
  skip "M5: the empty grep aborts"                    "$ORACLE_WHY"
  skip "M5: it aborts with nothing printed"           "$ORACLE_WHY"
  skip "the guard form runs clean"                    "$ORACLE_WHY"
  skip "the guard form reached the end"               "$ORACLE_WHY"
  skip "a WARN-only script runs clean"                "$ORACLE_WHY"
  skip "the WARN-only script reached the end"         "$ORACLE_WHY"
fi

echo
echo "======================================"
printf 'oracle bash: %s (%s)\n' "$ORACLE_BASH" "$OB_VER"
[ "$SKIP" -eq 0 ] || printf 'skipped: %d (%s)\n' "$SKIP" "$ORACLE_WHY"
printf 'RESULT: %d passed, %d failed\n' "$PASS" "$FAIL"
echo "======================================"
[ "$FAIL" -eq 0 ]
