# Rendering Claude Code natively — checkpoint

**Branch:** `claude-code-native-render`, off `wip/post-rebase-ios-work`
(`90941ef`, the iPad port). **Read `docs/plans/ipad-ui.md` first** — that is
the plan; this file is the state of the work against it, written so a session
with none of the preceding context can pick it up.

**Everything below is measured on this machine unless it says otherwise.** The
assumptions that were checked and turned out wrong are called out, because
each one cost a wrong implementation.

---

## The idea in one paragraph

Claude Code draws a TUI. We already draw TUIs — byte-exact, in our own
emulator, on the device. So rather than shipping a screen (server-side
rendering) or consuming `claude -p --output-format stream-json` (a second
protocol to keep in step), we **recognise shapes in our own grid and put
native affordances over them**, leaving the terminal underneath untouched and
working. A permission prompt becomes a sheet with buttons; a diff hunk gets
its own scroll; `file.swift:42` becomes tappable. When Claude Code ships a
layout we do not recognise, we lose an affordance and keep a working session.

## Why not `claude -p` (this was reversed once — do not re-reverse it silently)

The first version of the plan recommended headless mode. The deciding
argument is not that the TUI changes less often than the event schema; it is
that the failure modes differ in kind:

| | Enhance the grid | Consume `-p` events |
|---|---|---|
| A layout we do not recognise | lose one affordance, session still works | dropped, mis-rendered, or crashed |
| Far-side deployment | nothing new — same `claude`, same pty, same termd | an adapter to install and version-match everywhere |
| What actually runs | real Claude Code, interactive permission flow included | a different mode (`--allowedTools`, `--permission-mode`) |
| Pane model | the terminal pane, enhanced | a second pane type |

Also relevant, established by research rather than assumption: **Anthropic
ships mobile clients for Claude Code** (Remote Control + the Claude iOS app),
and there are several third-party ones (Orca, MobileCLI, AgentsRoom, Tactic
Remote). Every one is a Claude Code *client*; none is a terminal. Competing on
"drive Claude Code from a phone" loses to something bundled with the account.
Our opening is that the agent sits in a pane next to a real shell. **The
Claude Code affordances are a feature of the terminal, not the product.**

One gap worth knowing: Remote Control and cloud sessions are documented as
requiring a claude.ai account and unreachable with a Console API key or
Amazon Bedrock. We run the real binary over our own ssh transport and never
touch Anthropic's routing, so that constraint does not apply to us.

---

## What is built and green

| Piece | File | Platform |
|---|---|---|
| Shape detection | `sdk/Sources/Flutter/Terminal/GridRegions.swift` | any |
| "May I act on this?" | `sdk/Sources/Flutter/Terminal/PromptChoice.swift` | any |
| Poll / answer / draw the sheet | `apps/TerminalApp/Sources/TerminalApp/TerminalPrompt.swift` | any |
| Corpus + test | `test/tui-corpus/` | — |

`TerminalPrompt.swift` is an extension on `_TerminalTabsState`, the same
pattern `TerminalSwitcher.swift` and `TerminalHelp.swift` use, so **the Mac
terminal and the iPad get the sheet from one implementation**. Stored
properties live in the class (an extension cannot store), next to `_switcher`
and `_helpOpen`, for the same reason and with the same note.

`test/run.sh` runs the corpus test on every change: **57 checks, green.** The
only failing step in the suite is `engine-header`, which is a stale engine
checkout and unrelated (see "Environment traps").

### The load-bearing rule

A run of numbered lines is a prompt only if **exactly one of them is marked**
as selected. Prose numbers its steps constantly; nothing numbers its steps
*and* points at one. That single requirement is what makes the plan's bar —
no false positives, at any recall — reachable. The corpus's hardest negative
is prose with consistent columns and sequential numbers and no marker.

---

## What was checked, and what it changed

**There are no OSC markers.** The plan ranked "OSC markers, if they exist"
as the most durable signal and said to check rather than assume. Checked: the
only OSC in an entire Claude Code session sets the window title
(`OSC 0 ; ✳ Claude Code`). No OSC 133, nothing semantic. Structural detection
is not a preference, it is the only option. **Do not spend time looking
again** unless Claude Code's release notes say otherwise.

**A bare digit confirms a prompt — no Return.** The footer reads "Enter to
confirm", which suggests arrows-then-Enter. Driven against a real `rm`
permission prompt: writing `1` to the pty with nothing after it deleted the
file. This is why `PromptChoice.keystroke(for:)` returns the digit as drawn
and the overlay sends exactly that.

**Options wrap, and the first detector silently dropped one.** The real Edit
prompt is:

```
Do you want to make this edit to notes.txt?
 ❯ 1. Yes
   2. Yes, and switch to accept edits (auto-approve file edits and …) for this
        session (shift+tab)            ← indented to the LABEL column
   3. No
```

A scanner that stops its run at the first non-option line reports two options
and loses `No` — a sheet with no way to decline. Continuation lines are now
absorbed into the option above. Neither the synthetic cases nor the trust
prompt (which never wraps) could have caught this; the recording did, on
first contact.

