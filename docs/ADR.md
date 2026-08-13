# Architecture Decision Records (ADRs)

Why this is shaped the way it is, including the two decisions that only exist
because a test disagreed with me.

## Three shapes fail the build and two only get printed

The five shapes are not equally knowable. For three of them I can write the
flagged line into a file, run it, and watch the script die. For the other two I
am guessing about size and intent: `${var//pattern/}` is quadratic in bash 3.2
and painful on a large string, and perfectly ordinary on a short one, and there
is nothing on the line that tells me which I am looking at.

I wanted all five to block, on the theory that a warning nobody has to act on is
a warning nobody acts on. What changed my mind is what a check like this does to
the people who have to live with it. A check that fails your build on a guess
gets waived, because it has to be, and the second and third waivers are easier to
write than the first. By the time it fires on something real, the reflex is
already trained. So the exit code is reserved for the three shapes I can
demonstrate, and the other two are printed and nothing more. That split is worth
more than the extra coverage would have been.

It is enforced by a test rather than by discipline. Feeding the tool a file whose
only finding is a WARN and asserting exit 0 is one assertion, and making WARN
increment the block counter turns it red.

## The check runs the lines it flags

A checker for shell scripts usually cannot verify its own advice, so it gets
graded against examples somebody typed out by hand, and the examples inherit
whatever the author believed. This one is in a better position. The claim is
that a flagged line kills a running script, and that is a thing you can go and
find out.

So the suite writes each flagged line into a real script with `set -euo pipefail`
at the top, runs it under `/bin/bash`, and asserts a non-zero exit and that the
line after it never printed. The pipe case exits 141, the empty array exits 1
with `unbound variable`, the empty grep exits 1 with nothing at all.

I nearly shipped that section wrong. My first pipe fixture built one 300 kilobyte
line with no newlines in it and measured exit 0, and for a few minutes I had a
test asserting the opposite of what I had claimed. The reason is that BSD grep
has to buffer a whole line before it can decide whether it matches, so it read
every byte, my producer never wrote into a closed pipe, and no signal was ever
sent. Put newlines in the data and let the match land early and the producer gets
SIGPIPE at once. The measurement was right; my fixture was not describing the
situation I had actually hit in production, where the input was a diff and diffs
have newlines in them.

That is the sort of thing an examples list would never have caught, because I
would have written the example from the same wrong memory.

## Regular expressions on one line at a time, not a shell parser

Every miss in the README's list has the same cause. The tool greps a line, and
anything that hides the shape from that grep gets through. A pipe split over two
lines with a backslash is invisible. `cat big.txt | grep -q x` is invisible,
though it fails identically to the version that is caught. `||` in a trailing
comment reads as a fallback and silences a real finding.

A shell parser would fix all of that, and it is the wrong trade for this. Shell
grammar is enormous, a parser is a dependency or several hundred more lines I
would have to test, and it moves the tool from something you can read in one
sitting and drop into a hook to something you have to install and trust. The
version that exists is a hundred lines with no dependencies, which is what makes
it reasonable to run on every commit.

What that trade costs has to be paid honestly, which means the misses go in the
README in a list, at the same volume as what it catches, and two assertions pin
them. The suite feeds the tool a file with four real defects in it that it is
known to miss and asserts that it reports nothing. If someone widens a regular
expression later, those two go red and the README gets updated in the same
change, rather than quietly becoming a lie.

## The exemptions are the fix and a written reason

Two things are skipped without a waiver. `${arr[@]+"${arr[@]}"}` is skipped
because it is the correction for the empty-array crash, and flagging the fix
would make the tool impossible to satisfy. A `$( )` assignment with `||` on the
line is skipped because the fallback is right there.

Everything else needs `# bash32-ok: <reason>` on the line, and the reason is not
for the script, which never reads it. It is for whoever reads the diff. A pipe
over a value that is genuinely one short line is safe and will still be flagged,
because the tool cannot see how large your data gets, and the right answer is a
waiver that says why and can be argued with in review rather than a rule that
tries to guess.

Both exemptions are load-bearing in the literal sense. Deleting the guard-form
exemption turns five assertions red, and neutering the waiver turns four red,
including the standing check that the bundled corpus scans clean.

## The corpus ships with the package

The version of this I ran privately ended with a standing check that scanned a
directory of my own production scripts and asserted no findings. That check was
doing real work, since it is the one that catches a regular expression getting
greedy, but it only worked on the machine where those scripts lived, and it
described a tree nobody else could see.

So the package carries six scripts of its own in `tests/fixtures/corpus`. They
are written the way the real ones are, including the empty-array guard form, a
grep with its fallback on the same line, a waived pipe over one short line, and
one legitimate `${var//pattern/}` that earns a WARN and does not block. The
standing check scans all six and asserts `0 BLOCK, 1 WARN across 6 file(s)`.

One of them doubles as the base for the positive control: the suite copies it,
appends all five shapes to the bottom, and confirms every one is found among real
code rather than only in a synthetic file where they are the only thing present.

## The oracle is skipped on newer bash, out loud

bash 4.4 fixed the empty-array crash. On a Linux runner those oracle scripts exit
0, which is correct behavior for that bash and would fail the assertion against a
tool that is working perfectly.

The suite therefore reads the version off the bash it is about to use and skips
the oracle block above 4.4. It prints a line for every skipped check with the
reason and the version it read, and it prints the count in the summary, because a
test that silently does not run is worse than one that is missing. Everything
else in the suite runs on both platforms, so the Linux leg still covers all the
detection behavior. What it does not cover is the proof that the flagged lines
abort, and that proof only comes from the macOS leg.

I checked the skip path with a stub reporting 5.2 rather than trusting that I had
written the comparison correctly: 32 passed, 0 failed, 10 skipped, every skip
named.

## What is deliberately not here

No autofix. The corrections are not mechanical. The empty-array one has a
one-line answer, but the pipe one might mean restructuring how the data is
produced, and the assignment one might mean the fallback was wrong to begin with.
A tool that rewrites those would be making a decision it is not in a position to
make.

No configuration file, no severity flags, no way to turn a mechanism off
globally. Five shapes, two tiers, one waiver that works per line and asks for a
reason. Anything more configurable becomes a thing you tune until it stops
telling you what you do not want to hear.

No scanning of test files, which is a scope decision rather than a technical one.
Two of the five shapes are about input outgrowing a buffer, and test files assert
over short fixed strings by construction, so pointing the tool at them produces
findings that are all true and all irrelevant.
