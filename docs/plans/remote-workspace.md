# Remote workspace — the last thing tmux does that we don't

`docs/plans/remote-terminal.md` shipped the hard half: a session that outlives
its client, resumed on a byte offset, with no emulator on the server. Its
milestones 1-3 are DONE and verified over a real ssh link. What it did not
build is the reason people still open tmux, and this plan is that.

## The gap, stated plainly

Today one remote session is one tab. tmux gives you a *workspace*: several
shells arranged in panes, and — the part that actually matters — **that
arrangement survives**. Reattach from a different machine and your layout is
back: same panes, same split ratios, same names, same one focused.

We have persistence of *processes*. We do not have persistence of
*arrangement*. That is the whole difference, and it is why "run tmux inside
termd" is currently the honest recommendation to a tmux user.

Three things are missing, and only one of them is interesting:

1. **Splits in the shipped terminal.** They exist as `sdk/Examples/TerminalTiling`
   and are not in the product. Local work, no protocol.
2. **Several remote sessions over one connection.** `struct client` in
   `termd.c` holds one `uint32_t session` — a client connection attaches to a
   single session. Solvable two ways, and the cheap way needs no protocol
   change at all (see milestone 4).
3. **Server-side layout.** The interesting one. Nothing in the daemon knows
   that two sessions belong together, let alone how they were arranged.

## The shape: the daemon groups sessions and stores an opaque blob

The rule from the parent plan holds without amendment — **the server never
renders** — and it extends naturally: *the server never renders, and it never
parses the layout either.*

```
  workspace "dev"                        client
    ├── session 12  ──bytes──►  ┐
    ├── session 13  ──bytes──►  ├──►  three panes, drawn here
    └── session 14  ──bytes──►  ┘
    layout: <opaque blob> ◄──────────  written by the client on change,
                                        read back on attach
```

The daemon gains exactly two concepts: a **workspace** (a name, and the set of
sessions in it) and a **blob** (bytes it stores and returns, never inspects).
Split ratios, orientation, focus, pane titles and anything we invent later all
live inside that blob, so adding a layout feature later is a client change and
not a protocol change.

That is the design constraint worth defending: if the daemon ever has to
understand what a pane is, we have rebuilt tmux's mistake in a new place.

## Why this is a better shape than tmux's, concretely

Not taste — these follow from where the multiplexing happens:

- **No second emulator.** Each pane is a byte-exact stream into our own core,
  so truecolor, wide characters, grapheme clusters and mouse modes arrive as
  the far end wrote them. tmux must re-encode a composed screen.
- **Real resize.** Each pane's pty gets its own `TIOCSWINSZ`. tmux
  recomposes a character grid, and attached clients fight over one size.
- **Real scrollback per pane** — the terminal's own, with mouse and search.
  No copy-mode, because there is nothing to copy *out of*.
- **No prefix key.** The client has UI. Nothing to prefix, nothing to learn,
  and no collision with the shell's bindings (see `termd`'s `^]`, which
  exists only because a byte-exact tunnel has no spare keystroke).
- **A repaint is not a screenful of escapes on the slow link.**

## Protocol additions (v1)

Four frames, all of them thin. Version gate is the existing `HELLO`.

    WS_CREATE    name                     -> ws_id
    WS_LIST                               -> [ws_id, name, [session ids], blob_len]
    WS_SET_META  ws_id, blob              -> ACK        (client writes layout)
    WS_GET_META  ws_id                    -> blob

Plus one field on the existing `OPEN`: an optional `ws_id` so a new session is
born into a workspace. `ATTACH` is unchanged — you still attach to a session,
because the client is what assembles a workspace out of several attaches.

*(What shipped is `WS_ADD` instead of that `OPEN` field, and a `WS_INFO`
reply to every write — see milestone 2 below for why.)*

The blob is capped (16 KB is generous for a layout tree) and stored per
workspace, not per session, so it survives every session in it dying.

## Milestones (each lands green: `test/run.sh` plus its own test)

1. **Splits in the shipped terminal. — DONE.** The pane tree lifted out of
   `sdk/Examples/TerminalTiling` into the app: `TerminalPanes.swift` is the
   model, the widgets are in `TerminalTabs.swift`. Draggable seams, focus
   follows click, `Ctrl+Shift+D`/`⌘D` and `Ctrl+Shift+E`/`⌘⇧D` to split,
   `Ctrl+Shift+W`/`⌘W` to close the pane or the tab if it is the last one.
   Local only, no termd, no protocol.