**Do not read a recording with a regex.** Checking the Bash capture by hand
with a `re.sub` rendered its first option as `❯1. Yes` — marker jammed against
the number, apparently a different layout. It is not: the bytes are `❯`, then
`ESC[4G`, then `1.`, and the stripping threw away the cursor move. Feed
recordings to the emulator and look at the grid, which is what the test does.

---

## The corpus

Raw pty recordings, replayed through the **real** emulator (a parser written
for the test would be a second thing to drift). `test/tui-corpus/README.md`
has the full table and the recipe for adding one.

| | |
|---|---|
| `perm-edit-100.bin` | real Edit permission prompt, three options, one wrapped |
| `perm-bash-100.bin` | real Bash permission prompt, command line above the options |
| `trust-100.bin` / `trust-60.bin` | folder-trust prompt at two widths |
| `neg-numbered.bin` | prose with numbered steps — the hard negative |
| `neg-ls.bin` / `neg-git.bin` | ordinary command output |

Recording is `test/tui-corpus/record-tui.py`. **Provoking a permission prompt
reliably** took some doing: `echo hi` is auto-approved even under
`--permission-mode default`, and a request inside a large repo spends minutes
exploring and never reaches a gated command. What works is a throwaway
directory with one file and an unambiguous request (`rm junk.txt`). Answer the
folder-trust prompt first with a bare Return (`--send '5:'`).

Fixtures are checked for leaked usernames and home paths before committing —
`ls -la` bakes in the owner's name, which is why the negative uses `ls -1R`.

---

## Where it stops

**The sheet has never been seen on screen.** Everything above is verified by
test and by driving real sessions; the overlay itself is built, compiles for
both platforms, and is stacked into both `build()` methods — but no screenshot
exists of it appearing over a live prompt. That is the next thing to do, and
the milestone's own test is still unwritten: *drive a real session, tap an
option, assert the far side acted on it.*

The dev loop for that is the **macOS terminal**, not the simulator — Claude
Code runs locally, no ssh hop, no osascript into Simulator. It was blocked
only on macOS TCC dialogs, which are the user's to answer.

### Build the Mac app from this checkout

`starling-ios`'s `engine` symlink points at the iOS engine tree, which has no
macOS output. The sibling checkout has one. **Both variables are required** —
the SDK manifest reads `FLUTTER_SWIFT_ENGINE_OUT`, the app's reads
`STARLING_ENGINE_OUT`, and setting only one fails at `FlutterMacOS not found`:

```sh
ENG=/Users/dishengsu/dev/starling/starling-engine/engine/src/out/host_debug_arm64
STARLING_ENGINE_OUT=$ENG FLUTTER_SWIFT_ENGINE_OUT=$ENG build/macos-app.sh TerminalApp
open ".stage-macos/Starling Terminal.app"
```

Running the bare `swift build` binary does not work — it cannot find
`icudtl.dat`. Use the bundle.

---

## Next, in order

1. **See it.** Run the Mac app, start `claude` in a scratch dir, ask for
   something gated, screenshot the sheet. Fix what looks wrong.
2. **The milestone-5 test.** Drive a real session to a prompt, tap an option,
   assert the far side saw the byte a keypress would have sent. The
   filesystem is the cleanest assertion — `rm junk.txt`, then check the file.
3. **Milestone 6, read-only affordances.** Diff hunks get their own
   horizontal scroll and pinch; `path:line` becomes tappable. These cannot do
   harm, so they can be looser about confidence than the sheet.

## Rules that must not be quietly relaxed

1. **Never reconstruct semantics we can enhance in place.** The grid is the
   contract. Anything that parses the screen into a model and renders *that*
   instead of the screen has re-created the failure mode this work exists to
   avoid — and it will arrive as a reasonable refactor ("we already parsed it,
   why draw the text twice?").
2. **An overlay that acts must be certain; an overlay that shows may guess.**
   A missing button costs a tap. A mis-aimed *Allow* costs trust, once.
3. **Send the key the program drew.** Never an index, never something read out
   of the label, never "the one that says Yes". If a prompt ever puts a
   destructive option first, reasoning about meaning approves it.
4. **The pane recognises shapes, not concepts.** Nothing in `GridRegions`
   mentions Claude Code, and it should stay that way — it is what keeps this
   from becoming an agent client, and it is why the same detector helps
   `git diff`.
5. **The terminal keeps the keyboard.** The sheet adds a way to answer; it
   never removes the existing one. That is what makes a wrong sheet
   survivable.

## Environment traps

- **A new file in `sdk/` needs the stale SwiftPM plan cleared**, or dependents
  fail with `cannot find <symbol> in scope` though the manifest lists it.
  This bit once already:
  `rm -f apps/TerminalApp/.build/release.yaml apps/TerminalApp/.build/build.db && rm -rf apps/TerminalApp/.build/*/release/Flutter.build`
- **`engine-header` failing in `test/run.sh` is not this work.** The engine
  checkout (`../starling-engine-ios`) is on `wip/post-rebase-snapshot-bridge`
  with uncommitted changes, a few commits behind `starling`.
- `sdk/Sources/SwiftRuntime/SwiftRuntimeCallbackTable.swift` carries temporary
  frame-gap diagnostics in the working tree. Deliberately uncommitted; do not
  commit it.
