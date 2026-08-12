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
knowledge at all: no dependencies beyond libc and `forkpty`.

```bash
make                     # ./starling-termd
make static              # one binary to scp to a server with no toolchain
make test                # the protocol test — twelve checks, under two seconds
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
