# starling-termd

Terminal sessions that outlive their client — the server half of
[docs/plans/remote-terminal.md](../docs/plans/remote-terminal.md).

The daemon owns ptys. What it reads from one is appended to that session's
ring buffer and numbered by byte offset; attached clients are sent the tail.
A client that vanishes changes nothing — the shell keeps running, and the
next `ATTACH` resumes at whatever offset that client had reached.

**It never renders a screen.** The wire format is the pty byte stream, so
there is no second emulator here to disagree with the client's. That is what
separates this from tmux, and it is why the daemon needs no terminal
knowledge at all: no dependencies beyond libc, a pty and threads.

Linux and Windows both. `termd.c` is the same code on each and holds no
`#ifdef`; everything that differs is `plat.h` with `plat_posix.c` (forkpty,
AF_UNIX, pthreads) and `plat_win32.c` (ConPTY, AF_UNIX over `afunix.h`,
CRITICAL_SECTION) behind it. Read the header before changing either: it
explains why every session's pty gets its own reader thread rather than
joining the socket wait, which is a Windows constraint the POSIX build
adopts so there is only one control flow to reason about.

```bash
make                     # ./starling-termd
make static              # one binary to scp to a server with no toolchain
make test                # the protocol test — twenty-seven checks, a few seconds
./test-termd.py --stdio  # the same checks through a --stdio bridge

.\build-windows.ps1      # Windows: starling-termd.exe (clang, no make)
python .\test-termd.py   # the same checks, over --stdio automatically
```

```bash
starling-termd "iOS dev" # attach to that session, creating it if the name is new
starling-termd --serve   # the daemon (idempotent: exits if one is running)
starling-termd --stdio   # bridge stdin/stdout to it — what ssh runs
starling-termd --list    # sessions, for humans
```

The socket is `$STARLING_TERMD_SOCKET`, else
`$XDG_RUNTIME_DIR/starling-termd.sock`, mode 0600. There is no network
listener: authentication is ssh's job.

A session's environment is the daemon's, with `TERM=xterm-256color`,
`COLORTERM=truecolor`, and the terminal-multiplexer markers removed —
`TMUX`, `TMUX_PANE`, `TERM_PROGRAM`, `TERM_PROGRAM_VERSION`, `STY`, `WINDOW`.
The daemon outlives the shell that started it, so without that scrub a
daemon started from inside tmux hands every session it ever forks a `TMUX`
and a `TERM_PROGRAM=tmux`; programs that adapt their drawing to their host
believe them and render for a multiplexer that is not there, which looks
like a bug in the terminal rather than in the server. Setting `TERM` alone
does not cover it.

Wire format in [protocol.h](protocol.h). Sequence numbers are **byte
offsets** from the first byte a session ever produced, which is what makes
a reattach exact; a session keeps the last 8 MB, and an `ATTACH` older than
that is answered with the oldest byte still held (`ATTACHED` says where it
actually resumed, so a gap is visible rather than silent).

## Names

A session can carry a name — `iOS dev`, not `12` — and that is the handle
worth typing:

```
$ starling-termd --list
session 1   iOS dev              80x24  running  48213 bytes
session 2   prod tail            80x24  running  9911 bytes
session 3   -                    80x24  running  204 bytes
```

**A named `OPEN` is attach-or-create.** Asking for a name that already
exists resumes that shell — from the oldest byte still held, so the screen
comes back — rather than forking a second one beside it, and the command in
that `OPEN` is ignored. One request means "get me into iOS dev", whether or
not it is the first time, which is what lets a client reconnect knowing
nothing but the name.

That matters because **ids do not survive the daemon**: a restarted
`starling-termd` numbers from 1 again, so a stale id either misses or lands
on a different session. A name is what the person typed and can type again,
so the client keeps it across reconnects and re-opens by name whenever it
has no id.

Names are unique among live sessions, at most 63 bytes, and the daemon
treats them as opaque text apart from dropping control characters and
trimming edge whitespace — a name with an escape sequence in it would
repaint the screen of whoever ran `--list`, and `"iOS dev "` pasted with a
trailing space has to be the same handle as `"iOS dev"` or it silently opens
a second session. Sessions opened without a name are addressed by id, as
before.

## Attaching from a shell

`starling-termd "iOS dev"` puts the session on the terminal you are already
sitting in — over ssh, that means your own terminal at the far end of the
link:

```bash
ssh box                     # or run it locally
starling-termd "iOS dev"    # attach, creating the session if the name is new
starling-termd 12           # all-digits is an id, and re-attaches exactly
```

**It renders nothing.** DATA payloads go to stdout verbatim and whatever
emulator you are looking at does the drawing — which is why it needs no
terminfo, no capability negotiation, and no agreement with the far side
about what a screen is. What it does instead is tty plumbing: raw mode so
keys travel byte-exact (including `OPOST` off, without which a tunnelled
session prints a staircase), the window size on a RESIZE, and one stolen key
so there is a way back out.

**`^] d` detaches** and leaves the session running. A byte-exact tunnel has
no spare keystroke by definition, so one byte has to be ours: `^]` is
telnet's old escape and essentially nothing binds it today. Deliberately not
tmux's `^b`, which is backward-char in readline and page-up in vim — and
which would collide in exactly the case this exists for, attaching to a box
that already runs tmux. `^] ^]` sends a literal one, and any other key after
it passes both bytes through rather than eating a keystroke.
`$STARLING_TERMD_PREFIX` picks another (`C-b`, `^a`, or a single literal
character) for fingers that already know a different multiplexer.

Killing the connection detaches too — that is the whole point of the daemon,
so a dropped ssh link costs nothing.

The window is resized by polling `TIOCGWINSZ`, not by handling `SIGWINCH`: an
ioctl every 250 ms costs nothing, a resize is a human-speed event, and it
keeps one control flow across both platforms, since Windows has no such
signal. Note that resize is **last-writer-wins** across clients — two
terminals attached at different sizes will fight, and the loser sees a
layout drawn for someone else's window. Per-client sizing is the thing that
would require an emulator here, and not having one is the trade.

## From the client

Any Starling terminal can attach. In the workspace example, type a command
of this shape into a new pane:

```
remote:prod-1              # open (or re-open) a session on that ssh host
remote:prod-1/iOS dev      # open "iOS dev" there, or resume it if it exists
remote:prod-1/12           # re-attach session 12 specifically
remote:prod-1 -- htop      # open one that runs a command instead of a shell
remote:local               # the daemon on this machine, no ssh in between
```

`RemoteTerminal` (in the sdk) spawns `ssh <host> starling-termd --stdio`,
speaks the protocol above, and feeds a headless `TerminalSession`. The
widget above it is unchanged — same grid, same keys, same resize.

`$STARLING_SSH` overrides the ssh binary (a wrapper, a jump script) and
`$STARLING_TERMD` the server-side path, for sites where neither is on the
default PATH.

If the link drops, the pane says so in its own scrollback and reconnects
with backoff, resuming at the byte offset it had reached:

```
tick-11
[link lost — reconnecting…]
tick-12
```
