# Guest seamless — M2, "a Windows app is a window"

Implementation plan, approved 2026-09-03. The three open decisions were
settled at approval; they are recorded at the foot with what each one costs.

M1 put the whole Windows desktop in one window
(`docs/plans/guest-display.md`). M2 takes it apart: each Windows app becomes
its own Starling window, with its own dock icon, its own place in Mission
Control and the spaces, while the guest's own desktop — wallpaper, taskbar —
is gone. The design is `docs/plans/windows-home-vm.md` §"Layer 3 — per-app
windows without RemoteApp"; this is the how.

## What the survey found, which changes the estimate

Three pieces already exist, and together they are most of the milestone. All
were read on 2026-09-03; file references are to that tree.

**The guest half of `list_windows` is written.** `Win32WindowManager`
(`sdk/Sources/FlutterWin32/Win32WindowManager.swift`, 251 lines) returns the
manageable top-levels **in z-order, topmost first** — the taskbar's own set —
each carrying handle, pid, title, `className`, `executablePath`, the DWM
extended frame with the invisible Windows 10+ resize border already removed,
monitor index, and minimised/maximised/foreground. `observe()` installs
WinEvent hooks and reports `added` / `removed` / `foregroundChanged` /
`titleChanged` / `moved` / `minimizedChanged`, with `moved` deliberately fired
on drag *end* rather than continuously. `activate`, `move`, `minimize`,
`maximize`, `restore` and `close` are all there.

That is the whole ops table's first row, plus the z-order mirroring the crop
approach needs, already built and shipped on the `winshell` branch. Its
identity rule is already ours: `appName` is the executable's base name, never
the title, with the same reasoning the desktop's `app_id` rule uses.

**The empty desktop is already proven.** `WinShellBar --session` is the
`Winlogon\Shell=` entry, with `SessionSlot.supervise` restarting a crashed
child and writing `Shell=explorer.exe` back after two crashes in a minute.
`docs/plans/winshell-shell-replacement.md` §Phase 5 records the soak: real
Winlogon logons in `win11-gpu`, startup replayed with explorer absent, a live
HKLM RunOnce consumed and not resurrected, the crash-loop bail exercised and
the machine left on stock explorer. Seamless mode wants exactly that — a
session with no wallpaper and no explorer taskbar — and it is done.

**The crop primitive exists.** `TextureWidget(sourceRect:)` does not sample a
sub-rect; it oversizes and offsets the *destination* so a parent `ClipRect`
cuts the result (`sdk/Sources/Flutter/Rendering/Texture.swift:277-300`). It
was built to crop CSD shadows out of Wayland buffers, and it is precisely the
per-window crop: to show guest rect (x, y, w, h), draw the whole scanout at
destination (−x, −y, guestW, guestH) and clip to the window. One dma-buf, N
windows, no extra copies, no engine change.

So M2 is mostly **transport and wiring**, not new capability.

## Shape

```
  GUEST (Windows)                          HOST (Starling)
  ───────────────                          ───────────────
  WinShellBar --session   ← Winlogon Shell=
    └ --bridge role                        GuestBridge (JSON lines)
        Win32WindowManager ──┐                  │
          windows() z-order  │  virtio-serial   │  GuestSeamless (Swift)
          observe() events   ├──────────────────┤    one WindowInfo per HWND
          activate/move/close│ org.starling.    │    all sharing M1's texture
        flwin32_apps.c ──────┘  agent.0         │    each a ClipRect + crop
          Start Menu catalog                    └─ z-order mirrored back
```

Decisions fixed here, each with the reason:

1. **Crop the scanout; do not capture per window.** The design offers both and
   calls crop the v1. It stays v1: zero extra copies, and M1's texture is
   already imported and live. Per-window WGC is the agent capture path (M3)
   and needs a bulk channel; it is not needed to make windows.
2. **virtio-serial, not vsock.** `org.starling.agent.0`, JSON lines, the same
   channel kind qemu-ga uses, with libvirt exposing the host end as a unix
   socket. virtio-win's `vioser` is mature and WHQL-signed; vsock for Windows
   is real but its presence on the stock virtio-win ISO is unconfirmed, and
   this milestone should not turn on that question.
3. **The helper is a ROLE of `WinShellBar`, not a new program.** It already
   owns the session slot, the dock, the launcher and the tray; the bridge is
   one more `--bridge` flag beside `--session`. A separate program would need
   its own autostart, its own supervisor and its own signing story, and would
   still have to talk to the same `Win32WindowManager`.
4. **Identity is `executablePath`, never the title.** The desktop's standing
   rule, and `Win32Window.appName` already implements it.
