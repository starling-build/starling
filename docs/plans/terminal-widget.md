# TerminalView: the terminal as an SDK widget

Status: **implemented**, 2026-08-11 — steps 1–4 landed the same day the
plan was written (58f4272, 74a2f76, 794720f, and the TerminalDemo commit).
The extraction was perf-neutral: +0.1% at median-of-5 against the
pre-widget baseline (`fs4kw3m` in the bench data). Remaining ideas live in
"Later" under the migration order.

Release-notes draft for the next SDK release:

> **TerminalView** — the terminal is now a framework widget. A
> `TerminalSession` owns the emulator and (optionally) a PTY;
> `TerminalView` renders it: wide characters and grapheme clusters done
> properly (a clean ucs-detect sweep where ghostty nightly scores 33
> errors), 0.49x of ghostty nightly's wall on its own benchmark suite,
> mouse reporting, scrollback, selection, bundled fonts. A complete
> terminal app is twenty lines — `swift run TerminalDemo`. Headless
> sessions (`feed`/`onOutput`) embed SSH channels, replays, or a remote
> agent's pty.

## Why

The terminal is now the strongest component we ship — 0.49x of ghostty
nightly's wall on its own benchmark suite, a perfect ucs-detect battery
(data in `docs/perf/terminal-vs-ghostty-2026-08-11/`), 26 conformance
checks in the fast tier — and all of it is trapped inside one app. Every
agent-era application wants a terminal surface: an agent dashboard is N
embedded terminals with chrome, a CI viewer is a terminal with a sidebar,
an SSH client is a terminal with a connection form. Today each of those
would have to copy TerminalApp. The framework's whole thesis is "an app
is a widget"; the terminal should be one.

This is also the SDK's flagship-widget story: "build a terminal app in
twenty lines, and it's the fastest, most conformant terminal on Linux" is
a sentence no other UI framework can say.

## API sketch

Controller pattern, like Flutter's `TextField`/`TextEditingController` —
a `TerminalSession` owns the emulator and (optionally) a PTY; a
`TerminalView` renders one session and feeds it input.

    // A live shell:
    let session = TerminalSession(
        command: "/bin/bash", args: ["-l"],
        environment: ProcessInfo.processInfo.environment,
        initialCols: 80, initialRows: 24)

    // Or headless — the embedder owns the byte streams (SSH, a replay,
    // an agent's remote pty):
    let session = TerminalSession()
    session.feed(bytes)                     // emulator input
    session.onOutput = { bytes in ... }     // responses + user keystrokes

    TerminalView(
        session: session,
        theme: .starlingDark,               // palette16 + fg/bg/cursor/selection
        font: TerminalFont(family: "Roboto Mono", size: 13),
        autofocus: true,
        onTitleChanged: { title in ... },
        onBell: { ... },
        onExit: { code in ... }
    )

Both spellings ship together (ported initializer + trailing-closure
builder overload) — `test/lint.py` enforces the parity.

## What moves where

| piece | today | destination |
|---|---|---|
| C emulator core (`CStarlingTerm`, incl. `starling_widths_gen.h`) | `apps/TerminalApp/Sources/` | sdk target `CTerminalCore`, public API unchanged |
| conformance suite (`test/core/conformance.c`) | repo test tier | stays; path updated to the sdk target |
| PTY spawn/resize (`Pty.swift`, `PtyWindows.swift`) | TerminalApp | `TerminalSession` platform backends (Linux forkpty now; the Windows file is ConPTY groundwork) |
| row painter (`_rowWidget`, style cache, cell metrics, run merging) | `TerminalApp.swift` | `TerminalView` internals (`TerminalGridPainter`) |
| key/mouse translation (app cursor keys, bracketed paste, mouse reporting 1000/1002/1003 + SGR 1006, alternateScroll) | `TerminalInput.swift` | `TerminalView` internals |
| scrollback view + wheel routing | TerminalApp | `TerminalView`, optional `TerminalScrollController` |
| window chrome, menus, app identity | TerminalApp | stays — TerminalApp becomes a ~100-line consumer and remains the perf/conformance testbed |

## Design decisions to hold

1. **Session/view split is the API.** One session, one view in v1;
   multiple views over a session (a mirrored terminal) is explicitly out
   of scope until someone needs it.
2. **Repaint contract stays generation-based.** The view polls
   `starling_term_generation` per frame tick exactly as TerminalApp does
   today — element remount is the dominant update path in this framework
   (CLAUDE.md), and the painter must keep the run-merging + style-cache
   behaviour that the colour-heavy benchmarks priced.
3. **Cell-metric discipline travels with the painter.** Measure with the
   font the rows are painted in; pin rows to exact cell multiples; the
   fallback-family fractional-advance trap (soft wrap eating the last
   word) is a documented war story — the widget inherits the fix, and the
   `STARLING_CELL_W` override stays as an escape hatch.
4. **Fonts are the embedder's choice, Roboto Mono the default.** The sdk
   already bundles CupertinoIcons; TerminalFont resolves through
   fontconfig with the same fallback logic TerminalApp grew (box glyphs,
   CJK, emoji).
5. **The C core's API is the compatibility boundary.** Widget and app
   talk to it through `starling_term.h` only; the conformance suite is
   the contract's test. No Swift-side emulator state.
6. **v1 scope = today's TerminalApp parity.** No selection/search — they
   don't exist today either; they land later as widget features that
   every consumer inherits at once (that being the point of the move).

## Migration order (each step lands green: fast tier incl. conformance, then a bench spot-check)

1. Move `CStarlingTerm` into the sdk as `CTerminalCore`; TerminalApp
   depends on it. Pure move, no behaviour change — the diff that proves
   it is the md5 of the rebuilt app.
2. Extract `TerminalSession` (pty + emulator + resize plumbing) into the
   sdk; TerminalApp adopts it.
3. Extract `TerminalView` (painter + input translation); TerminalApp
   becomes a consumer. This is the big one — land it behind the app's
   existing behaviour, diffing screenshots and the bench numbers.
4. `Examples/TerminalDemo` in the sdk (the twenty-line app), a docs page,
   and the sdk release notes entry. Ship in the next SDK release.
5. Later, in the widget where every consumer gets them: selection +
   clipboard, search, Windows ConPTY, per-view themes, and the
   agent-dashboard example (N sessions in a grid — the workspace story
   as a *widget* story).

## Risks

- **API commitment.** The SDK is public; mark TerminalView experimental
  in the first release and stabilise in the next.
- **Perf regression during extraction.** The bench harness runs against
  TerminalApp binaries, so steps 1–3 are each measurable; the 4K
  fullscreen suite is the gate (current baseline: `fs4kfin`, 0.49x).
- **sdk build-time creep.** The C core is ~3k lines of dependency-free
  C — negligible next to the framework itself.
