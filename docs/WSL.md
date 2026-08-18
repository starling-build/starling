# Starling in WSL

What happens when you install the desktop inside WSL2, why the compositor
cannot start there, and what an RDP backend would have to look like to change
that. Everything below was run start to finish on 2026-08-16 against Windows
11 26200, WSL 2.7.11 (kernel 6.18.33.2-microsoft-standard-WSL2, WSLg 1.0.73.2)
and a fresh Ubuntu 26.04 LTS distro — the log lines are the ones that actually
came out, not a reconstruction.

## The short answer

The `.deb` installs cleanly and the shell itself runs. The **compositor cannot
run**, because WSL exposes no DRM/KMS device of any kind. There is nothing to
configure, no connector to force, and no EDID to override: the device class is
absent, not empty.

If the desktop grows an **RDP output backend** — RDP as the display, the way
WSLg's own Weston does it — WSL becomes an excellent place to run it, better
than a VM. An RDP *screen-sharing* feature layered on top of the DRM path
would not help at all. See "If RDP support lands" below; that distinction is
the whole point of this document.

## What works

- `wsl --install Ubuntu-26.04` — 26.04 **is** offered by `wsl --list --online`,
  so the version worry does not apply. The `.deb`'s dependencies are computed
  against 26.04 and every one of them resolves.
- `apt-get install -y /mnt/c/dist/starling_0.3.0_amd64.deb` installs clean:
  `ii  starling  0.3.0  amd64`. No held packages, no unmet dependencies.
- `DesktopShellApp --headless` runs the whole shell — the agent broker listens,
  the liquid-glass shader loads, the engine runs the widget tree:

  ```
  [AgentBroker] listening on /tmp/xdg-starling-headless/starling-agent.sock
  [DesktopShell] Liquid-glass shader loaded from .../liquid_glass.frag.iplr
  ```

  `--headless` uses the software renderer and its `surface_present_callback`
  returns `true` without doing anything, so the frames are produced and then
  discarded. It is a liveness path, not a visible desktop — but it does prove
  the binary, the engine, the assets and the shell's own startup are all fine
  under WSL. Whatever is broken is not those.

## Where it fails, exactly

`/usr/libexec/starling-session` redirects everything to
`/tmp/starling-session-$(id -u).log`, so a run that "prints nothing" is normal
— read the log. Two failures, in order, and the first one is a red herring:

```
[Seat] libseat_open_seat failed (no logind session / seatd?)
[DrmView] Seat init failed
DesktopShellApp/main.swift:596: Fatal error: fl_drm_view_create failed
```

`wsl -u root` is not a logind session, so libseat has nothing to attach to.
Installing `seatd` and starting it clears this completely — `srwxrwx--- root
video /run/seatd.sock`, and the shell then reports `[Seat] libseat active on
seat0`. Do not stop at the seat error and conclude WSL needs a session; it
does not. The wall behind it is the real one:

```
[Seat] libseat active on seat0
[Seat] libseat_open_device(/dev/dri/card0) failed
[DRM] Failed to open /dev/dri/card0
[DrmView] Display init failed
DesktopShellApp/main.swift:596: Fatal error: fl_drm_view_create failed
```

There is no `/dev/dri` directory at all — not an empty one, not a card without
a connector. (The `Illegal instruction` in the shell's output around this is
just Swift's `fatalError` trapping with `ud2`; it is the assertion above, not a
separate crash.)

## Why: rendering is not display

WSL gives you one half of "graphics" and none of the other.

| | What it is | In WSL |
|---|---|---|
| **Rendering** | the GPU draws pixels into a buffer | yes — `/dev/dxg` plus Mesa's d3d12 Gallium driver, reached through `libdxcore`/`libd3d12`/`libd3d12core` in `/usr/lib/wsl/lib` |
| **Mode-setting / scanout** | KMS: connectors, CRTCs, EDID, page flips onto a panel | none — no card node, no connector, no CRTC |

The kernel says so plainly. `dmesg` shows `hv_vmbus: registering driver
dxgkrnl`, and every message after it is prefixed `misc dxg:` — **dxgkrnl is a
misc character device, not a DRM driver**. `CONFIG_DRM=y` is set, but no driver
ever registers a card, so `/sys/class/drm` contains exactly one entry:
`version`. Mesa reaches the GPU through `libdxcore` and bypasses libdrm
entirely, which is why GL applications work perfectly well on a box with no
`/dev/dri` in it.

That is also why the synthetic-EDID recipe in `CLAUDE.md` cannot rescue this.
It writes `edid_override` into a connector's debugfs directory under
`/sys/kernel/debug/dri/<n>/<connector>` — which presumes a real DRM driver,
a real connector, and a debugfs tree for it. In WSL there is no `dri` directory
to descend into. The recipe is for a box whose connectors are all
`disconnected`; here there are no connectors.

## How WSLg puts Linux windows on screen

It does not scan out either. `cat /mnt/wslg/versions.txt`:

```
WSLg ( x86_64 ): 1.0.73.2
Azure Linux: VERSION="3.0.20260510"
FreeRDP: c4030980b29322a9cb2190711a5fadeeeb8b6a33
weston:  04d436c7d9a0cd55fa64b6612c7fa678d6fcd077
```

WSLg is a hidden Azure Linux system distro running **Weston with its RDP
backend**. Weston composites into an ordinary memory buffer and hands it to
FreeRDP, which streams it to the Windows side, where the RDP client draws each
Linux window as a native Windows window (RAIL mode). Your distro is handed
`WAYLAND_DISPLAY=wayland-0` and `DISPLAY=:0` pointing at
`/mnt/wslg/runtime-dir/`, so every GUI application in WSL is a **client** of
that compositor.

So the "screen" is a network protocol. No scanout, no vblank, no connector —
none of it is needed, because the pixels leave through a socket. This is the
existence proof that a compositor can run happily in WSL. It just cannot be a
KMS one.

## Why our shell cannot simply be one of those clients

It is not an application; it *is* the compositor, and it expects to own the
display. The shell accepts `--drm` and `--headless` and nothing else — the
windowed path was deliberately removed:

```swift
// main.swift:1071
fatalError("[DesktopShellApp] requires --drm (or --headless); windowed mode is not supported")
```

In WSL the compositor seat is already occupied by Weston, and the floor it
stands on is RDP rather than KMS.

## If RDP support lands

RDP in the desktop can mean two things that read alike in a changelog and are
completely different here.

**RDP as screen sharing, on top of DRM.** The desktop runs on real hardware,
composites through KMS, and additionally streams a copy of the screen to a
client. *This does nothing for WSL.* The session still opens `/dev/dri/card0`
first, still needs a connector and a CRTC, and still dies at
`fl_drm_view_create` before a byte of RDP code runs. The RDP side is a consumer
of frames that only exist because DRM already worked.

**RDP as an output backend.** The compositor's display *is* the RDP
connection — Weston's `rdp-backend` shape. No DRM in the path at all. This
solves WSL outright, and WSLg proves the shape works on this platform.

The one-line test for which you have: **can it start with `/dev/dri` absent?**
If yes, it runs in WSL. If no, it does not, however good the streaming is.

If it is the backend kind, `starling-session --rdp` inside Ubuntu 26.04 plus
`mstsc.exe` from Windows gives a real desktop hosting real Wayland clients,
with no nested VM and no image build. Three things will trip it in WSL even
once frames work, none of them about rendering:

1. **It must start with no seat.** We fail at libseat *before* DRM, and only
   got past it by installing seatd. A seat exists to hand out DRM master and
   evdev fds; an RDP-output shell needs neither. If `--rdp` still walks the
   seat path, it fails in WSL for a reason unrelated to display — and the error
   points at logind, which sends you the wrong way entirely.
2. **Output geometry has no EDID behind it.** `DeriveScale` picks 1x/1.5x/2x
   from the physical size in the EDID. An RDP client negotiates a resolution
   and reports nothing trustworthy about physical size, so scale needs an
   explicit policy rather than a derived one, or sessions come up at a
   surprising scale with nothing to reason about.
3. **Input must land in the same representation as evdev.** `EvdevToHID`
   (engine, `fl_drm_input.cc`) and `WaylandIntegration.hidToEvdev` (shell) are
   exact inverses. RDP delivers its own scancodes; feeding them in directly
   rather than converting into the same HID form breaks letters for Wayland
   clients — the failure mode `CLAUDE.md` already warns about for that pair.

And one gap to plan for rather than discover: `build/shell-drive.py` screenshots
go through DRM (`build/tools/drm_screenshot`), so driving and capturing a WSL
session needs an RDP-side equivalent before it can be tested the usual way.

There is a cheaper cousin worth knowing about. `--headless` already produces
real frames on the software renderer and throws them away in
`surface_present_callback`. Giving that callback somewhere to go — PNGs, a VNC
server, a `wl_surface` on WSLg's Weston — makes the desktop visible in WSL for
a fraction of the work, at the cost of software compositing and with input
still to wire. Useful for *seeing and driving* the shell; useless for measuring
it.

## The alternative, if RDP stays hardware-only

Run a VM with a real virtio-gpu, which gives both KMS and a render node.
Nested virtualisation is available inside WSL on this box — `/dev/kvm` exists
in the distro and 16 CPUs report `vmx`/`svm` — so `test/vm-harness/launch-vm-2604.sh`
can run nested, or use Hyper-V directly and skip a hypervisor layer. The cost
is building the guest image; nothing renders until that exists.

**Do not chase vkms.** It has no render node, and the shell opens one device
for both GBM/EGL and KMS.

## Reproducing, or picking this up

