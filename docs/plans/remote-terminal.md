# Remote terminal — the session lives on the server, the emulator lives here

The workflow this exists for: ssh to a machine, start something long, lose
the network, come back an hour later on a different network, and find the
work where you left it. Today that means tmux, and tmux is the wrong shape
for a client that already has an emulator.

## Why not tmux (the structural reason, not the taste one)

tmux runs an emulator on the server, renders a screen, and then **re-encodes
that screen as escape sequences** for the local terminal, which parses them
again. Everything people dislike follows from that one decision:

- **Two emulators must agree, and they don't.** Wide characters, grapheme
  clusters, colour handling, mouse modes — every disagreement is a rendering
  bug. Our core sweeps `ucs-detect` at zero errors where the ghostty nightly
  scores 33; whatever is on the far end of an ssh pipe will not match it.
- **Every feature has to be a keystroke.** The only channel is a terminal
  protocol, so multiplexing needs a prefix key (`Ctrl-B`), selection needs
  copy-mode, and history needs tmux's scrollback instead of the one your
  terminal already has.
- **Attached clients fight over size.** The window shrinks to the smallest.
- **A repaint costs a screenful of escapes**, on the link with the latency.

## The shape instead: ship bytes, not screens

The client owns the emulator (`CTerminalCore`, in every Starling terminal),
so the server never renders anything:

```
  shell ──pty──► termd ──ring buffer──► framed byte stream ──ssh──► TerminalSession.feed()
   ▲                                                                      │
   └────────────────────────── INPUT frames ◄─────────────────────────────┘
```

- **The wire format is the pty byte stream.** No re-encoding, so no second
  emulator to disagree with, and no repaint amplification.
- **Reconnect is a byte offset.** The daemon numbers every byte it has ever
  read from a session; a client reattaches with "I have through N" and gets
  the tail. Same session, same scrollback, mid-`top` and all.
- **Multiplexing is client-side UI.** Tabs, splits, the floating workspace,
  selection, search and scrollback are widgets here, not remote redraws.
  There is no prefix key to learn because there is nothing to prefix.
- **Resize is per client.** Two attached clients do not shrink each other;
  the session is resized by whoever is driving it.

**Deployability is the quiet part.** `CTerminalCore` is ~1,500 lines of C
including only `stdio/stdlib/string`. The daemon around it is a single
static binary to `scp` — no Swift, no Flutter, no runtime on the server.

## Prior art, and what we take from each

| | what it gets right | what it leaves |
|---|---|---|
| tmux / screen | ubiquitous, persistent | re-renders through a terminal protocol |
| mosh | roaming, local echo prediction | no detach/reattach, one session |
| abduco / dtach | tiny, detach-only | no reconnect story, no multiplexing |
| Eternal Terminal | survives disconnects | delegates everything else to tmux |
| wezterm mux | native client, own protocol | client and server are one codebase, one language |

Ours is wezterm-shaped, with the emulator core shared byte-for-byte between
the ends and a real widget toolkit on the client.

## Protocol v0