2. **Workspaces in the daemon. — DONE.** Five frames rather than four —
   `WS_CREATE`, `WS_ADD`, `WS_SET_META`, `WS_GET_META`, `WS_LIST`, with
   `WS_INFO` as the reply to every write — and *no* `ws_id` on `OPEN`, which
   is the one thing this differs from the sketch above: `OPEN`'s payload ends
   with "command (rest)" and has no room to grow at the end, so joining a
   session to a workspace is its own additive frame and needs no version bump.
3. **Attach a workspace, not a session. — DONE.** `--workspace
   remote:host/ws:dev` (or `STARLING_WORKSPACE`) opens a tab that is N
   attaches, the tree rebuilt from the blob, the ratios where they were left
   and the keyboard in the pane that had it. Every change to the arrangement —
   split, close, focus, a seam coming to rest — is written back, debounced
   0.4 s inside `RemoteWorkspace` so a drag is one write and not a hundred,
   and flushed on the way out.
   - `RemoteWorkspace` (sdk) is the control link: its own connection, no
     session on it, because a workspace outlives every pane in it and so
     must the thing that holds its identity.
   - `TermdLink.swift` is the child transport both links share, and it grew a
     Darwin branch (`posix_spawn` with `POSIX_SPAWN_CLOEXEC_DEFAULT`; Swift's
     Darwin overlay makes `fork()` unavailable outright), so `RemoteTerminal`
     now builds on macOS too.
   - A pane whose stored session id is gone opens a fresh one rather than
     dying (`reopenIfSessionGone`). The arrangement is what was promised to
     survive; a dead rectangle in the middle of it keeps none of that promise.
   - **Verified live**: three panes on a local daemon, a seam dragged well off
     centre, the app killed outright — no clean exit — and relaunched: same
     tree, same ratio, same three shells with their scrollback replayed. Then
     the daemon killed under the running app: every pane reported the link
     lost, opened a fresh session, kept its place in the tree, and the blob
     was rewritten with the new ids — so the NEXT relaunch reattached to those
     silently.
   - **Not yet the launcher the plan pictures.** The entry point is a launch
     argument, so a workspace cannot yet be opened from inside a running
     terminal. Lifting `TerminalTiling`'s launcher is the obvious next piece,
     and it calls the same `_openWorkspace`.
   - **Closing a remote pane detaches; it does not end the shell.** The
     protocol has no frame that kills a session. The pane leaves the layout
     and the session keeps running, where `--list` still finds it. A frame
     that ends one belongs with milestone 5.
