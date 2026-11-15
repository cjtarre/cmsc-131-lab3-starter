<!--no-pdf-->
# CMSC 131 Lab 3 Starter

[![lab3-checks](https://github.com/WhiteLicorice/cmsc-131-lab3-starter/actions/workflows/test.yml/badge.svg)](https://github.com/WhiteLicorice/cmsc-131-lab3-starter/actions/workflows/test.yml)

A grep clone whose correctness is agreement with `grep` itself, byte for byte. The manual is the assignment. This file is the repository's own notes.

## Layout

```text
Makefile            platform preamble and build rules
driver.c            provided: file reading, the line loop, and output
cdecl.h             provided: the cdecl macros for the C boundary
args.asm            yours
match.asm           yours
lines.asm           yours
fmt.asm             yours
run_tests.sh        provided: the correctness gate
contract_test.c     provided: the second pass, in C
contract_regs.asm   provided: register checks for contract_test
LICENSE             provided: the repository licence
tests/              provided: the test corpus
```

## What to Run

On Windows, run these commands in Git Bash, the shell from Block 1. In that
shell, `make` is your alias for `mingw32-make`. On Linux, use
your terminal.

```bash
make
make check
```

`make` builds `rengrep` and `contract_test`. `make check` builds both, then
runs `./run_tests.sh`, which reports each test and exits nonzero when any
of them differ.

The first `make check` takes the longest, often more than a minute on
Windows. It saves the output of your installed `grep` in `.grep-cache`, and
later runs read that saved output. A change to your `grep`, `run_tests.sh`,
or a test file makes the next run save the output again.

The gate has two passes. The first runs your tool and `grep` with the same
arguments and compares the two outputs byte for byte. It does that across
all 32 flag subsets, 7 patterns, and 6 files: 1344 comparisons. The second
is `contract_test`. It calls the four routines directly. It checks the
capacity argument, the boundary rules, the formatter, the parser, and the
register discipline. Both passes run every time, because each one catches
what the other cannot.

## Reading a First Run

The assembly files ship as stubs that assemble and link as-is, so the build
works before you write any code. Right now the parser stub exits 2 for
every command. The gate requires exit 0 for a valid invocation, so all
1345 checks fail. That red run is the correct starting state for a starter.
Expect the first passing cells once `args.asm` and `lines.asm` are in
place, and the badge turns green when the matching and formatting routines
are done.

The provided files are fixtures. The grader compares your fork against the
starter. An edit to `driver.c`, `Makefile`, `run_tests.sh`, or a `tests/`
file appears as a diff in the open.

## Documentation

The three sections at the end of this file are yours. Complete Design Notes
and Subsystem Ownership before the Week 1 progress report. Complete Quirks
and Issues before the Week 3 progress report. Each section says what it
needs. Leave the rest of this file as it is.

---

## Design Notes

<!--
Complete this section before the Week 1 progress report. The syllabus asks
for problem analysis, a solution architecture, and an estimated timeline.
Keep each part short. Update it when the plan changes.
-->

### Problem analysis

<!--
The five flags and what each one does. What the oracle is, and what
agreement with it means for a line that matches inside a longer word.
-->

`rengrep` searches a text file for a literal pattern. We use
`LC_ALL=C grep -F` as the oracle and compare its output with ours byte for
byte. By default, `cat` matches `concatenate` because it occurs as a
substring. With `-w`, that occurrence fails the word-boundary check.

| Flag | Behavior |
| --- | --- |
| `-n` | Prefix each selected line with its 1-based line number and a colon. |
| `-c` | Print only the count of selected lines. Takes priority over `-n`. |
| `-v` | Select lines that do not match. With `-c`, count those lines. |
| `-i` | Ignore ASCII case during matching and keep the original text for output. |
| `-w` | Require a line edge or a non-word byte on each side of a match. Letters, digits, and `_` are word bytes. |

### Solution architecture

<!--
How the four routines split the work. How the line index is built from
one buffer, how the flag table dispatches, and which registers each
routine uses.
-->

The C driver calls `parse_args`, reads the file into one buffer, and calls
`index_lines` to record where each line starts and how long it is. It then
uses `line_matches` to check each line and `int_to_dec` to format any
line numbers or counts.

| Routine | Plan | Planned register use |
| --- | --- | --- |
| `parse_args` (`args.asm`) | Walk `argv` to find the pattern and file path. For grouped flags like `-nvi`, scan `ncviw` with `repne scasb`. Set each flag bit from its position in the table. | `AL` holds the flag byte, `EDI` points into the table, and `ECX` counts the remaining bytes. |
| `index_lines` (`lines.asm`) | Scan the buffer for newline bytes. Record each start offset and length without the newline. Include a final line without a newline, return zero entries for an empty file, and stop at the output capacity. | `ESI` walks the input buffer and `EDI` points to the next output entry. |
| `line_matches` (`match.asm`) | Handle empty and oversized patterns first. Check candidate offsets from `0` through `linelen - patlen`. Use `repe cmpsb` for exact comparisons and fold ASCII bytes in registers for `-i`. Keep searching if a candidate fails the `-w` check. | `ESI` and `EDI` point to the bytes being compared, and `ECX` counts the bytes for `cmpsb`. |
| `int_to_dec` (`fmt.asm`) | Divide by 10 and push each digit onto the stack. Pop the digits into the output buffer in display order. Write one digit for zero and return the digit count. | `EAX` holds the quotient, `EDX` holds the remainder, and `EDI` points to the output. |

All four routines follow 32-bit `cdecl`. Each returns its result in `EAX`
and preserves `EBX`, `ESI`, `EDI`, and `EBP`. The caller cleans up the
arguments. Set `cld` before `scasb` or `cmpsb` so the pointers move forward.

### Timeline

<!--
One line per week. Name the subsystem each week finishes and the member
who owns it.
-->

| Week | Goal | Owner |
| --- | --- | --- |
| 1 | Repo setup, design notes, subsystem ownership, and a prototype with basic argument parsing and line indexing | All members |
| 2 | Complete Buffering and Lines, basic Matching, and Formatting and Flags for `-n` and `-c` | All members |
| 3 | Finish the remaining flags, pass `make check`, and document quirks | All members |
| 4 | Defense | All members |


## Subsystem Ownership

Complete this section before the Week 1 progress report. The manual lists
the three subsystems. Each member owns one. In a group of four, two members
share one. The commit history must agree with this table.

| Subsystem | Owner |
|---|---|
| Buffering and lines (`lines.asm`) | Ma. Christie Jude L. Tarre |
| Matching (`match.asm`) | Aleighia Keith L. Reyes |
| Formatting and flags (`fmt.asm`, `args.asm`, the tests you add) | Trisha Mae A. Hechenagocia, Gabrielle M. Sumergido |

## Quirks and Issues

Complete this section before the Week 3 progress report. The syllabus asks
for documentation of quirks and issues with the complete implementation.
One entry per item. State what happens, what causes it, and what the group
did about it.

### Known issues

- 

### Quirks

- 