Length-prefixed frames, little-endian, over whatever byte pipe the transport
provides (v0: an ssh exec channel's stdin/stdout).

    struct frame { u8 type; u8 flags; u16 _pad; u32 len; u8 payload[len]; }

| type | payload | direction |
|---|---|---|
| `HELLO` | version u16, client name | → |
| `HELLO_OK` | version u16, session count u16 | ← |
| `LIST` | — | → |
| `LIST_REPLY` | n × { id u32, cols u16, rows u16, alive u8, title } | ← |
| `OPEN` | cols u16, rows u16, command (may be empty) | → |
| `ATTACH` | id u32, from_seq u64, cols u16, rows u16 | → |
| `ATTACHED` | id u32, from_seq u64 (what the server will actually send) | ← |
| `DATA` | seq u64 (offset of the first byte), bytes | ← |
| `INPUT` | bytes | → |
| `RESIZE` | cols u16, rows u16 | → |
| `ACK` | seq u64 (consumed through) | → |
| `EXIT` | id u32, status i32 | ← |
| `DETACH` | — | → |
| `ERROR` | code u16, message | ← |

**Sequence numbers are byte offsets**, counted from the first byte the
session ever produced. A session keeps a ring of the last N MB (default 8);
`ATTACH` with a `from_seq` older than the ring gets the oldest byte the ring
still holds, and `ATTACHED` says so — the screen rebuilds by replay, and only
scrollback older than the ring is lost. **v0 has no snapshot frame on
purpose**: replay is exactly correct when the ring covers the gap, and it
needs no new core API.

## Milestones (each lands green: `test/run.sh` plus its own test)

1. **`termd/`, the daemon. — DONE** C, POSIX, one static binary. Sessions on ptys,
   per-session ring, unix socket in `$XDG_RUNTIME_DIR` mode 0600, `poll()`
   loop, `--serve` / `--stdio` / `--list`. `--stdio` is what ssh runs: it
   bridges the socket to stdin/stdout and starts the daemon if absent.
   Its test drives the protocol over a socketpair: open a session, write,
   detach, reattach at an offset, and compare bytes exactly.
2. **The client transport. — DONE**, as `RemoteTerminal` in the sdk rather
   than in the example first: the API is dictated by the protocol, not
   discovered by the UI, and there is exactly one consumer, so the detour
   through the example would have proved nothing. `remote:host`,
   `remote:host/12` and `remote:host -- command` in the launcher spawn
   `ssh host starling-termd --stdio` and feed a headless `TerminalSession`.
   The widget, the panes and the launcher are unchanged; `TerminalSession`
   gained one hook (`onResize`) so a view's resize becomes a RESIZE frame
   when there is no local PTY.
3. **Reconnect as a first-class state. — DONE.** Backoff retry (0.5s to 8s),
   a `[link lost — reconnecting…]` line in the pane itself, resume from the
   consumed offset, PING/PONG every 10s with a 30s deadline so a half-open
   link is noticed rather than waited on, and the link state in the pane's
   title. Verified live: a tick loop at 0.4s, the transport killed mid-run,
   and the pane resumed `tick-11 → [link lost] → tick-12` — no gap, no
   repeat, same shell.
4. **`SNAPSHOT`** — a frame plus the core API it needs
   (`starling_term_snapshot` / `_restore`) so a long-detached session
   restores its screen instantly instead of replaying. **Deferred, with a
   number:** replay runs at the core's parse rate (30+ MB/s measured), so
   the whole 8 MB ring costs ~0.3 s — the benefit is real only for a much
   larger ring, and the cost is that the daemon starts carrying terminal
   state it currently does not have at all. Revisit when someone wants
   history measured in hundreds of megabytes.
5. **Later, separable:** several clients attached to one session, mosh-style
   local echo prediction, and a UDP path for roaming.

## Design decisions to hold

1. **The server never renders.** If a future feature needs the server to
   know what is on screen (a title, a "did anything change" poll), it runs
   the same C core headlessly — it still does not re-encode.
2. **SSH is the transport in v0.** No new port, no new auth, jump hosts and
   agent forwarding work, and reconnect is a fresh exec channel. A native
   UDP transport comes later and must not become the only path.
3. **The daemon is per-user and local-socket only.** No network listener;
   authentication is ssh's job. Socket 0600 under `$XDG_RUNTIME_DIR`.
4. **Byte offsets, not message counts.** Everything resumes on a `u64` byte
   offset, which is what makes replay exact and the ring easy to reason about.
5. **The client is not special.** The daemon must be usable from a plain
   `nc`-style pipe for debugging, and its test does exactly that.

## Risks

- **Ring sizing and flow control.** A detached session that floods (a build,
  `yes`) overruns the ring. v0 accepts loss of the oldest bytes; the
  snapshot in milestone 4 is what makes that invisible.
- **Version skew** between a server binary and a newer client core. The
  `HELLO` version handshake gates the protocol; snapshots (v1) must carry a
  core version and fall back to replay when it differs.
- **Half-open links.** TCP will happily wait forever; the heartbeat in
  milestone 3 is what turns that into a reconnect.
- **Scope creep toward tmux.** Anything that wants a prefix key belongs in
  the client's UI, not in the protocol.
