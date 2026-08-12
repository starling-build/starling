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
make test                # the protocol test — twelve checks, under two seconds
./test-termd.py --stdio  # the same checks through a --stdio bridge

.\build-windows.ps1      # Windows: starling-termd.exe (clang, no make)
python .\test-termd.py   # the same twelve, over --stdio automatically
```

```bash
starling-termd --serve   # the daemon (idempotent: exits if one is running)
starling-termd --stdio   # bridge stdin/stdout to it — what ssh runs
starling-termd --list    # sessions, for humans
```

The socket is `$STARLING_TERMD_SOCKET`, else
`$XDG_RUNTIME_DIR/starling-termd.sock`, mode 0600. There is no network
listener: authentication is ssh's job.

Wire format in [protocol.h](protocol.h). Sequence numbers are **byte
offsets** from the first byte a session ever produced, which is what makes
a reattach exact; a session keeps the last 8 MB, and an `ATTACH` older than
that is answered with the oldest byte still held (`ATTACHED` says where it
actually resumed, so a gap is visible rather than silent).

## From the client

Any Starling terminal can attach. In the workspace example, type a command
of this shape into a new pane:

```
remote:prod-1              # open (or re-open) a session on that ssh host
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
