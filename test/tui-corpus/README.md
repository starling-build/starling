# The TUI corpus

Raw pty recordings — escape sequences and all — replayed through the real
emulator by `regions-test.swift` to check what `GridRegions` will and will not
put an affordance over. Milestone 4 of `docs/plans/ipad-ui.md`.

`test/run.sh` builds and runs it on every change.

## Why recordings and not fixtures

A hand-written fixture encodes what we *think* a program draws. These encode
what one actually drew, at a stated size, on a stated version — so when Claude
Code (or anything else) changes its layout, the suite fails instead of the
iPad silently losing an overlay. The recording is replayed through
`TerminalEmulator`, not a parser written for the test: a second parser is a
second thing to drift, and this suite exists to notice when the first one
moves.

## What is in here

| File | Size | What it is |
|---|---|---|
| `perm-edit-100.bin` | 100×30 | the real Edit tool-permission prompt — three options, the second **wrapped** |
| `perm-bash-100.bin` | 100×30 | the real Bash tool-permission prompt — a command line above the options |
| `trust-100.bin` | 100×30 | Claude Code's folder-trust prompt — two numbered options, `❯` on one |
| `trust-60.bin` | 60×40 | the same prompt narrow, because the layout is column-addressed |
| `neg-numbered.bin` | 100×30 | prose numbering its steps: everything a menu has **except** a selection marker |
| `neg-ls.bin` | 100×30 | `ls -1R` over a synthetic tree (`ls -la` bakes in the owner's username) |
| `neg-git.bin` | 100×30 | `git log --oneline` |

### What the permission recording caught

It earned its place immediately. The prompt is:

```
Do you want to make this edit to notes.txt?
 ❯ 1. Yes
   2. Yes, and switch to accept edits (auto-approve file edits and …) for this
        session (shift+tab)
   3. No
```

Option 2 **wraps**, and the wrapped remainder is indented to the label column
rather than renumbered. The first detector stopped its run at the first
non-option line, so it reported two options and silently dropped `No` — a
sheet offering "Yes" and "Yes, and switch…" with no way to decline. Neither
the synthetic cases nor the trust prompt (which never wraps) could have shown
that, which is the argument for recording real programs in one line.

The negatives are the point. An overlay that misses a prompt costs a tap; one
that appears over ordinary text and sends a keystroke costs trust. The bar is
one-directional — **no false positives on an option list, at any recall.**

## A trap this suite exists to avoid

While checking the Bash recording by hand, a quick `re.sub` over the raw bytes
rendered its first option as `❯1. Yes` — marker jammed against the number,
apparently a different layout from the Edit prompt's `❯ 1. Yes`. It is not.
The bytes are `❯`, then `ESC[4G`, then `1.`: the stripping threw away the
cursor move, so two cells that are three columns apart on screen looked
adjacent.

The lesson is the reason for the whole harness. **Do not read a recording with
a regex.** Feed it to the emulator and look at the grid, which is what
`regions-test.swift` does and what the detector sees.

## Adding a recording

`record-tui.py` runs a program on a pty of a fixed size and writes every byte
it emits. Keep recordings small and name the size in the table above; the
replay must use the same size or the frame will not lay out the same way.

Recordings may contain paths and prompt text from the machine that made them.
Check before committing.
