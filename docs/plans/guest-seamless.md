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

**BUILT 2026-09-04** — `shell/Sources/DesktopShellApp/Guest/GuestSeamless.swift`,
owned by `GuestSession` as its `.seamless` mode; the dock menu's "Show Apps as
Windows" / "Show Windows Desktop" switch it, `STARLING_GUEST_SEAMLESS=1` starts
a launch in it, and the broker's `guest_state` / `guest_mode` / `guest_launch`
drive it from the functional tier. What the survey's crop primitive turned out
to need, and what the reconcile does:

- **`TextureWidget(sourceRect:)` was the wrong primitive after all.** It is a
  fixed paint rect in logical pixels, and Mission Control and the workspace
  panes draw the same window into a *scaled* box — a crop fixed in logical
  units shows the wrong region there. The SDK gained `crop:` (unit texture
  coordinates, scaled to the box); `WindowInfo.textureCrop` carries it, and
  ONE painter — `windowTextureContent` in `DesktopWindow.swift` — is used by
  the window, the exposé card and the pane, so the crop cannot be honoured
  in one and not another. It also folds `flipTextureY` into the crop: the
  flip is a `Transform` about the box's centre, which mirrors the oversized
  quad, so a bottom-up buffer's crop has to be mirrored first.
- **The helper's events carry the whole list, not deltas.** The C# fixture
  polls (100 ms) and sends `{"event":"windows",…}` whenever the serialised
  list changes; the shell reconciles against it — add, retitle, re-crop,
  minimise/restore, remove, and raise the guest's foreground. Idempotent, so
  it does not matter whether a WinEvent hook or a poll produced the list —
  the real helper can send the same thing from `observe()`.
- **Both echo guards.** Our focus → `activate`, the guest's foreground →
  `bringToFront`; a reconcile marks itself `applying` so the focus and
  minimise callbacks it fires are not sent back, and a raise the guest asked
  for is remembered (`expectFocus`) so our own focus change for it is not
  either. Same shape as the clipboard's `mine`.
- **Resize is a request, and the guest's answer wins.** Ours → `move` with
  the same origin and the new size (debounced during a drag); the rect
  follows only what the next list reports, exactly as M1's `noteGuestResized`,
  with the request forgotten after a second so a guest that refuses does not
  freeze the window.
- **Unrepresentable foregrounds are reported.** The list carries `fg` even
  when it is not in the list, plus `fgTitle` when it is not furniture; the
  shell logs it and posts one notification per such window — after 1.5 s,
  because a launching app is foreground for a tick before it is listable
  (Calculator, every time) and that is not a UAC prompt.

**VERIFIED 2026-09-04** on the dev box (`win11-dbus`, stock QEMU, the C#
helper, the shell unprivileged at 1.5x on the 4K output): switching from
the console closes it and the guest re-renders at 3840x2160; Notepad and
Calculator each became a desktop window cropped pixel-exact from the one
scanout, stacked as the guest stacks them; a window dragged on our desktop
kept its crop; clicking a title bar raised the guest's window too, and
typing then landed in it; an edge drag resized the guest's window and ours
followed the size it actually took (1202 → 892 guest px); the yellow button
minimised it in the guest, relaunching restored it, the red button closed
Registry Editor and Calculator through `WM_CLOSE`; a window closed inside the
guest vanished from the desktop; with no helper the switch fell back to the
console after 15 s with a notice. `test/functional.py --only seamless`
passes (4.6 s), the M1 check still passes, and the fast tier is green.
Not seen live: the "foreground we cannot show" notice — the guest's
Administrator auto-elevates, so `regedit` never raised a UAC prompt.

Four things the live run taught, none visible from the code:

- **A write with no host attached does not pend for .NET, it throws.** The
  Phase 1 stub made it look like a pend; a synchronous `FileStream` turns
  the port's `ERROR_IO_PENDING` into an `IOException`, and the helper died
  on its `helper-up` line every time it started before the desktop
  connected — the normal order at logon. The scheduled task's last result,
  `-532462766` (`0xE0434352`, a CLR unhandled exception), is the only
  trace. The bytes stay in the stream's buffer, so catching it loses
  nothing; they go out with the next write.
- **One synchronous handle serialises the reader and the writer.** With the
  main thread blocked in `ReadLine`, the observer's `WriteFile` queued
  behind it and completed only when the host next sent something — so
  every event after the first arrived exactly when the desktop happened to
  ask for a list, which looks like "events are lost". The port is opened
  `FILE_FLAG_OVERLAPPED` now, the stream unbuffered. The real helper has the
  same problem the moment its hooks write from the UI thread.
