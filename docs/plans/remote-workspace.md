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

The blob is capped (16 KB is generous for a layout tree) and stored per
workspace, not per session, so it survives every session in it dying.

## Milestones (each lands green: `test/run.sh` plus its own test)

1. **Splits in the shipped terminal.** Lift the split tree out of
   `sdk/Examples/TerminalTiling` into the app: a pane tree, draggable seams,
   focus follows click. Local only, no termd, no protocol. Ships useful on
   its own — this is the milestone that makes the terminal competitive with
   ghostty's splits regardless of the rest.
2. **Workspaces in the daemon.** The four frames above plus `OPEN`'s `ws_id`.
   Test drives it over a socketpair the way the existing protocol test does:
   create a workspace, open three sessions into it, set a blob, drop the
   connection, reconnect, list, read the blob back byte-identical, and check
   that killing one session leaves the workspace and the blob intact.
3. **Attach a workspace, not a session.** `remote:host/ws:dev` in the
   launcher: one command, N attaches, layout restored from the blob, focus
   where it was. The client writes the blob on every layout change, debounced.
   This is the milestone where a tmux user gets their workflow back.
4. **Several sessions over one connection — measure before building.** The
   cheap path needs no protocol change: ssh already multiplexes channels, so
   N attaches over one `ControlMaster` is N streams, one authentication, one
   TCP connection, today. The expensive path is a session id on every `DATA`
   and `INPUT` frame so one client connection carries all panes. Do the cheap
   one, measure per-channel cost (a `--stdio` bridge process per pane on the
   server, and reconnect latency for N panes), and only pay for in-protocol
   multiplexing if the numbers say so. Record the number either way, the way
   milestone 4 of the parent plan recorded its 0.3 s.
5. **Later, separable:** detach/reattach of a whole workspace as one
   operation, workspace names in `--list`, and sharing a workspace between two
   clients (the daemon already permits two clients on one session — `ATTACH`
   does not reject a second — so this is client work, not protocol).

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

## Risks

- **Layout blob skew** between client versions. Mitigated by decision 5, and
  the test in milestone 2 should include reading a blob whose version byte is
  from the future.
- **N panes, N reconnect storms.** A dropped link with six panes means six
  backoff timers. They should share one, or the far end sees a thundering
  herd on every tunnel bounce.
- **Server process count.** One `--stdio` bridge per pane is the price of the
  cheap path in milestone 4. Fine at six panes, questionable at sixty; that
  is exactly what the measurement is for.
- **Scope creep toward tmux**, again. The parent plan's risk list ends with
  this and it is still the one to watch: status bars, pane numbering overlays
  and copy-mode are all things we do not need because we have a real UI.

## What this does not make true

tmux runs in every terminal; this runs in ours. For someone who lives in one
terminal that is a fine trade — it is the same trade ghostty makes with its
splits — but the claim to make is "you do not need tmux **here**", never
"tmux is obsolete". The moment the pitch overreaches, the first tmux user to
try it finds no panes and no copy-mode and is right to say so.
