# An iPad UI — the grid is the contract

`docs/plans/remote-workspace.md` shipped the thing worth having: an
arrangement of remote shells that survives the client. It is now reachable
from an iPad, and the chrome around it is iPad-shaped (milestones 1–3 below,
all landed). This plan is about what that terminal is mostly *used for* — an
agent session, usually Claude Code — and how to make that feel native without
throwing away the reason our client is worth having.

The short answer, and the thing to hold onto when this gets re-litigated:
**we enhance the terminal grid in place; we never reconstruct its meaning
somewhere else.**

## The gap, stated plainly

The desktop chrome was the wrong shape for a finger, and that is fixed. What
is left is that a Claude Code session on an iPad is a wall of reflowed text
with a permission prompt you answer using arrow keys. Everything the TUI does
well on a laptop — a diff you scan, a prompt you hit `y` on, a file path you
click in your editor — degrades on a device with no pointer and no arrow keys
unless something on our side helps.

## What already exists, and why we are not building that

Worth writing down, because the obvious framing for this work is already
occupied — by the vendor:

- **Anthropic ships mobile clients for Claude Code.** *Remote Control*
  (`claude remote-control`, or `/remote-control` in a live session) bridges a
  local session to the Claude iOS/Android app; code and filesystem stay local.
  Alongside it: cloud sessions (Claude Code on the web) and Dispatch. On iPad
  it is the same iOS app.
- **Third-party mobile clients are a crowded field** — Orca, MobileCLI,
  AgentsRoom, Tactic Remote, and others.

Every one of those is a **Claude Code client**. None of them is a terminal.
The Claude app's own documentation is explicit that it is "a client for Claude
Code sessions rather than a place where code runs."

That is the whole opening. We are not competing on "drive Claude Code from a
phone" — we would lose, to something bundled with the account. We are the only
one that can put a live `htop`, a test run, and an agent session in three
panes on the same iPad, because we are a real terminal first. **The Claude
Code affordances are a feature of the terminal, not the product.**

One concrete gap, worth knowing: Remote Control and cloud sessions require a
claude.ai account and are documented as unreachable with an Anthropic Console
API key or a third-party provider such as Amazon Bedrock. A team on Bedrock
cannot use the first-party mobile path at all. We run the real `claude` binary
over our own ssh transport and never touch Anthropic's routing, so that
constraint does not apply to us.

## Why re-render the TUI instead of consuming `claude -p`

The tempting alternative is to run Claude Code headless
(`claude -p --output-format stream-json`) and render the event stream as
native views. It was the first recommendation in this plan and it is wrong.
The deciding argument is not that the TUI changes less often than the event
schema — it is that **the two approaches fail in different kinds of ways**:

| | Enhance the grid | Consume `-p` events |
|---|---|---|
| Claude Code ships a UI we don't recognize | Lose one affordance; still a working session | Dropped, mis-rendered, or crashed |
| Far-side deployment | Nothing new — same `claude`, same pty, same termd | An adapter to install and version-match on every machine |
| What actually runs | Real Claude Code, the interactive permission flow included | A different execution mode (`--allowedTools`, `--permission-mode`) |
| Pane model | The terminal pane, enhanced — splits and the blob for free | A second pane type |

For a client shipped on someone's iPad, against a tool that updates weekly,
**soft failure is worth more than fidelity.** A missing affordance costs a tap.
A hard failure costs the session.

The `-p` path also quietly changes the thing under test: it is not what the
person runs at their desk. That is the same rule the bench work landed on —
reproduce as the user runs it.

## The shape: progressive enhancement over the grid

Not "parse cells back into a chat UI." That is semantic reconstruction, and it
is as brittle as the event schema without the upside. The TUI stays the source
of truth for content *and* layout; we overlay native affordances only where
the grid can be read with confidence.

```
  ┌──────────────────────────────────────────────┐
  │  ⏵ Edit  src/TerminalPad.swift               │   ← detected diff hunk:
  │    - let barH = 0                            │     own horizontal scroll,
  │    + let barH = docked ? 0 : handle          │     pinch, syntax tint
  │                                              │
  │  Do you want to make this edit?              │   ← detected prompt:
  │    1. Yes                                    │     native sheet floats
  │    2. Yes, and don't ask again               │     over it with the
  │    3. No, tell Claude what to do differently │     options as buttons
  └──────────────────────────────────────────────┘
       everything above is still ordinary terminal text
```

| Detected | Overlay | If detection misses |
|---|---|---|
| Permission prompt | Native sheet; the options as buttons | Prompt is on screen; the key bar drives it |
| Diff hunk | Independent horizontal scroll, pinch, syntax tint | Reads as coloured text, as today |
| `path:line` | Tap target that opens the file | Plain text |
| Todo list | Nothing — it already reads fine | — |

