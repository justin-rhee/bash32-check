# bash32-check

[![tests](https://github.com/justin-rhee/bash32-check/actions/workflows/test.yml/badge.svg)](https://github.com/justin-rhee/bash32-check/actions/workflows/test.yml)

I lost an afternoon to five scripts that had all passed their tests and all quit
halfway through their work without a word.

The one that took longest to find was `printf '%s' "$diff" | grep -q "$pattern"`,
a line that had worked for months. Then a big commit came through and the script
just stopped there. Exit 141, nothing printed, the next twenty lines never ran.
What happened is that grep found its match on the first line and exited, my
printf still had two hundred kilobytes to push into a pipe nobody was reading any
more, and it took SIGPIPE. `set -o pipefail` calls that a failed pipeline,
`set -e` exits, and the match having actually succeeded changes nothing. It only
breaks once the data outgrows the pipe buffer, which is why every test I'd
written passed.

macOS still ships bash 3.2 from 2007 as `/bin/bash`, so if your scripts run
`set -euo pipefail` anywhere near a Mac, you have some of this. This is about a
hundred lines of bash that reads a script and blocks only the lines it can prove
will kill it partway through.

## Use it if

- your scripts run `set -euo pipefail` and some of them have to work on a Mac
- something of yours has died mid-run with no output and no explanation
- your tests pass on short fixture data and production data isn't short

## How it works

Point it at files and it greps each line for five shapes. Three get BLOCK and set
the exit code to 1. Two get WARN and never touch the exit code at all

The three that block:

- a variable piped into `grep -q`, which is the SIGPIPE story above
- an unguarded `"${arr[@]}"`, which bash 3.2 calls an unbound variable when the array is empty and `set -u` is on
- a variable assigned from a `$( )` containing grep with no `||` fallback on the same line, which exits before your fallback runs

The two that warn:

- `${var//pattern/}`, which is quadratic in bash 3.2 and takes over a minute on input that's instant in bash 4
- a multi-command `( cmd1; cmd2 ) || fallback`, where `set -e` doesn't apply inside the parentheses and a failure partway through is swallowed

The split is deliberate. A check that fails your build on a guess gets waived,
and once waiving is a habit the real findings get waived the same way, unread.
So the three BLOCK shapes each have a test that runs the flagged line as a real
script and confirms it aborts, while the two WARN shapes are judgement calls
about size and intent and get reported and nothing else.

Only one of the three blocking shapes is really a bash 3.2 bug: the empty-array
crash, fixed in 4.4. The other two abort on bash 5 as well. The name is where I
found them, not where they live.

A line carrying `# bash32-ok: <reason>` is skipped. Whole-line comments are
skipped without needing one.

Here is a hook I wrote that has three of the five in it:

```
$ bash src/bash32-check.sh pre-commit.sh
BLOCK M1 pre-commit.sh:8: printf "%s" "$diff" | grep -q "TODO"
BLOCK M3 pre-commit.sh:9: for f in "${files[@]}"; do echo "checking $f"; done
BLOCK M5 pre-commit.sh:10: branch="$(git branch | grep "\*" | cut -c3-)"
WARN M2 pre-commit.sh:11: slug="${branch//\//-}"
bash32-check: 3 BLOCK, 1 WARN across 1 file(s)
$ echo $?
1
```

The M numbers are just the order I hit them in.

## Try it before you install it

Nothing to install and nothing to configure. Clone it and point it at your own
scripts.

```
git clone https://github.com/justin-rhee/bash32-check.git
bash bash32-check/src/bash32-check.sh ~/bin/*.sh
```

It only reads. It never edits a file, and it never runs the script you give it.

## Install

Copy one file onto your machine and make it executable.

```
curl -fsSL -o /usr/local/bin/bash32-check \
  https://raw.githubusercontent.com/justin-rhee/bash32-check/main/src/bash32-check.sh
chmod +x /usr/local/bin/bash32-check
```

To confirm it arrived working rather than just arrived, run it against the corpus
that ships with the repo. Six scripts, one of them carrying a legitimate WARN, and
the exit code should be 0.

```
$ bash32-check tests/fixtures/corpus/*.sh
WARN M2 tests/fixtures/corpus/render-report.sh:28: title="${title//_/ }"
bash32-check: 0 BLOCK, 1 WARN across 6 file(s)
$ echo $?
0
```

In CI or a pre-commit hook, give it your production scripts and let the exit code
decide.

```
bash32-check scripts/*.sh || exit 1
```

Point it at production scripts, not at test files. Two of the five shapes are
about input outgrowing a buffer, and test files assert over short fixed strings
by construction, so they fire constantly there and mean nothing.

## What it won't do

It's not a shell linter. It looks for five shapes and ignores everything else, so
it will happily pass an unquoted variable, a missing `local`, or any of the
hundreds of things shellcheck catches. Run both.

The misses are all the same kind: it reads one line at a time with a regular
expression, so anything hiding the shape from that expression gets through.

- `cat big.txt | grep -q needle`, because the pipe check needs a `printf` or `echo` producing a variable, though a `cat` of a large file fails identically
- a pipe split across lines with a backslash, since nothing here looks at more than one line
- unquoted `${arr[@]}`, which crashes the same way on an empty array as the quoted form it does catch
- `||` anywhere on the line read as a fallback, including inside a trailing comment
- a `$( )` nested inside another before the grep, which cost me a red test while writing the oracle

It also fires when it shouldn't. A `printf | grep -q` over a value you know is
one short line is safe and still reports BLOCK, because the check can't see how
big your data gets. That's what `# bash32-ok:` is for, and it asks for a written
reason so somebody reading the diff can disagree with you.

The WARN pair are heuristics on purpose. `${var//pattern/}` on a short string is
fine, and plenty of `( a; b ) ||` compounds are written knowing exactly what
`set -e` does inside them.

It doesn't fix anything, it prints lines and an exit code. Windows is untested,
and I don't have a way to test a Windows equivalent properly.

## How I tested it

42 checks, offline, in one throwaway directory: `bash tests/test-bash32-check.sh`.

Most linters get graded against examples somebody wrote by hand. This one
doesn't have to, because the claim is that a flagged line kills a script, and
that's testable. The suite writes each flagged line into a real script, runs it
under `/bin/bash` with `set -euo pipefail`, and checks it aborts.

```
ok  M1: the pipe aborts even though grep matched (exit 141)
ok  M3: the empty array aborts (exit 1), and says why
ok  M5: the empty grep aborts (exit 1) with nothing printed
ok  the guard form runs clean and reaches the end (exit 0)
```

M1 and M5 abort with nothing at all, which is why they took an afternoon to
find. Getting M1 measured right took two attempts: my first fixture piped a
single 300KB line and got exit 0, because BSD grep buffers a whole line before
matching, so it read everything and my producer never hit a closed pipe. With
newlines in the data and the match early, the producer takes SIGPIPE. I'd have
shipped a false negative dressed as a passing test if I'd stopped at the first
run.

The oracle can't run everywhere. bash 4.4 fixed the empty-array crash, so on
Linux those scripts exit 0 and the assertions would go red against a tool
that's working perfectly. The suite reads the version it's about to use, skips
that block above 4.4, and names every skip rather than dropping it quietly.
Checked with a stub reporting 5.2: 32 passed, 10 skipped, all named. The CI
matrix prints each runner's bash version, so the platform claim is checkable
against the log rather than against my word.

Then a mutation pass, because a test that can't fail proves nothing. Deleting
the guard-form exemption turns 42 passing into 37 and 5 failing. Neutering the
inline waiver gives 38 and 4. Counting a WARN as a BLOCK gives 37 and 5. All
three restored, back to 42 passed.

Two more checks keep this README honest: they feed the tool a file carrying four
defects it's known to miss and assert it stays quiet, so the day somebody widens
a regular expression, the suite says the "What it won't do" list is now wrong.

## License

MIT, see [LICENSE](LICENSE). No warranty. Security posture and how to report a
problem: [SECURITY.md](SECURITY.md).

Design decisions and what changed while building it: [docs/ADR.md](docs/ADR.md).

This little tool is one of a handful I pulled out of my own day-to-day agent setup. I use them all myself, so when something breaks I usually notice fast. But if you run into any issues, or anything that looks off, open an issue. I read every one. More tools on my [GitHub profile](https://github.com/justin-rhee).
