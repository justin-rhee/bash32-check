# Security policy: bash32-check

## Posture

bash32-check is provided as-is, with no warranty (see LICENSE). It is a
correctness tool for shell scripts, not a security boundary. Use it as one check
among several, never as a sole guarantee.

It only reads. It opens the files you name, greps each line, prints findings, and
exits. It never edits a file, never executes the script you point it at, and
makes no network calls.

The honest ceiling: a clean result means none of five specific shapes matched on
any single line, and nothing more than that. The check is a regular expression
run line by line, so a real defect that is split across two lines, or written
with `cat` instead of `printf`, or unquoted, is not reported. The README lists
the misses I know about, and the test suite pins them so the list stays true. If
you need coverage of shell defects in general, run shellcheck as well.

Two things worth knowing before you wire it into a gate:

The WARN tier never affects the exit code, by design. A file with WARN findings
and no BLOCK findings exits 0 and will pass your gate.

The `# bash32-ok:` waiver is a comment. Anyone who can edit a script can silence
a finding on any line of it, and nothing here verifies the reason. It is a review
aid, not a control.

## Validation status

The offline suite in `tests/test-bash32-check.sh` has been run: 42 checks, all
passing, on macOS with `/bin/bash` reporting
`GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)`.

Ten of those checks are an oracle that runs each flagged line as a real script
and asserts it aborts. bash 4.4 fixed one of the three blocking defects, so on a
newer bash those ten are skipped with the reason printed. The Linux leg of the CI
matrix therefore proves the detection behavior and not the abort behavior. The
matrix prints each runner's bash version in its own step, so any platform claim
here can be checked against the log.

The tool was also broken deliberately three times to confirm the suite notices:
removing the empty-array guard exemption, neutering the waiver, and counting WARN
findings as blocking. All three turn assertions red, and the receipts are in the
README.

There is no fuzzing corpus and no adversarial corpus. The threat model is my own
scripts and my own mistakes, not a hostile author, and a hostile author defeats
this trivially by writing the same defect on two lines.

## Reporting a problem

Report privately through this repository's Security tab, using GitHub's
"Report a vulnerability" flow, or by opening a minimal issue that describes the
impact without a working exploit. Please give a reasonable window for a fix
before publishing details.

For a false negative or a false positive, which is what most reports here will
be, a normal issue with the exact line is the fastest path.