- **`SetForegroundWindow` is refused from a windowless helper**, even
  through `AttachThreadInput`: WinShellBar gets away with the attach alone
  because it is a window the person just clicked. Measured: Notepad behind
  Calculator, `activate` → `ok:false`, foreground unchanged, and the
  keystrokes meant for Notepad went into Calculator. `SwitchToThisWindow`
  (Alt+Tab's path) is not subject to the lock; an Alt tap is the fallback.
- **A minimised UWP window is cloaked**, so `is_manageable()` drops it and
  the desktop window goes away rather than minimising — Calculator's yellow
  button removes it; relaunching brings it back as a new HWND. Windows'
  own taskbar keeps a button for it, so the filter (the C bridge's too)
  should treat cloaked-and-iconic as minimised rather than absent. Left as
  is here, noted for the real helper.

And two that are not bugs: stale pixels below a window that just animated
(a duplicated row of Calculator keys) are the guest scanout's own damage
tracking — the console shows the same — and `shell-drive shot` converts
whichever output's dump lands first, so on a two-output box a 4K capture
has to be taken from the leftover dump.

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

**BUILT 2026-09-04**, with two departures from the paragraph above that the
code forced:

- **Not `installed.d`, and not looked up by catalog id.** The registry loads
  the shipped catalog and looks each id up in `installed.d`; a record with no
  catalog entry was never loaded at all. And `installed.d` is root's —
  `app-install` writes it under pkexec — while the shell runs as the session
  user. So `Kind=guest-app` records live in a per-user directory,
  `AppRegistry.guestAppsDir` (`~/.local/share/starling/guest-apps.d`,
  `$STARLING_GUEST_APP_RECORDS` to override), which the registry enumerates
  as a second catalog — self-describing records, installed by definition, a
  catalog id winning any collision — and watches like the other two. The
  App Store never sees them: it lists only records with an install recipe.
- **The AppsFolder, not the Start Menu.** `shell:AppsFolder` is what
  Explorer's Start enumerates, packaged apps included, and every entry is
  launchable as `shell:AppsFolder\<id>` whether it is an AppUserModelID, a
  known-folder-relative path or a registered label. The C# helper reads it
  through the Shell COM object (interactive session only — from session 0
  the folder is empty) and hands over each app's icon as the shell draws it
  for Start, 48px, via `IShellItemImageFactory` — the one icon source that
  serves packaged and classic apps alike. 74 apps with icons in 4.7 s on the
  dev guest.

Identity follows the desktop's standing rule. A window's `aumid` (the
`window_app_id` transcription: the process first, the frame's property store
for the CoreWindow generation) matches a packaged record's launch id; a
classic window's executable matches the record's known-folder-expanded path;
anything else stays under the VM's own record. `GuestAppRecords` keeps that
table and writes the records — temp file and `rename(2)`, because
Foundation's `replaceItemAt` refuses a destination that does not exist yet,
which is every first write, and that cost one round: 74 icons on disk and not
one record.

Launching is the launch arm's new `Kind=guest-app` case: the VM's session is
opened in seamless mode if there is none, switched to it if it shows the
console, and the launch is queued on `whenSeamlessReady` until the helper
answers. The dock's Quit needs nothing new — it closes each owned window,
which is a `close` to the guest.

**VERIFIED 2026-09-04:** 74 records with icons appeared in the launcher
within seconds of the switch; "notepad" in the launcher's search offered
`guest-win11-dbus-windowsnotepad`, Enter started Notepad inside the VM, and
its window was counted as that record's (the dock grew a Notepad icon with
the guest's own artwork and a running dot, not Windows'). The seamless
functional check covers the launcher launch and passes back to back; the M1
check and the registry unit test pass.

It found one crash that was not Phase 5's: `_buildDock` read
`_dockDisplayApps` twice in one build — once to size slots, once to draw
them — and a second guest app's transient dock icon arriving between the
two reads indexed past the slot array (an `ud2` at `DesktopShell.swift:6917`,
symbolised with `addr2line` from the kernel's `traps:` line; the shell's
own log ends silently). The build now takes one snapshot for both, and the
icon loop never reads past what was sized. What could mutate the list
between two synchronous reads is not settled — the registry watch runs on
the main queue — and is noted rather than explained.

Two things the launcher shows that are decisions, not bugs: a guest app is
named what Windows names it, so "Calculator" appears twice (ours and the
guest's, told apart by icon), and every AppsFolder entry becomes a record —
74 here, Character Map and Recovery Drive included — because that is what
Start lists.

## Phase 6 — DPI and resize

Run the guest at the host output's logical size with Windows' scaling at the
host's scale, or every crop lands at the wrong size. M1's `set_ui_size`
already drives the first half; the second is a one-time guest setting.

**BUILT 2026-09-04.** Not a one-time guest setting after all: the helper's
`set_scale` op changes Windows' display scaling LIVE, through the
DisplayConfig DPI-scale device-info requests (types -3/-4 — the
undocumented half the Settings app uses, and what the SetDPI tools wrap).
No sign-out, DWM re-scales, apps get `WM_DPICHANGED`. The shell asks for its
own scale (`currentShellDpi` × 100) on every seamless attach, so a guest
window is the logical size a native one would be instead of physically 1:1
and small at 1.5x. Windows' scale is a step on a fixed ladder stored
RELATIVE to the monitor's recommended step; the helper reads the current
value with `GetDpiForMonitor` — which is why it is per-monitor-DPI-aware
now rather than system-aware, or the value would be frozen at process
start — and converts. The scanout stays at the output's physical size; the
crops did not change, because they were never in dpi units.

**VERIFIED 2026-09-04:** over the channel, 96 → 144 → 96 → 144 dpi with the
virtual screen fixed at 3840x2160; through the shell, "guest scale asked
150% -> 150%", and Notepad's frame went from 1270x747 to 1906x1121 guest
pixels — 1271x785 logical, the size a native window of it would be, its
menu text the same size as the desktop's title bars. Both checks and the
fast tier pass.

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
