# Headless desktop

**Question:** is there a headless desktop, controlled only by agents? Can
existing GNOME do it?

**Answer:** yes, Starling already has one. `DesktopShellApp --rdp` ("display
mode", see `rdp-wsl.md`) runs the whole desktop with no display, no seat, no
libinput and no root. This work added a private control socket for agents,
a no-root driver, a smoke test, and measurements. GNOME 50 can also do it,
but it is a much heavier stack and was not measured here (web-sourced only).

## How it works

- The engine runs on `kOpenGL` with a surfaceless EGL context
  (`shell/Sources/RdpServer/rdp_egl.c`), rendering into an off-screen buffer.
- Pixels are read back with `glReadPixels` for screenshots and, optionally,
  the RDP encoder for a human viewer.
- Input is synthesised into the engine through the same path RDP uses.
- Wayland clients and the portal work. X11 is excluded.
- Needs only the stock `libflutter_engine.so`. **No engine change.**
- Needs no GPU. Tested on Mesa llvmpipe (software GL) on a 192-thread box.

## Operator socket (security)

`$XDG_RUNTIME_DIR/starling-operator.sock` (override `STARLING_OPERATOR_SOCK`).
It controls the **whole** desktop, so:

1. Unix socket only. **Never TCP.**
2. Lives under `$XDG_RUNTIME_DIR`, which is mode 0700 and per user.
3. Socket file is mode 0600 (created under umask 0177, then chmod).
4. On every connection the shell reads `SO_PEERCRED` and **closes the
   connection if the peer uid is not the shell's own uid**, before reading
   a byte.
5. It is for the session's owner only. Sandboxed agents must NOT be handed
   this socket. They use the Agent Broker (`starling-agent.sock`), which is
   scoped to windows the agent launched.
6. Anything remote goes through a small external gateway (see below), so
   network code stays out of the shell.

`test/headless.sh` checks the mode and owner. The foreign-uid rejection is
not tested (needs a second user).

Protocol: JSON lines. Ops: hello, screen, shot, windows, launch, move,
down/up, click, dblclick, drag, scroll, key/keydown/keyup, type, stats, quit.
Coordinates are logical pixels. Client: `build/headless-drive.py`.

## Measurements

Box: 192 threads, no GPU, load average 85–150 from other sessions, so
wall-clock numbers are noisy. Workload: Settings and Terminal open, the
Terminal window dragged back and forth. `LP` is llvmpipe threads.

| Config | Drag fps | Frame p50 / p95 | Cores | CPU per frame |
|---|---|---|---|---|
| 1080p, LP=1 | 3.5 | 304 / 313 ms | 1.0 | 301 ms |
| 1080p, LP=4 | 8.7 | 105 / 155 ms | 3.3 | 373 ms |
| 1080p, LP=16 | 23.0 | 39 / 71 ms | 9.2 | 399 ms |
| 4K at scale 2, LP=4 | 4.1 | 228 / 344 ms | 3.8 | 935 ms |
| 4K at scale 2, LP=16 | 13.3 | 72 / 82 ms | 12.4 | 934 ms |
| 4K at scale 1, LP=16 | 12.9 | 75 / 86 ms | 12.6 | 976 ms |

- Cost per frame is about 0.3–0.4 CPU-seconds at 1080p and about 0.95 at
  4K. It scales with pixels, not threads. More llvmpipe threads buy speed,
  not efficiency.
- Every present re-renders the whole screen (no partial repaint).
- **Idle is free** until something animates. The bare desktop presents no
  frames. A blinking Terminal cursor used to cause about 3.4 presents/s,
  costing 0.6–2.9 cores. Headless mode now sets `STARLING_CURSOR_BLINK=0`
  (inherited by child apps) and an idle desktop with Terminal open measures
  0 presents and about 1 ms CPU in 10 s.
- The screensaver shader stalls llvmpipe for seconds per frame. Headless mode
  turns the screensaver off by default.
- Screenshot: readback 60–115 ms, PNG encode about 300 ms under load; total
  roughly 170–400 ms at 1080p.

### Side-by-side desktops (1080p, LP=2 each)

| Desktops | Socket ready | First shot | Memory |
|---|---|---|---|
| 8 (+Settings) | 0.5 s | 167–270 ms | 3.7 GB |
| 32 (+Settings) | 0.6 s | 257–316 ms | 14 GB |
| 96 (no apps) | 1.3 s | 306–445 ms | 25 GB |

About 250 MB per bare desktop, about 210 MB more per Settings window. Idle
CPU is negligible (0.01 cores for 96). **Memory and per-frame CPU are the
limits.** A few hundred idle desktops fit in 499 GB. Animating desktops share
roughly 150–200 full 1080p frames per second across 192 threads.

Not measured: the RDP path (no RDP client installed here), and any GPU.

## Recommended architecture

1. One shell per desktop, each with its own `XDG_RUNTIME_DIR`.
2. Agents drive it through the operator socket (owner) or the broker
   (sandboxed).
3. Optional RDP for a human to watch.
4. A small gateway or MCP server outside the shell bridges the unix socket
   to whatever the agents speak. All network code lives there.
5. A systemd user template unit `starling-headless@NAME`.
6. Launcher defaults: no RDP listener, screensaver off, cursor blink off,
   small `LP_NUM_THREADS` (default is one thread per core, hundreds).

## Engine needs

None for the prototype. Wanted later:
- Partial repaint / damage tracking (`engine-partial-repaint.md`). This is
  the biggest win: it makes every frame cheaper.
- A frame-pacing hook, so idle animation can be throttled.

## Plan

1. Done: operator socket, driver, smoke test, measurements.
2. Done: cursor-blink suppression in headless mode.
3. Semantic tree and `perform_action` exposed through the operator socket.
4. `starling-headless@` unit, plus a gateway/MCP bridge.
5. Multi-output, and the DMA-BUF versus CPU path for child apps (with no
   `/dev/dri` they use the CPU path; with it, kms_swrast).
6. Test with a real RDP client.

## GNOME 50 comparison (web-sourced, not installed, not measured)

- mutter has a `--headless` backend. GNOME 50 added virtual monitors and
  monitor-mode emulation, and `gnome-headless-session` to launch a session
  with no monitor.
- Control: `org.gnome.Mutter.RemoteDesktop` and `org.gnome.Mutter.ScreenCast`
  (`RecordVirtual`) over D-Bus, pixels over PipeWire, input over libei.
- `gnome-remote-desktop` serves RDP (FreeRDP) and VNC. Headless single-user
  setup uses `grdctl --headless`; multi-user remote login goes through GDM
  and a per-user compositor.
- A headful session cannot be shared with a headless one. Mutter 50.1 has a
  reported crash when a Qt client asks a headless seat for a keyboard.
- Cost: a full gnome-shell (JavaScript), mutter, PipeWire, WirePlumber and
  a D-Bus stack per session. Starling's headless shell is one process with
  no such stack.
- Unlike Starling, GNOME has no agent-oriented control API. You assemble one
  from RemoteDesktop, ScreenCast and libei.

Verdict: GNOME can do it and is the better choice if the goal is running
unmodified GNOME apps with the stock desktop. For agent control at density,
Starling's own headless mode is simpler and lighter.