The box is already in this state: Ubuntu 26.04 installed under WSL, the `.deb`
installed in it, `seatd` installed, and `starling_0.3.0_amd64.deb` sitting in
`C:\dist\` (visible from the distro at `/mnt/c/dist/`).

```powershell
wsl --install Ubuntu-26.04 --no-launch          # 26.04 is offered; use it
wsl -d Ubuntu-26.04 -u root
```

```bash
apt-get install -y /mnt/c/dist/starling_0.3.0_amd64.deb   # installs clean
ls /sys/class/drm            # -> `version` only. This is the whole story.
ls /dev/dri                  # -> No such file or directory

apt-get install -y seatd && systemctl start seatd         # clears the red herring
LIBSEAT_BACKEND=seatd /usr/libexec/starling-session
tail /tmp/starling-session-0.log                          # the real failure

# what does run:
LD_LIBRARY_PATH=/usr/lib/starling FLUTTER_ENGINE_OUT=/usr/share/starling \
STARLING_DATA_DIR=/usr/share/starling FLUTTER_APPS_DIR=/usr/lib/starling/apps \
XDG_RUNTIME_DIR=/tmp/xdg-starling-headless \
  /usr/lib/starling/DesktopShellApp --headless
```

Quoting note for anyone driving this from PowerShell: nested quotes through
`wsl -u root -- sh -c "…"` are a reliable way to lose an afternoon. Write the
script to a file, strip CRs, and run that — `sed 's/\r$//' /mnt/c/dist/x.sh >
/tmp/x.sh; bash /tmp/x.sh`.

## Two things WSL does not provide, and the session must

Display mode runs the desktop here (see `docs/plans/rdp-wsl.md`), and a full
end-to-end run — install the `.deb`, connect `mstsc`, install Chrome from the
App Store, launch it — needs both of these. Neither is a product bug: they are
services a normal login gives you and WSL does not.

- **`XDG_RUNTIME_DIR` does not exist.** There is no logind, so nothing creates
  `/run/user/<uid>`, and `wsl --shutdown` wipes `/run` on every restart.
  Without it the Wayland compositor cannot write its lockfile and binds **no
  socket at all** — the log fills with `unable to open lockfile
  /run/user/1000/wayland-N.lock check permissions`, once per candidate name,
  and there is no `listening on wayland-N` line. The desktop still comes up
  over RDP and first-party apps still draw, because they are memfd/dma-buf
  children rather than Wayland clients — so the failure shows up only as
  "Chrome does nothing", with `Failed to connect to Wayland display` in the
  app's own output. Create it before starting the shell:

      install -d -o starling -g starling -m 700 /run/user/1000

- **polkit can never authorize the App Store.** The store installs through
  `pkexec app-install`, and `org.starling.app-install.policy` grants
  `allow_active` — which requires an *active logind session*. WSL has none, so
  pkexec answers `Not authorized` and the Install button fails. Grant that one
  action directly:

      # /etc/polkit-1/rules.d/49-starling-wsl.rules
      polkit.addRule(function(action, subject) {
          if (action.id == "org.starling.app-install" &&
              subject.user == "starling") { return polkit.Result.YES; }
      });

  Do not work around it by running the desktop as root instead: pkexec then
  succeeds, but Chrome refuses to start at all (`Running as root without
  --no-sandbox is not supported`), so the install works and the launch cannot.
  Unprivileged shell plus this rule is the combination that works.

## Driving a recorded run from the Windows side

Four traps, each of which cost a take:

- **A DPI-unaware capture gets a quarter of the screen.** The panel is 4K at
  200%, so `Screen.PrimaryScreen.Bounds` reports 1920x1080 and
  `CopyFromScreen` grabs the top-left quadrant of a 3840x2160 desktop. Call
  `SetProcessDPIAware()` first; for `ffmpeg`'s `gdigrab` (same `BitBlt`) mark
  the binary system-DPI-aware via the `AppCompatFlags\Layers` registry value.
- **`mstsc` full-screen negotiates the panel's *physical* resolution** —
  3840x2160 here, not the `desktopwidth` in the `.rdp`. Pair it with
  `STARLING_RDP_SCALE=2` so the session is a HiDPI 1920x1080 logical desktop.
  And prefer *windowed* (`screen mode id:i:1`) a little shorter than the
  screen: full-screen puts our dock on the screen's bottom edge, where a click
  reveals and hits the Windows taskbar instead.
- **Injected clicks need a hover that round-trips first.** A `SetCursorPos`
  straight onto a dock icon followed 450 ms later by `mouse_event` is ignored —
  the dock hit-tests through hover state. Hover, wait ~1.4 s, then click.
- **Nothing may steal foreground once the client is connected.** Every
  `wsl.exe` launch takes focus; `mstsc` then suppresses output and the session
  looks frozen — clicks are still delivered and logged, but nothing repaints.
  Do all WSL work *before* connecting. (Our `peer_suppress_output` ignores the
  `allow` flag and there is no force-composite on resume; that is the open W1
  item in `docs/plans/rdp-wsl.md`.)