4. **Several sessions over one connection — measured; the cheap path stays.**
   The cheap path needs no protocol change: ssh already multiplexes channels,
   so N attaches over one `ControlMaster` is N streams, one authentication,
   one TCP connection. The expensive path is a session id on every
   `DATA` and `INPUT` frame so one client connection carries all panes.

   *(That paragraph said "today", and that word was wrong — see "what a real
   link costs" below. `termdArgv` passes no `ControlMaster` options, so unless
   the person running this has put them in their own `ssh_config`, every pane
   is a full TCP connection and a full authentication of its own.)*

   What N panes cost the far machine, measured on a Mac (2026-08-18, local
   bridges, no ssh in the path):

   | panes | attach | bridge RSS each | daemon RSS |
   | --- | --- | --- | --- |
   | 1 | 0.02 s | 1.34 MB | 1.5 MB |
   | 3 | 0.01 s | 1.34 MB | 1.8 MB |
   | 6 | 0.01 s | 1.34 MB | 2.3 MB |
   | 12 | 0.02 s | 1.34 MB | 3.3 MB |

   So a pane costs about **1.3 MB of bridge process and 165 KB of daemon**
   while it is idle — six panes is ~8 MB of processes, sixty would be ~80 MB,
   which is the "server process count" risk quantified and the shape the plan
   guessed. In-protocol multiplexing would save exactly that 1.3 MB per pane
   and one ssh channel each; at six panes it buys nothing worth a protocol
   change, and the number to watch is the process count rather than the bytes.

   The surprise is where the memory actually is. A session's 8 MB ring is
   `malloc`ed and only faulted in as it is written, so an idle pane costs
   nothing like 8 MB — but a session that has PRODUCED 12 MB takes the daemon
   from 1.4 MB to 18.9 MB, of which 8 MB is the ring it has now filled. The
   cost of a workspace is therefore set by how noisy its panes are, not by how
   many there are.

   **What a real link costs — measured 2026-08-18** over key-based ssh from
   this Mac to a stock Ubuntu box on the LAN, by `test/workspace/link-bench.swift`,
   which drives the real `RemoteTerminal` (its spawn, its framing, its backoff)
   and substitutes only the emulator. Both numbers the plan left open, and one
   it did not think to ask:

   | panes | setup p50 | setup p50, `ControlMaster` | reconnect p50 | dials in one 250 ms window |
   | --- | --- | --- | --- | --- |
   | 1 | 235 ms | — (builds the master) | 820 ms | 1 |
   | 3 | 343 ms | 26 ms | 821 ms | 3 |
   | 6 | 306 ms | 73 ms | 942 ms | 6 |
   | 12 | 381 ms | 41 ms | 994 ms | 12 |

   **ssh channel setup is ~300 ms per pane and they pay it in parallel**, so a
   six-pane workspace opens in about the time one pane takes. Multiplexing is
   worth roughly **8x on setup** once a master exists — 300 ms becomes 40 —
   which is a much bigger win than the memory numbers above suggested, and it
   is not switched on.

   **Reconnect is ~0.8-1.0 s for any N**, of which 250 ms is the jittered
   backoff and the rest is a fresh handshake. That is the good news.

   The bad news is the last column, and it is what the risk list called a
   thundering herd. Every pane holds its own backoff and they are all handed
   the same `attempt` by the same tunnel dropping, so **every pane dialed
   inside the same millisecond** — measured spread 0.0 ms, at every N tried.
   A stock sshd's `MaxStartups 10:30:100` begins refusing unauthenticated
   connections at ten, and at 24 panes it did: two of them came back
   `kex_exchange_identification: Connection reset by peer`, which is a pane
   that fails to return while its neighbours do. `TermdDialPacer` now spaces
   dials per host, and the same 24 panes reconnect with **6 in the window and
   no refusals** — the bound is `burst + window/spacing`, so it does not grow
   with N at all:

   | 24 panes | busiest 250 ms | spread | setup p50 | refusals |
   | --- | --- | --- | --- | --- |
   | unpaced | 24 | 676 ms | 808 ms | 2 |
   | paced | 6 | 1943 ms | 1349 ms | 0 |

   The cost is real and bounded: the Nth pane of a burst waits
   `(N - 4) x 100 ms`, so 24 panes take 2.4 s to all come up rather than 1.1 s.
   That is the right trade — a workspace that opens half a second slower beats
   one where two panes are simply missing.

   **`ControlMaster` is still not switched on by default, and the measurement
   is why.** It caps out: `MaxSessions` (default 10) is a limit on channels
   *within* one connection, so panes past the tenth are refused with
   `Session open refused by peer` — a hard wall exactly where a big workspace
   wants to be, and a more confusing failure than a slow start. Concurrent
   first dials also race to create the master ("ControlSocket ... already
   exists, disabling multiplexing") and quietly fall back to their own
   connections. It is a good thing to put in `ssh_config` for a workspace of
   six; it is not a good thing to impose on everyone from inside `termdArgv`.
5. **Coming back to it.** Milestone 3 proved the arrangement survives; this is
   the milestone that makes *arriving* feel right, which is the whole point of
   the feature and the part a person actually experiences. Three pieces, in
   this order:
   - **Discovery, and a default. — DONE.** `⌘O` / `Ctrl+Shift+O` opens a
     switcher: one line to type a destination (`name`, or `host/name`) and
     under it the workspaces that host actually has, from `WS_LIST` through
     `TermdDirectory`. Enter on a row opens it, Enter on something typed
     creates it — a named workspace is attach-or-create on the daemon, so the
     picker needs no second verb for "new". The destination is remembered
     (`~/.local/state/starling-terminal-workspaces`) and a launch with no
     arguments reopens the last one, which is what makes closing the lid and
     opening it somewhere else need no typing at all. `⌘T` is still a local
     shell; the launch argument still works and now only exists for scripts.
     Loose sessions — the ones in no workspace — are listed by the daemon and
     not yet shown, because the app has no way to open one: that is
     milestone 7's, alongside a frame that can end one.
   - **Bounded replay. — DONE.** A fresh attach asks from offset 0, so the daemon
     replays everything its ring still holds: up to 8 MB *per pane*. Six panes
     on a hotel connection is minutes of nothing. `ATTACH`'s payload is
     `id, from_seq, cols, rows` and the daemon checks `len < 16`, so a trailing
     `max_replay u32` is purely additive — "the last N bytes, not all of it".
     `ATTACHED` already reports where the stream truly starts and the client
     takes its word, so a bounded attach begins cleanly rather than reporting
     history it deliberately declined; the `[N bytes of history dropped]` note
     stays for what it was always for, a live client falling far enough behind
     that the ring rolls past it. A single remote session stays unbounded (its
     scrollback is worth the wait); a workspace pane asks for a screenful or
     two, and only on its first attach — a reconnect resumes from a real
     offset, where a cap would silently discard what was missed.
   - **Where the pane was. — DONE.** When the daemon restarts, panes came back
     as fresh shells in `$HOME` — same rectangles, wrong contents. No protocol
     change was needed: the client's own emulator keeps the **OSC 7** the
     shell already emits (the core parsed OSC into a buffer nothing read), the
     blob carries it per leaf, and the pane reopens with
     `cd '<dir>' && exec "$STARLING_SHELL"` through `OPEN`'s existing command
     field — composed only for a daemon whose HELLO_OK says its commands reach
     a POSIX shell, since on a Windows daemon that string is a pane that exits
     before it draws.
     **And the shells that say nothing — DONE.** OSC 7 is an opt-in that a
     great many shells do not take: macOS ships zsh emitting it for Apple
     Terminal alone, so on the desktop this was developed on the feature was
     silent. `SESSION_CWD` asks the daemon instead, which owns the pty and can
     ask the kernel (`/proc/<pid>/cwd`, `proc_pidinfo` on Darwin, nothing on
     Windows — hence a second capability bit rather than a guess). The client
     still prefers its own OSC 7 reading, which needs no round trip and is
     never stale, and polls the daemon every 5 s as the fallback under it.
     Verified with a plain macOS zsh and no hook of any kind: two panes cd'd
     to `/usr/share/man` and `/Library/Fonts`, daemon killed, both reopened
     there.
6. **More than one client at once — a policy, not an accident. — DONE.**
   Attaching from a second machine always worked (`ATTACH` has never rejected
   a second client, and each keeps its own byte cursor); what was missing was
   an answer to the two things that then collide.

   **The pty's size: last writer wins.** One pty has one size and that is the
   price of not rendering on the server, so somebody loses. The daemon already
   took the last `RESIZE` it was given; what makes that the right rule rather
   than an accident is the client half — **engaging with a window re-asserts
   every one of its panes** (`TerminalWorkspace.assertSizes`, on pane click and
   on tab select), so "last writer" means "the machine in your hands" and not
   "whichever attached most recently". Between engagements the other client
   draws a grid the shell does not know about: its text was wrapped for
   somebody else. That is visible rather than corrupting, one click fixes it,
   and the alternative — smallest-client-wins — makes the laptop letterbox
   itself to the phone permanently, which is worse for the case this feature
   is actually for.

   **The arrangement: last writer wins, and the loser is told.**
   `WS_SET_META` now broadcasts `WS_META` to every other connection watching
   that workspace (a connection starts watching by naming one in any `WS_`
   frame). The client that receives it ADOPTS — its `lastSent` moves to the
   blob it was handed — so it does not write its own tree back and the two
   cannot trade the same arrangement forever. Applying it is a **merge, not a
   rebuild**: a pane already attached to a session the new tree still mentions
   is kept exactly as it is, so a split appearing on the other machine costs
   one new pane rather than every pane's screen.

   Verified live with two clients on one workspace: a split in one appeared in
   the other with the same session behind it, and clicking into the small
   window sized both shells to 36x24 while clicking into the large one put
   them back to 66x40.
7. **A session that can end, and a lifecycle that says so. — DONE.**
   Closing a remote pane only detached, so every closed pane left a shell that
   nothing would ever show again. `KILL` is the verb that was missing —
   deliberately a different one from `DETACH`, which is what this daemon is
   built around: **closing a PANE ends its shell; closing a tab or the window
   detaches**, because a pane is gone from the arrangement for good while a
   workspace is the thing you come back to.

   Two things fell out of writing it, both older than this plan:
   - **`TERMD_EXIT` had never been sent.** The frame is in the protocol from
     v0 and the attach CLI has always handled it, but nothing emitted it: a
     client whose shell exited simply stopped receiving bytes and sat there,
     because "no more output" and "over" look the same on a stream. The daemon
     now sends it, and a pane whose shell ends closes itself the way a local
     one does.
   - **Nothing ever reaped a dead session.** `session_close` existed and was
     never called; a session whose shell exited kept its slot forever, so a
     table of sixty-four filled with corpses and the daemon began refusing to
     open sessions on an idle machine. A dead session still keeps its ring —
     reattaching to read the last words is the point — but the oldest one now
     makes way when a live one needs the slot. Killing a session also drops it
     from every workspace's membership, which was the same leak seen from the
     other side.
8. **Sessions that belong to nothing. — DONE.** Someone runs
   `starling-termd build` over ssh, and until now this terminal could not
   reach it: the daemon listed it and the app had no way in, because what this
   app draws is always a workspace — that is what an arrangement is stored
   against. So the switcher shows loose sessions under the workspaces and
   choosing one ADOPTS it: into the workspace on screen when there is one on
   that machine ("bring that session in here"), otherwise into a workspace
   named after it. Either way it stops being loose — the pane's link `WS_ADD`s
   it and the next arrangement written includes it — and nothing is opened on
   the far side, because this is an ATTACH to something already running.
9. **Later, separable:** detach/reattach of a whole workspace as one
   operation, workspace names in `--list`, and genuinely shared editing of one
   workspace by two people.

## Design decisions to hold

1. **The daemon never parses the layout.** It stores bytes. The moment it
   needs to know what a pane is, this has become tmux with extra steps.
2. **A workspace is a grouping, not a screen.** No compositing server-side,
   no "workspace size", no shared cursor. Sessions inside it keep independent
   sizes, exactly as they do now.
3. **`ATTACH` stays per session.** The client assembles; the server serves.
   This is what keeps N-panes and 1-pane the same code path on the daemon.
4. **No prefix key, ever.** Splits, focus and zoom are UI. If a feature seems
   to need a keystroke reserved from the shell, it belongs in the tab bar or
   a menu instead.
5. **The blob is the client's private format**, versioned inside itself. An
   older client attaching to a workspace written by a newer one must degrade
   to "here are the sessions, arranged by default" rather than fail.
   The corollary, learned the moment milestone 5 wanted to add a field: a
   decoder that refuses everything it does not fully understand makes every
   future field cost an older client its whole layout — and "an older client
   on the other machine" is exactly the case this feature is for. So a leaf
   carries **length-prefixed room it does not have to understand**, and a
   reader skips what it does not know instead of refusing it. Version 2 is
   where that room was added; there should never need to be a version 3.

## Risks

- **Layout blob skew** between client versions. Mitigated by decision 5, and
  the test in milestone 2 should include reading a blob whose version byte is
  from the future.
- **N panes, N reconnect storms — real, measured, and now paced.** A dropped
  link with six panes meant six backoff timers, and because one tunnel drops
  them all at the same `attempt`, they fired within 0.0 ms of each other. At
  24 panes a stock sshd refused two of them outright (`MaxStartups 10:30:100`).
  `TermdDialPacer` in `TermdLink.swift` spaces dials per host — four at once,
  then one every 100 ms — which holds the busiest 250 ms to six dials no
  matter how many panes there are. The backoff is jittered as well, so the
  same pane is not last in the queue every round. See milestone 4.
- **Server process count.** One `--stdio` bridge per pane is the price of the
  cheap path in milestone 4. Fine at six panes, questionable at sixty; that
  is exactly what the measurement was for, and it came back **1.34 MB per
  bridge** — 8 MB at six panes, 80 MB at sixty. The bytes are not the problem
  at any plausible size; the process count is what to watch.
- **Scope creep toward tmux**, again. The parent plan's risk list ends with
  this and it is still the one to watch: status bars, pane numbering overlays
  and copy-mode are all things we do not need because we have a real UI.

## What this does not make true

tmux runs in every terminal; this runs in ours. For someone who lives in one
terminal that is a fine trade — it is the same trade ghostty makes with its
splits — but the claim to make is "you do not need tmux **here**", never
"tmux is obsolete". The moment the pitch overreaches, the first tmux user to
try it finds no panes and no copy-mode and is right to say so.