5. **One z-layer group.** Guest windows keep Windows' stacking among
   themselves and are mirrored back on focus (`activate`). Interleaving a
   Windows window between two Linux windows is the case this cannot do, and
   v1 does not offer it — the same compromise VirtualBox ships.

## Phase 1 — the channel

Host end first, because it is testable with no Windows code at all.

- Domain XML gains a second channel beside qemu-ga:
  `<channel type='unix'><target type='virtio' name='org.starling.agent.0'/></channel>`.
  libvirt then owns a unix socket under
  `/var/lib/libvirt/qemu/channel/target/domain-*/org.starling.agent.0`.
- `shell/Sources/DesktopShellApp/Guest/GuestBridge.swift`: connect, read JSON
  lines, write JSON lines, reconnect with backoff. The socket exists whether
  or not anything in the guest has opened its end, so "connected" means a
  `hello` was answered, not that `connect(2)` returned.
- Protocol: one JSON object per line, `{"op":…,"id":…}` / `{"id":…,"ok":…}`,
  plus unsolicited `{"event":…}`. Deliberately the same shape as
  `AgentBroker`'s socket, so the vocabulary is already familiar and M3 can
  proxy broker ops through it without translation.
- Prove it with a stub: `winrun.py` running a PowerShell that opens
  `\\.\Global\org.starling.agent.0` and writes a line. No helper build
  needed to know the pipe works.

**DONE 2026-09-03.** A line written inside Windows arrived on the host:
`GUEST SAID: {"event":"hello-from-guest","helper":"stub"}`. Three things the
guest side taught, so the helper does not rediscover them:

- .NET's `FileStream` refuses the port by path ("asked to open a device that
  was not a file"); it needs `CreateFileW` and a handle-based stream.
- PowerShell reads `0xC0000000` as a **negative Int32**, so the access mask
  must be written `[uint32]3221225472`.
- **A write with no host reader attached does not fail, it PENDS.** The first
  attempt looked like a broken port and was an absent listener. Both ends have
  to be up to test either.

And one host-side requirement: the socket is `libvirt-qemu:kvm` 0775 inside a
kvm-group directory, so reaching it needs the **`kvm`** group as well as
`libvirt`. Any machine that can use `/dev/kvm` already has it, but it is a
second requirement.

## Phase 2 — the bridge role in the guest

`WinShellBar --bridge` (composable with `--session`), a thin server over
`Win32WindowManager`:

| Op | Implementation |
|---|---|
| `list_windows` | `Win32WindowManager.windows()` — already z-ordered |
| events | `observe()` → one `{"event":"added"|"removed"|…}` line each |
| `activate` / `move` / `close` / `minimize` / `restore` | the same-named statics |
| `launch` | `ShellExecuteEx` in-session; Store apps via `IApplicationActivationManager` |
| `apps` | `flwin32_apps.c`'s Start Menu catalog, for Phase 5's records |

Bootstrapping it into a guest is the documented `schtasks /it` trick
(`docs/WINDOWS-VM.md`), once, after which `--session` starts it every logon.

**DONE 2026-09-03, as a C# prototype** —
`docs/windows-vm/starling-bridge.cs`, which answers `hello` and
`list_windows` over the real channel. It exists because building Swift for
Windows needs a toolchain neither the dev box nor the guest has, while every
Windows install ships `csc.exe` under `%WINDIR%\Microsoft.NET\Framework64`:
one file in, an exe out, nothing installed. It is the protocol reference and
the fixture that unblocks Phase 3 — **not** a second implementation to keep in
sync, and its filter is a transcription of `flwin32_wm.c`'s `is_manageable()`
for exactly that reason.

Verified against a live guest: two windows, topmost first, each with hwnd,
pid, title, class, exe path, DWM frame and the min/max/foreground flags.

Two traps, both of which make a working helper look broken:

- **`guest-exec` runs in session 0**, which has no interactive windows, so the
  helper enumerates *nothing* there. It has to go through `schtasks /it`, and
  an empty list from session 0 is indistinguishable from a broken filter.
- **`guest-exec` cannot carry a large payload on its command line.** A source
  file's worth of base64 fails with "Failed to execute helper program (Invalid
  argument)", which says nothing about size. `docs/windows-vm/winput.py`
  copies files through `guest-file-open`/`write`/`close` instead — the inverse
  of `winrun.py`, needing nothing installed in the guest.

The helper is **unelevated on purpose**: UIPI means it cannot see or drive
elevated windows, and an elevated helper driving the human's session is a
worse trade than a missing window. Elevated windows stay in the M1 console.

## Phase 3 — one window per HWND