Every row is additive, independently revertible, and degrades to the terminal
we already ship.

### The safety rule: prefer revealing over acting

Read-only overlays (diff scroll, tap targets) are cheap to get wrong — the
cost is a missing affordance. **Overlays that synthesize input are not.** A
native *Allow* button works by sending the keystrokes the TUI expects; if that
key handling changes, the button silently does the wrong thing, and the wrong
thing here is approving an edit the person did not read.

So: **only act on high-confidence detection, and never guess at an option's
meaning.** The sheet renders the option lines it actually parsed and sends the
literal key for the one tapped. If the options cannot be parsed unambiguously,
no sheet appears and the pane is a terminal. A missing button costs a tap; a
mis-aimed *Allow* costs trust, once, permanently.

### What detection anchors on

The open question, and the reason milestone 4 exists before any UI is built on
it. Candidates, roughly in order of durability:

1. **OSC markers, if they exist.** We already consume OSC 133 for shell status
   dots. Anything Claude Code emits out-of-band is the clean path — no parsing,
   no drift. Check first; do not assume.
2. **Structural features of the grid** — box drawing, contiguous colour runs,
   the ±-prefixed line shape of a diff. Survives copy changes.
3. **Anchor text** ("Do you want to…", numbered option lines). Most precise,
   most brittle, and breaks under localization. Use it to *confirm* a
   structural match, never as the sole signal.

## The chrome (milestones 1–3, landed)

Recorded here because the rest of the plan sits on it:

- **A sidebar, not a tab strip.** Workspaces at the top level, panes nested,
  the OSC 133 status dots the desktop already computes, 44pt rows. Persistent
  in landscape, slide-over in portrait behind a `☰` bar. ⌘O still lands on the
  same list — one model, two ways in.
- **`TerminalPadView` subclasses `_TerminalTabsState`** and overrides `build`
  and nothing else, so the model and the chord table are shared by
  construction rather than by discipline.
- Portrait pays 44pt for a real bar rather than floating the handle over the
  grid: an early version occluded the first character of the prompt, and a
  terminal that hides a character it is drawing is worse than one that is a
  row shorter.

## What the port already established (measured, not assumed)

Landed and verified on the 13-inch simulator against `192.168.68.53`:

- **`TermdTransport`** in `sdk/Sources/Flutter/Terminal/TermdLink.swift` — the
  seam the desktops' `ChildLink` and iOS's NIOSSH channel both sit behind.
  `RemoteWorkspace`, `RemoteTerminal` and `TermdDirectory` take an injected
  dialer and no longer name a transport.
- **`TermdSSHTransport`** in the app — one channel per pane on the single ssh
  connection, with a queue between NIO's event loop and the workspace's
  blocking read thread.
- A workspace opened, ⌘D split it into live remote shells, ⌘O listed
  `main · N sessions` read back from the daemon, and the arrangement came back
  from the daemon across a full app reinstall.

Three facts worth keeping:

- **⌘ chords arrive on iPadOS exactly as on macOS** — the modifier and the
  letter are the same `KeyData` the Mac sends. The desktop chord block was
  `#if os(macOS)` and silently fell through to the shell, so ⌘O typed a bare
  `o` at the prompt. It is `#if os(macOS) || os(iOS)` now.
- **⌘/ never arrives.** The modifier is delivered, the `/` is swallowed by the
  system. Ctrl+Shift+/ works and is what the sheet names there. Any future
  chord on punctuation needs the same check.
- **A phone's column count is not an iPad's.** `defaultColumns` was a flat 50
  and made a 45-character prompt span a 13-inch display. It now derives from
  the window — ~8.2pt per column, the advance of the 13pt face both desktops
  default to — with 50 as a floor for the phone.

## Milestones (each lands green: `test/run.sh` plus its own test)

1. **The transport. — DONE.** Above.
2. **Split the presentation. — DONE.** `TerminalPadView` beside
   `TerminalTabsView`, picked at the top of `TerminalApp.build`. Landed as a
   bare pane tree first, so the seam was provably load-bearing before anything
   was built on it.
3. **The sidebar. — DONE.** Workspace list from `TermdDirectory`, panes
   nested, status dots, `+ new`; docked in landscape, slide-over in portrait.
4. **Detection, rendering nothing.** A pass over the grid that marks regions —
   permission prompt, diff hunk, `path:line` — and draws *no UI at all*, only
   a debug outline behind a flag. Ships with a corpus: recorded byte streams
   from real Claude Code sessions, and a test asserting what each frame should
   have matched. **This is the milestone that decides whether the rest is
   possible**, and it is deliberately free of consequences if detection is bad.
   The number to beat is stated before building: no false positives on the
   permission prompt, at any recall.
5. **The permission overlay.** The first affordance that synthesizes input,
   and the highest-value one. Sheet renders the parsed options; taps send the
   literal key. Refuses to appear on an ambiguous parse. The test drives a
   real session and asserts the far side saw the same byte a keypress would
   have sent.
6. **Read-only affordances.** Diff hunks get their own horizontal scroll and
   pinch; `path:line` becomes a tap target. No input synthesis, so these can
   be looser about confidence than milestone 5.
7. **Touch pane manipulation.** Long-press to lift, drop-to-edge to split, fat
   seams. The blob written must be byte-identical to what the desktop would
   write for the same arrangement — that is the test.
8. **Keyboard parity and the HUD.** `UIKeyCommand` registration, ⌘-hold HUD,
   help sheet reduced to what the HUD cannot say. Every touch action has a
   chord and every chord has a touch route; the test is a table with no blank
   cells.
9. **The phone.** Same model, one pane at a time, sidebar as a full-screen
   sheet. Explicitly last: the same code with a harder constraint, and doing it
   first would drag the iPad toward a phone layout.

## Design decisions to hold

1. **Never reconstruct semantics we can enhance in place.** The grid is the
   contract. Anything that parses the screen into a model and then renders
   that model instead of the screen has re-created the failure mode this plan
   exists to avoid — and it will arrive as a reasonable-sounding refactor
   ("we already parsed it, why draw the text twice?").
2. **Never render server-side, not even as a fallback.** The one thing that
   would make us the same as everything else.
3. **An overlay that acts must be certain; an overlay that shows may guess.**
   Decision 1's corollary at the input layer — see the safety rule above.
4. **The layout blob does not change.** An iPad and a laptop attach to the
   same workspace and must agree byte for byte. If the iPad needs to remember
   something the desktop does not, it goes in `UserDefaults`, never the blob.
5. **Share the model, fork the chrome.** `TerminalWorkspace`, `PaneLayout`,
   `TerminalPane` and the chord table stay one copy. Two copies of "what a
   pane is" is how two UIs become two products.
6. **Neither input is second-class.** Nothing reachable only by chord, nothing
   only by finger. An iPad with a Magic Keyboard is a keyboard machine, and the
   same iPad an hour later is not.
7. **No iPad-only workspace concept, and no Claude-Code-only pane type.** The
   daemon does not learn what an iPad is, and the pane does not learn what
   Claude Code is — it learns to recognize *shapes on a grid*, which is why the
   same code helps `git diff` and any other tool that draws one.

## Risks

- **Detection brittleness is the whole bet.** Mitigated by structure over
  anchor text, by milestone 4 proving hit rate before any UI depends on it, and
  by the corpus of recorded sessions becoming a regression test that fails when
  Claude Code's layout moves. What it cannot be mitigated against is a redesign
  that removes the shapes entirely — at which point we lose affordances and
  keep a terminal, which is the deal.
- **Input synthesis approving the wrong thing.** The one failure here with
  real consequences. Decision 3 and the parse-or-don't-appear rule are the
  mitigation; the test in milestone 5 asserting the exact byte is the check.
- **Scope creep toward being a Claude Code client.** The moment the pane knows
  what a "message" or a "todo" is, we are building the thing four other
  products already ship and the vendor bundles. The pane recognizes shapes,
  not concepts.
- **Two UIs, and drift between them.** Mitigated by decision 5, and by keeping
  the chord table in one file so a chord added to one is present in both or
  fails to compile.
- **A layout sensible on an iPad and absurd on a 27-inch display**, or the
  reverse. Already visible: three panes on a 13-inch iPad is ~41 columns each
  and the prompt wraps mid-hostname. The blob is device-independent by design,
  so milestone 9 has to decide whether a small screen *presents* a stored
  arrangement differently without rewriting it — presentation, not a second
  blob.
- **Stage Manager and Split View resizing.** True reflow is the feature and
  also a resize storm — every pane's pty gets a `TIOCSWINSZ` per drag frame.
  The debounce `RemoteWorkspace` applies to layout writes needs a sibling.

## What this does not make true

The iPad does not become a development machine, and this does not make us a
better Claude Code client than the Claude app. It makes us the only one where
the agent sits in a pane next to a real shell, on a device that cannot
alt-tab. Every byte still comes from the far end, and a workspace with no
network is a screen of what you last saw. The claim is that reaching that
machine feels like an iPad app rather than like looking at someone else's
screen — a real claim, and a smaller one than "you can work from an iPad now."
The moment the pitch overreaches, the first person to try it on a train with
no signal is right to say so.