`shell/Sources/DesktopShellApp/Guest/GuestSeamless.swift`, owned by the
`GuestSession` that already holds the texture:

- On `list_windows` / events, reconcile a `[HWND: String]` of shell window ids
  against the guest's list. `added` → `windowManager.addWindow` with M1's
  texture id and `wmClass` set from the app record; `removed` → close;
  `moved` → re-crop; `minimizedChanged` → minimise ours.
- The crop is the `sourceRect` + `ClipRect` idiom above, recomputed whenever
  the guest window moves or the scanout resizes. Guest pixels → logical is
  M1's content-rect ratio, not the dpi — the M1 bug that made clicks land
  elsewhere is the same arithmetic.
- Input already works: M1 maps pointer and keys into guest coordinates. A
  per-window Starling window adds its origin before that mapping.
- Focus mirrors both ways: our focus → `activate(hwnd)`; guest
  `foregroundChanged` → raise ours, without echoing back into a loop (the
  clipboard's `mine` guard is the precedent).
- **The M1 console stays.** `windows.app` still opens the whole desktop; it is
  the fallback whenever a window cannot be represented (elevated, or the
  helper is not running), and the only way to reach the guest's own UI.

## Phase 4 — the empty session — **DEFERRED TO M3**

Registering `WinShellBar --session` as the guest's shell is out of M2 by
decision. It costs less than it looks: the guest's taskbar and wallpaper stay
on the scanout, but nothing ever crops *them* into a window, so the human
never sees them. What is actually lost is tidiness inside the guest — windows
still avoid a taskbar that is not on screen, and a maximised guest window
stops short of it.

The rest of the milestone does not depend on this, which is why it separates
cleanly.

## Phase 5 — per-app registry records

The helper's `apps` op walks the Start Menu; the shell writes one record per
app into `/var/lib/starling/installed.d/`, exactly as `app-install` does for
host apps, and the shell's inotify watch lights them up with no relogin. Kind
and key naming is the open decision below.

## Phase 6 — DPI and resize

Run the guest at the host output's logical size with Windows' scaling at the
host's scale, or every crop lands at the wrong size. M1's `set_ui_size`
already drives the first half; the second is a one-time guest setting.

## Phase 7 — tests and docs

`test/functional.py` gains a seamless check beside the M1 one (skipped without
a domain): launch an app through the bridge, assert a Starling window appears
whose `wmClass` is the app's, close it, assert it goes. `docs/WINDOWS-VM.md`
gains the bridge bootstrap.

## Traps

- **Minimised windows stop producing frames**, so a crop of one is stale
  pixels. Minimise ours when the guest's minimises and do not paint.
- **Cloaked windows are not hidden windows.** `DWMWA_CLOAKED` covers UWP
  suspension and virtual-desktop switches; `Win32WindowManager` already
  filters them, and a naive `IsWindowVisible` would show ghosts.
- **`moved` fires on drag END.** Continuous motion is not reported, by design
  — a window dragged inside the guest will jump, not glide, and chasing that
  with a poll would cost a `windows()` walk per frame (single-digit ms).
- **Two overlapping guest windows show WINDOWS' stacking**, because the crop
  shows whatever the guest drew at that rect. This is the known v1 limit.
- **One input queue, one foreground window.** `SendInput` lands wherever the
  guest's foreground is. This is why M3's agent story needs its own answer
  and why v1 mirrors focus rather than pretending windows are independent.
- **The helper cannot see elevated windows** (UIPI). Not a bug to fix; a
  documented boundary with the M1 console as the fallback.

## Decisions, settled at approval

- **`Kind=guest-app`**, a new kind carrying `Domain=` plus `Exec=` (the AUMID
  or exe path). `AppRegistry.probe` and the launch arm both switch
  exhaustively, so the compiler finds every site that has to learn about it,
  and a console and an app genuinely launch differently.
- **Replacing the guest's shell is deferred to M3** (Phase 4 above).
- **The console and seamless mode are mutually exclusive.** Opening one closes
  the other; the console's dock menu carries the switch. Two windows showing
  the same pixels is the confusion this avoids.

  What it costs, stated plainly because it is a real loss: **anything a crop
  cannot represent has no fallback while seamless is on.** Elevated windows
  are invisible to an unelevated helper (UIPI), and so is the guest's own UI —
  its Start menu, its settings, a UAC prompt. The switch back to the console
  is the answer to all of them, and it has to be reachable from the dock menu
  at all times, not from inside a guest window. A UAC prompt appearing while
  seamless is on is the sharpest case: the guest is waiting for a click on a
  window we are not showing. Phase 3 must detect "the guest has a window we
  cannot represent" and say so, rather than looking hung.
