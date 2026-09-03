# Windows apps on Starling, from the Windows 11 **Home** the laptop came with

An exploration, 2026-09-01. Nothing here is built; the experiments at the end
are what to run first, in order, and each names the fact it settles. The
first of them ran on 2026-09-02 (the M0 display spike and the Triton
evaluation, on the dev box) — their outcome is in *Results (2026-09)* at the
end, and the layer text below is corrected in place where they proved it
wrong.

## The problem, restated

The earlier design ran Windows apps in a VM and reached them over RDP — an
`xfreerdp` session into the guest, with RemoteApp giving each Windows app its
own window on the Linux desktop. That is also what every project in this
space does (WinApps, WinBoat, Cassowary), and it has one dependency that
decides who can use it: **the guest must run Windows Pro**, because Home has
no Remote Desktop *server*. Client only. RemoteApp rides on the server, so it
goes too. Nothing changed in 2025's Remote Desktop churn — the Store client
died, the MSI client is out of support in March 2026, "Windows App" replaced
them — all of it client-side; the server still does not exist on Home, and no
official route to one is planned. The ecosystem's answer for Home users is
"install Pro from evaluation media and bring your own license" (dockur/windows,
which WinApps and WinBoat build on, lays down Pro by default). The unofficial
answers are RDP Wrapper — patches `termsrv.dll`, breaks on every Windows
update until new offsets ship, and violates the EULA's
"work around technical restrictions" clause outright — and Thinstuff XP/VS, a
commercial add-on that does work on Home. Neither is something to ship on.

Most laptops ship Home. So the question is what a design looks like that
**never asks Windows for anything Home gates**, and then how far it can go.

## What RDP was doing, and who can do it instead

RDP did two jobs. **Transport** — pixels out, keyboard and mouse in. And
**per-window integration** — RemoteApp (RAIL) gives each app window its own
surface on the client, so a Windows app can sit in the Linux window list like
a native one.

Home gates the Windows-side server for both. But a VM on our own host does not
need Windows for either:

- **The hypervisor owns the framebuffer and the input devices.** Whatever the
  guest scans out, QEMU has; whatever we inject into a virtual tablet and
  keyboard, Windows receives as hardware input. No server in the guest, no
  edition check, no session type — Windows cannot tell the difference between
  this and a person at the console.
- **Per-window integration needs a program inside Windows that knows the
  window list.** That is a guest helper we write, and the winshell branch
  already contains most of it: `sdk/Sources/FlutterWin32/` enumerates
  top-level windows and watches them change (`Win32WindowManager.observe`,
  a WinEvent hook), knows the app catalog (`flwin32_apps.c`, the Start Menu
  as IShellLink), launches apps, captures a window's pixels
  (`flwin32_capture.c`, PrintWindow with `PW_RENDERFULLCONTENT`, measured per
  app class), owns the clipboard and the tray. What it lacks is a channel to
  the host.

So the design moves both jobs out of Windows: transport to QEMU's D-Bus
display, per-window to our own helper. Everything below follows from that.

## The shape

```
 Starling (host)                                    Windows 11 Home (guest)
 ┌──────────────────────────────┐                   ┌─────────────────────────┐
 │ compositor                    │  dma-buf scanout  │ viogpudo (2D, shipped)  │
 │   GuestDisplay listener  ◄────┼───────────────────┼─ or a 3D WDDM driver    │
 │   (org.qemu.Display1)         │  QEMU -display    │   (tiers, below)        │
 │                          ─────┼─► Keyboard/Mouse ─┼─► virtio-tablet/kbd     │
 │ AgentBroker                   │                   │                         │
 │   Kind=windows windows   ◄────┼── virtio-serial ──┼─► guest helper          │
 │   list/launch/capture/UIA     │  JSON lines       │   (FlutterWin32-based)  │
 │ registry: Kind=windows        │                   │                         │
 └──────────────────────────────┘                   └─────────────────────────┘
                                   QEMU/KVM, libvirt domain; the person's own
                                   Windows partition, booted through a
                                   VM-private ESP (Layer 0)
```

Four layers, each useful on its own, each independent of the edition:

| Layer | What it gives | Depends on Windows for |
|---|---|---|
| 1. Display + input | the guest desktop as a Starling window, zero-copy, at guest frame rate; typing and clicking into it; the Windows cursor; clipboard | nothing (viogpudo + vioinput from virtio-win, which are drivers, not services) |
| 2. Acceleration | DWM, WebView2, D3D at something like native speed | a driver — which one depends on the host GPU |
| 3. Per-app windows | each Windows app as its own Starling window, in the launcher and dock | our helper, running in the user's session |
| 4. Agents | the broker's ops against Windows windows | our helper (UIA, per-window capture) |
| 0. The person's own Windows | no second license, no reinstall — the laptop's install becomes the guest | a one-time preparation while still booted natively |

Layer 1 is the foundation and the first thing to build; it replaces the
`virsh screenshot` / `send-key` loop of `docs/WINDOWS-VM.md` with a real
display. Layer 2 is a matrix, not a step. Layers 3 and 4 share one helper.
Layer 0 is a recipe plus a first-run flow.

## Layer 1 — the display and input path

QEMU has had an out-of-process display since 7.0: `-display dbus`, the
`org.qemu.Display1` interfaces (this is what GNOME Boxes uses through libmks,
and what the `qemu-display` Rust crate wraps). The client calls
`Console.RegisterListener(fd)` with one end of a socketpair; QEMU speaks
peer-to-peer D-Bus over it to an object the client exports at
`/org/qemu/Display1/Listener`. We already link sd-bus (basu when deployed) for
the portal and the IME bridge, and sd-bus does peer connections over an fd
(`sd_bus_set_fd`), so the plumbing is in-tree.

**The finding that makes this work for a Windows guest:** with `gl=on`, QEMU
delivers frames as `ScanoutDMABUF(fd, w, h, stride, fourcc, modifier, y0_top)`
plus `UpdateDMABUF(x, y, w, h)` damage rects — **even when the guest driver is
the 2D-only `viogpudo`**. `ui/dbus-listener.c`'s `dbus_gl_gfx_switch` uploads
a plain 2D surface into a GL texture and exports it
(`egl_dmabuf_export_texture`); the guest needs no blob resources and no 3D
driver. One host-side copy (guest RAM → texture), then zero-copy into the
compositor through `EGL_EXT_image_dma_buf_import` — the same import our
Wayland dma-buf clients already take, so the guest console composites like
any other window. QEMU 10.1 (2025-08) adds `ScanoutDMABUF2` (multi-plane,
per-plane offsets/strides, for DCC-style modifiers) and uses it iff the
listener exports that interface; single-plane is the fallback. 26.04 ships
10.2.1 and takes the multi-plane path when offered (measured: a `viogpudo`
guest arrives as `ScanoutDMABUF2`, one plane, `AB24`, modifier `INVALID`,
`y0_top=true`; UTM's 10.0-based fork still speaks the single-plane
`ScanoutDMABUF`, so the listener implements both). The GL-texture export
carries **no CPU-readable modifier** — the pixels are reached only by EGL
import, which is the path the compositor takes anyway — and `y0_top=true`
means the texture's row 0 is the bottom: flip on import iff it is set (the
placeholder surface QEMU sends first, and blob scanouts, come `y0_top=false`).

Frame pacing is built in on the GL path: QEMU blocks the guest's GL
(`qemu_console_hw_gl_block`) until our method reply arrives, so **the reply is
the ack** — return it once the image is latched, and the guest is throttled to
what we present. (A newer "DMABUF3" listener — pre-registered buffers swapped
with damage rects, client-settable refresh rate — was on the QEMU list in
August 2026, unmerged; it matches this use exactly. Track it.)

The rest of the interface, and what each means for us:

- **Cursor.** `viogpudo` drives the virtio-gpu cursor queue, so the Windows
  pointer arrives as `CursorDefine(w, h, hot_x, hot_y, argb)` +
  `MouseSet(x, y, on)` — a hardware cursor, not painted into the scanout.
  Composite it as a sprite and Windows' cursor shapes come for free.
  **Opt-in, though:** the shipped INF sets `HWCursor=0`, and with it the
  pointer is painted into the scanout and no `CursorDefine` ever comes.
  `HWCursor=1` under the adapter's class key
  (`HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-…}\000N`) plus
  a reboot turns it on (measured: 64x64 ARGB `CursorDefine` + `MouseSet`).
- **Input.** `Keyboard.Press/Release(u)` takes **qnum** (XT set-1 scancode,
  extended keys `| 0x80`) — *not* QKeyCode; keycodemapdb has the evdev→qnum
  table. `Mouse.SetAbsPosition(x, y)` needs a device with absolute axes
  (`virtio-tablet-pci`, or `usb-tablet` which needs no guest driver) and
  errors otherwise; `RelMotion` errors when a tablet is present; `IsAbsolute`
  says which. Buttons 0/1/2, wheel 3/4. QMP `input-send-event` is the other
  route (QKeyCode-typed) and coexists, but it shares the management channel,
  so the D-Bus one is the interactive path. Both confirmed (qnum chords,
  `usb-tablet` absolute positioning, drags). One trap: **p2p mode admits one
  control client at a time** — `dbus_display_add_client_ready` hands the
  object-manager server to the newest connection, and the previous client's
  connection is closed under it. Listener sockets coexist; a second
  `openGraphicsFD` does not. The compositor is that one client.
- **Clipboard.** `org.qemu.Display1.Clipboard` needs a guest agent:
  `-chardev qemu-vdagent,clipboard=on` + a `virtserialport` named
  `com.redhat.spice.0` bridges the ordinary Windows spice-vdagent into QEMU's
  clipboard core without SPICE. Or the helper (Layer 3) does it directly and
  never touches the host clipboard. Measured: **host → guest works** end to
  end on stock 10.2.1 (our `Grab` → the Windows vdagent's request → our
  `GetText`, pasted in Notepad). **Guest → host does not**, on any stock
  QEMU: the Windows vd_agent (0.10.0) never announces
  `VD_AGENT_CAP_CLIPBOARD_GRAB_SERIAL`, and `ui/dbus-clipboard.c` drops every
  grab that carries no serial — so a guest copy never reaches the listener.
  A four-line patch (forward serial-less grabs with serial 0; `patches/0003`
  in `docs/windows-vm/triton/`) is applied to our QEMU build and not yet
  verified against a vdagent guest.
- **Resolution.** `Console.SetUIInfo` pushes a size to the guest via
  virtio-gpu's EDID/display-info. The kernel driver does not apply it; the
  user-mode `vgpusrv.exe`/`viogpuap.exe` "VioGpu Resolution Service" in
  virtio-win does, and needs `vgpusrv -i` to install. It is the flakiest part
  of the stack (virtio-win issues #1391, #1314) — budget experiment time, and
  set the initial mode on the device (`xres=`/`yres=`/`edid=on`) so a fixed
  size works with no service at all. Measured: without the service
  `SetUIInfo` is accepted and nothing happens; with `vgpusrv -i` (virtio-win
  0.1.285) the new mode scans out 30–45 ms after the call, 8 of 8 tries at
  1600x900 / 1280x800 / back. The one flake was not the service: Windows'
  display-off timeout had blanked the panel, the mode changed but no scanout
  was issued until input woke it — `powercfg /change monitor-timeout-ac 0`
  (and `-dc`) for a guest whose "monitor" is a compositor.
- **Multi-head.** One `Console` object per head; whether `viogpudo` drives
  more than one is unconfirmed (likely single-head).
- **SPICE** is removed from RHEL 9's QEMU and maintenance-only upstream;
  `-display dbus` (local) and `qemu-rdp` (remote) are the successors. Do not
  build on SPICE.

What gets built: a `GuestDisplay` source in `Compositor/` — a C shim that
exports the Listener (and `.Unix.ScanoutDMABUF2`) over the socketpair and
hands imported images to the same texture path the Wayland surfaces use —
plus the keyboard map and the cursor sprite. The whole guest desktop is then
one Starling window: "Windows, in a window". That alone is a shippable
product step and the base for everything after.

Minimal QEMU shape (libvirt: `<graphics type='dbus' p2p='yes'>` with
`<gl enable='yes' rendernode='…'/>`; `<video><model type='virtio'/>` with
3D accel — the exact domain is `docs/windows-vm/win11-dbus.xml`; under
libvirt the client gets its socket from `virDomainOpenGraphicsFD`, no
`addr=` needed):

```
-device virtio-vga-gl,xres=2560,yres=1600,edid=on
-display dbus,gl=on,rendernode=/dev/dri/renderD128[,p2p=on,addr=…]
-device virtio-tablet-pci -device virtio-keyboard-pci      # or usb-tablet
-chardev qemu-vdagent,id=vd,name=vdagent,clipboard=on
-device virtio-serial-pci -device virtserialport,chardev=vd,name=com.redhat.spice.0
```

## Layer 2 — acceleration, by host GPU

This is the part that does not have one answer, and the exploration's main
job was to find out which answers exist in 2026. Two facts organise it.

**First: KVM has no shipped 3D driver for Windows guests.** virtio-win's
`viogpudo` is 2D; upstream's 3D driver (PR #943, `viogpu3d`, 2023) never
merged. The host side is ready — QEMU 9.2 ships Venus (Vulkan 1.3 over
virtio-gpu), and for Linux guests it is "close to native" — but nothing on
the Windows side consumed it until this year. Three alpha drivers now do:

| Driver | What the guest gets | Host | State (2026-09) |
|---|---|---|---|
| **Triton** (osy / UTM, v0.3 on 2026-09-01) | a real **WDDM** KMD (`viogpu3d.sys`, binding the stock virtio-gpu PCI id `1AF4:1050`) + `neptune_umd.dll`, a Mesa-built UMD implementing the D3D11 DDI — Microsoft's own `d3d11.dll` runs on it; calls serialised ("Neptune") over virtio-gpu and replayed on the host; Venus Vulkan ICD alongside | AMD/Intel (Mesa); **no NVIDIA** | alpha (four releases in six weeks, v0.3 a "critical fix"); D3D10/11 today, D3D12 in the protocol (`d3d12.idl`, host slot for vkd3d-proton) but not in the driver; see *Triton, concretely* |
| **Yttrium** | WDDM; Mesa in the guest — D3D9–11 via Gallium → SPIR-V → Venus, Vulkan via Venus, GL via Zink; no D3D12 | any Venus host (tested on Arc) | alpha, test-signed (Secure Boot off) |
| **Helios** (WinBoat) | a Vulkan ICD only — **not a WDDM adapter**; DXVK/Zink inside the guest; display through a separate IDD | any Venus host | alpha, "driver release aimed for 2026" |

**Triton, concretely** — what adopting it commits us to, from the repos
(`osy/kvm-guest-drivers-windows` branch `neptune`, `osy/virtio-win-mesa`,
`utmapp/virglrenderer` — the host side lives on **`macos-next`**, whatever
the name says; the `neptune` branch stopped 2026-07-25 and desynchronises
against the v0.3 guest — `osy/neptune-protocol`):

- *Guest:* one driver package (`viogpu3d.sys` + `.inf`/`.cat`, `neptune_umd.dll`,
  `vulkan_virtio.dll`) replacing `viogpudo` on the same device. It **is** the
  primary adapter, so DWM, DirectComposition and WebView2 land on it — the
  property the tier analysis needs. Measured: DWM does run on it; WebView2
  and Edge land on it and their GPU process dies in the UMD (Results).
  BSD-3 (driver) / MIT (Mesa, virglrenderer): shippable.
- *Host:* virglrenderer built with `-Dneptune=true`, which `dlopen`s **DXVK's
  native Linux build** (`libdxvk_d3d11.so`, `libdxvk_dxgi.so`, named by
  `NPT_D3D11_LIBRARY_PATH` / `NPT_DXGI_LIBRARY_PATH`; built
  `-Dnative_headless=true`) and replays the D3D11 stream onto the host's
  Vulkan — RADV or ANV, hence the AMD/Intel-only note. Each guest D3D11
  device becomes a Neptune context, and each context is its own
  `virgl_render_server` worker process holding its own Vulkan device. **And
  UTM's QEMU fork, which is required, not optional**: the Neptune capset
  (`VIRTIO_GPU_CAPSET_NEPTUNE`), the `neptune=on` device property and the
  async-fence path exist only there, and the device refuses to start without
  `blob=on` and `hostmem=`. Stock 10.2 cannot advertise the capset, so the
  guest driver loads and finds nothing. Three packages, then —
  `docs/windows-vm/triton/build-host.sh` builds them into `/opt/triton`
  from pinned commits.
- *Frames:* swapchains and shared textures are **blob-backed dma-bufs**
  ("share guest textures as blob-backed dmabufs for cross-context
  compositing", 2026-07), scanned out through virtio-gpu like everything
  else — so Layer 1's dbus listener receives them unchanged. Path A survives.
  Measured: it does, as `ScanoutDMABUF` `AR24` `LINEAR`, one per frame,
  because DWM *flips* a triple-buffered blob chain — which stock
  `ui/dbus-listener.c` turns into a `Disable` per frame and a stale picture
  until patched (`patches/0004`; Results).
- *Signing — resolved, and in the project's favour.* v0.3's `-signed`
  package carries a catalog signed by Microsoft's attestation signer
  (`CN=Microsoft Windows Hardware Compatibility Publisher`, issuer "Microsoft
  Windows Third Party Component CA 2014", valid to 2027-05), not the
  virtio-win test certificate, and **it loads with Secure Boot on** — no test
  mode, so nothing touches the native boot of the person's own Windows
  (Layer 0). Attestation-signing a package ourselves through Partner Center
  becomes a question only if we ever ship a driver package of our own.
- *Coverage:* D3D11-and-earlier apps and Vulkan; D3D12 apps fall to WARP
  until the driver grows the second protocol family; OpenGL only via Zink
  over Venus, if at all. For the app population this design is for (Office,
  Electron, WinUI, Adobe's D3D11 paths) that would be the right 90% — except
  that today **Chromium's ANGLE-on-D3D11 does not survive the UMD**
  (`DXGI_ERROR_DRIVER_INTERNAL_ERROR` creating a rasterizer state, GPU
  process exits, software GL), which takes Electron, WebView2 and Edge out
  of the accelerated set until that bug is fixed in Triton (Results).

**Second: Windows renders on the adapter that owns the primary display.** A
headless render GPU beside an emulated display (virtio/QXL) does *not* become
the renderer — every passthrough and SR-IOV guide ends up either putting a
display on the real GPU (a dummy plug or an indirect display driver) or
deleting the emulated one so DWM lands on the VF. Per-app GPU preference
moves an app, never DWM. The hybrid cross-adapter path (Optimus) engages
only when the driver stack declares a hybrid pair, which an emulated adapter
does not. (24H2's cross-adapter scan-out in a VM: no reports either way.)

The consequence for the architecture: for DWM, WebView2 and DirectComposition
UI to feel native, **the guest's primary adapter must have a WDDM driver**. A
Vulkan-ICD-only guest (Helios) accelerates draw calls and leaves DWM in
software. And the frames come out one of two ways:

- **Path A — virtio-gpu scanout.** The primary adapter is virtio-gpu (2D
  today, Triton/Yttrium tomorrow) and Layer 1 receives the picture
  unchanged. Host keeps its GPU. This is where the compositor work goes.
- **Path B — in-guest capture.** The primary adapter is a real GPU with no
  output (an SR-IOV VF, or a passed-through dGPU); a virtual monitor (IDD)
  sits on it, and a program in the guest captures the desktop into shared
  memory. That is exactly Looking Glass: its host app writes DXGI/D3D12
  captures into an IVSHMEM BAR (the open LGMP protocol + KVMFR headers,
  documented as code), and its client is an ordinary Wayland app. B7 (March
  2025) shipped; Looking Glass' own IDD is in nightlies through 2026-09 and
  not yet in a stable release, so today it still wants a third-party Virtual
  Display Driver or a dummy plug.

Layer 1's `GuestDisplay` must therefore abstract two sources — a D-Bus
scanout and an LGMP frame — and the cheapest first version of Path B is
**running the stock `looking-glass-client` as a Wayland client** inside
Starling: it appears as a window, and no compositor code is written. A native
LGMP consumer (frames straight into our texture path, per-window cropping
possible) comes after, if Path B earns it.

Now the matrix, by what a laptop actually has:

| Host GPU | Split the GPU? | Best today | Best bet | Notes |
|---|---|---|---|---|
| **Intel 12th–14th gen** (Alder/Raptor Lake) | yes — SR-IOV via out-of-tree `strongtz/i915-sriov-dkms` (maintained; kernels 6.12–6.19; up to 7 VFs) | VF as primary adapter, genuine Intel driver (D3D12, DWM accelerated), Path B | same | Windows Update can downgrade the VF's driver to a broken 2022 one (block it); Code 43 sometimes wants `cpu=host` |
| **Intel Tiger/Alder Lake on Xe, Panther Lake, Battlemage Pro** | yes — mainline Xe SR-IOV (6.17/6.18); Panther Lake ships with it | VF, Path B | same | the clean case: in-tree kernel, 2026 laptops |
| **Intel Meteor / Lunar / Arrow Lake** (the 2023–2025 Core Ultra laptops) | **no** — MTL is i915-only (no dkms path), LNL unsupported, ARL iGPU has no official SR-IOV | Path A, 2D + WARP | Triton / Yttrium on Path A | VMware Workstation as the mature escape hatch (below) |
| **AMD iGPU only** (680M/780M/890M — this dev box's class) | **no** — GIM (open-sourced 2025-04) is Instinct-only; "client Radeon on the roadmap", nothing shipped | Path A, 2D + WARP | **Triton on Path A** — measured 2026-09: loads under Secure Boot, DWM and D3D11 on the host GPU, scanout still dma-buf; Chromium/WebView2 in software; and a host-memory budget that ends an 8 GB guest on a 16 GB laptop in an OOM kill (Results) | full iGPU passthrough blanks the host: non-starter |
| **Hybrid + NVIDIA dGPU** (this dev box; muxless) | no split (vGPU is datacenter-only; `vgpu_unlock` dead past Turing) — but the whole dGPU can go | VFIO the dGPU + Looking Glass, Path B: full native driver, D3D12, everything | same | host loses the dGPU while the VM runs (fine: host keeps the iGPU); muxless needs the vBIOS via patched ACPI and a fake-battery SSDT against Code 43; `docs/WINDOWS-VM.md` already binds `10de:25ac` to vfio-pci and notes the card is headless |
| **Hybrid + AMD dGPU** | as above | VFIO + Looking Glass | same | fewer driver tricks than NVIDIA |

And the non-KVM option, because on an AMD-only or Core-Ultra laptop it is the
only mature accelerated D3D11 today: **VMware Workstation** (free since
2024-11; 26H1 released 2026-05) gives Windows guests DX11 + OpenGL 4.3 via
SVGA3D on any host with GL 4.5+/Vulkan, DWM and WebView2 just work, and the
host GPU is shared at API level. The catches are real: closed source, not
redistributable, no support, and `vmmon`/`vmnet` break on new kernels with
community patch repos filling the gap (6.15–6.17 all needed one). Its display
is its own window, so it would run as a Wayland client — no Layer 1, no
per-window crop. VirtualBox 7.2 (D3D11 over DXVK, GPLv3) works and is the
slowest of the viable options. Both are escape hatches to *mention* in a
compatibility note, not platforms to build on: they would fork every layer
above.

**Recommendation.** Build Path A first (it is the same work whether the guest
has 2D or Triton; Triton keeps the scanout on virtio-gpu, so Layer 1 is
unchanged when it lands), stand Path B up with the stock Looking Glass client
on the dev box's 3050 to know what "native" feels like and what the per-tier
gap is, and evaluate Triton on the 680M as the strategic KVM-native bet for
the AMD/Core-Ultra population — the largest one. Be honest in the product
copy: "fast" on those machines today means a fast *display path* (60 fps
compositing instead of a screenshot loop, which is what every dockur/WinApps
user runs) with software DWM, not accelerated D3D. The Triton evaluation
(Results) does not change that copy yet: it accelerates DWM and D3D11, not
the Chromium-based apps most of the population runs, and it is not yet
stable enough to ship — it is the bet, still, with two named blockers.

## Layer 3 — per-app windows without RemoteApp

Nothing exists for QEMU. VirtualBox's seamless mode is the model: the guest
additions stream the visible-region rectangles to the host, which shapes one
borderless full-screen window; VMware's Unity enumerated windows guest-side
and is long gone; no open-source SPICE/QEMU Windows agent reports a window
list today. So this is our helper, and the winshell branch is its source.

**The helper.** A per-user autostart program in the interactive session (HKCU
Run or a logon task — never a service in session 0, whose windows are never
composited), speaking JSON lines over one virtio-serial port
(`org.starling.agent.0`; virtio-win's `vioser` is mature and WHQL-signed, the
same channel qemu-ga uses). `virtio-vsock` for Windows is real and maintained
through mid-2026 but its presence on the stock virtio-win ISO is unconfirmed;
serial first. Bootstrap once through qemu-ga plus an interactive scheduled
task (`schtasks /it`, the trick `docs/WINDOWS-VM.md` already documents).
Ops, each on an API the FlutterWin32 tree already calls:

| Op | Windows side | Limit |
|---|---|---|
| `list_windows` + change events | `EnumWindows`, `DWMWA_CLOAKED` filter, `GetWindowThreadProcessId` → exe path / AUMID; WinEvent hook (`Win32WindowManager.observe`) | identity is exe/AUMID, never title (same rule as the shell's `app_id`) |
| `launch` | `ShellExecuteEx` / `CreateProcess` in-session; `IApplicationActivationManager` for Store apps; catalog from the Start Menu (`flwin32_apps.c`) | unelevated helper cannot reach elevated windows (UIPI) |
| `capture(window)` | `Windows.Graphics.Capture` `CreateForWindow` (occluded and DirectComposition content OK); PrintWindow `PW_RENDERFULLCONTENT` fallback (black on some DirectComposition surfaces) | minimized windows stop producing frames; WGC's yellow border unless `IsBorderRequired=false` |
| `inject` into a window | UIA pattern → `PostMessage` (legacy Win32 only; Chromium ignores it) → `SetForegroundWindow` + `SendInput` | `SendInput` is foreground-only — see Layer 4 |
| `semantic_tree` / `perform_action` | UI Automation with `CacheRequest`; Invoke / Value / Toggle / SelectionItem / ExpandCollapse / ScrollItem | Chromium (Electron, WebView2) exposes UIA natively since Chrome 138 (2025), first query slow; virtualised lists need `VirtualizedItemPattern` |
| `await_settled` | `WaitForInputIdle` + UIA structure/property event quiescence + `GetGUIThreadInfo` + capture frame delta | all heuristic; Chromium settles after the tree says so |
| `clipboard` | `OpenClipboard`/`GetClipboardData` in-session | replaces the vdagent chain if we want |

**Presenting per-window.** Two ways, and v1 takes the cheap one:

- *Crop the scanout.* The helper reports rects and z-order; the compositor
  cuts each window out of the one dma-buf as its own Starling surface,
  positioned where Starling wants it, with server-side decorations. Zero
  extra copies. The catch is z-order: the crop shows whatever the *guest*
  has at that rect, so two overlapping Windows windows show Windows'
  stacking, not Starling's. Handle it the way VirtualBox does, plus one
  trick: keep all guest windows in one z-layer group, and mirror Starling's
  ordering back into Windows (`SetWindowPos` / `SetForegroundWindow` from the
  helper on focus). Interleaving a Windows window between two Linux windows
  is the case this cannot do, and v1 does not offer it.
- *Per-window capture.* WGC per window streamed out — true independent
  surfaces, one copy per window per frame, heavy on a WARP guest, and it
  needs a bulk channel (IVSHMEM, not serial). This is the v2 if the z-order
  compromise turns out to matter, and it is the agent capture path anyway.

The guest desktop in seamless mode should be *empty*: no wallpaper, no
explorer taskbar, and the winshell branch's Phase 5 already owns the
`Winlogon\Shell=` slot with a supervisor that hands the machine back to
explorer if it crashes twice in a minute. Running `WinShellBar --session`
as the guest's shell, with the bridge as one more role, makes the helper the
shell rather than a program beside it — and gives the dock's live previews,
the tray and notifications on the Linux side for free. That is the biggest
piece of prior work this exploration found, and it was built for another
purpose entirely.

DPI: run the guest at the host output's logical size and Windows' scaling at
the host's scale (200% on this panel), or crops land at the wrong size.
`SetUIInfo` when the output changes, given the resolution service behaves.

**Registry.** `Kind=windows` joins `first-party` / `host` / `android` / `x11`
in `AppRecord.Kind` — the Waydroid precedent is exact: a container that
renders into our window, whose apps are listed by an agent inside it. One
shipped record (`windows.app`, "the Windows desktop", `Exec=` the domain
name) and per-app records the helper writes into
`/var/lib/starling/installed.d/` from the Start Menu, the way `app-install`
writes host apps — the shell's inotify watch lights them up in the launcher
with no relogin. No app id goes in a table anywhere; that rule stands.

## Layer 4 — agents

`AgentBroker.swift`'s ops map one-to-one onto the helper's (that table was
written against the broker's vocabulary), so a `Kind=windows` window is one
more window kind the broker can list, launch, capture, inject into and read
semantically. Ownership is by launch: the helper tags windows by the process
it started for which agent, and `ownedWindow()` resolves as it does now.
What changes are two of the four properties in `computer-use.md`:

- **Capture stays content-local** — but through the helper (WGC per window),
  not the scanout crop, which shows whatever overlaps. The helper is ours
  and runs in a VM we control, so the privacy property holds; it is enforced
  one hop further away.
- **"Agent input never touches the human's controls" holds only while the
  human is not in the VM.** A Windows session has one input queue and one
  foreground window. `SendInput` lands wherever the foreground is;
  `PostMessage` reaches legacy Win32 and nothing modern. Microsoft's own
  agents confirm the limit: UFO² runs the agent in an RDP loopback session
  (Pro only), and Windows 11's *agent workspace* (Copilot Actions, Insider
  preview since 2025-11) gives each agent a separate account and a parallel
  contained session — reportedly an RDS child session — with no external
  protocol and Home availability unstated. The EULA closes the other door:
  2(d)(iv) is one instance per device, "physical or virtual", so a second
  VM for the agent is a second license.

So the VM is a **seat**, and the shipped take-over mechanism that left with
the AI Space (`computer-use.md`, property 4) comes back at VM granularity: a
seat lease. While the person has a guest window focused, agent ops that need
the foreground (`click`, `key`, `text`) wait, or fail with a distinct error
so a batch stops cleanly; `semantic_tree`, `perform_action` (UIA patterns act
without focus or cursor), `capture` and `list_windows` proceed regardless.
Semantic-first is the right default for a shared VM anyway — it is the escape
from pixels the broker already offers first-party UI. A person who never
opens a Windows window themselves gets the full property set; a person who
does shares one seat with the agent and sees the guest cursor move. Say so.

Track, do not build on: the agent workspace, and Windows' on-device MCP
registry (ODR, File Explorer and Settings servers, Insider preview) — the
helper could act as the in-guest MCP host and bridge tool calls out, once
they leave preview.

## Layer 0 — the person's own Windows

The premise: the laptop already has a licensed Windows 11 Home on it. Linux
goes on beside it, and the existing install becomes the guest — no
reinstall, no second license, and it still boots natively if wanted.

**Boot the partitions, not the disk.** Passing the whole NVMe through hands
the guest the live Linux filesystems and lets Windows write its BCD into the
shared ESP (an attempt on the Arch forums ended in an Automatic Repair loop).
The working pattern, reconfirmed on Proxmox in 2024: give the VM its **own
ESP** — two small image files (~100 MB head, 1 MB tail) composed with the
real Windows NTFS partition by `mdadm --build --level=linear` into one block
device, a synthetic GPT written over it, and `bcdboot C:\Windows /s B: /f ALL`
run once from install media to populate the private ESP. Native boot keeps
the real ESP; the VM never sees it. No packaged tool does this; it is a
libvirt hook that assembles the array before start.

**Decrypt first.** 24H2 turns Device Encryption on by default on clean
installs — including Home, with a Microsoft account — so assume the disk is
BitLockered. The key is sealed to the physical TPM's PCRs; swtpm measures
differently, so the first VM boot demands the recovery key, Windows re-seals
to the *current* TPM, and the next native boot demands it again. (The
ping-pong follows from the mechanism; no single report of the alternating
case was found.) While still booted natively: save the recovery key, then
`manage-bde -off C:` and wait for 0%. Suspend is a one-reboot bypass, the
wrong tool.

**Activation.** An OEM key lives in the firmware's ACPI MSDM table; passing
it through (`-acpitable file=/sys/firmware/acpi/tables/MSDM`) together with
the host's SMBIOS type 0/1 (libvirt `<sysinfo type='smbios'>` — manufacturer,
product, serial, UUID; Windows checks the UUID) is repeatedly reported, on
Proxmox and elsewhere through 2025, to keep the guest activated; KubeVirt
merged MSDM passthrough in 2025 for this reason. Typing the MSDM key by hand
is now refused server-side — table passthrough is the path. A
Microsoft-account digital license has the "I changed hardware" troubleshooter
as fallback, with mixed reports. Activation is an opaque server decision:
"stays activated in practice", never "guaranteed". Unactivated Windows keeps
working, with a watermark and locked personalisation.

**The license question, separately from the activation one.** The OEM terms
(April 2024) say, 2(d)(iv): *"This license allows you to install only one
instance of the software for use on one device, whether that device is
physical or virtual."* One instance is what this is — the same install,
booted either way on the same laptop. Microsoft's own Q&A answers read OEM
licenses as carrying no virtualisation rights at all; a retail license moved
into the VM is the unarguable configuration. This is a product decision, not
an engineering one, and the doc's job is to make it visible: the design needs
exactly one instance and never two, and it is no worse a position than the
state of the art (Pro from evaluation media, unlicensed, which is what
WinApps/WinBoat ship).

**Drivers, updates, hardware.** Windows tolerates alternating hardware
profiles; the one killer is the boot controller — a virtio boot disk with no
boot-start driver bound is `INACCESSIBLE_BOOT_DEVICE`, and installing the
virtio-win MSI natively stages the drivers without guaranteeing that binding.
First VM boot on AHCI (inbox `storahci` always binds), install/verify
virtio-win, attach a dummy virtio disk so the driver binds, then flip.
Feature updates re-check hardware (24H2 needs POPCNT/SSE4.2, 25H2 needs TPM
2.0 + Secure Boot to upgrade), so the domain gets the full kit from day one:
q35, OVMF `.ms.fd` + MS-keyed VARS, swtpm 2.0, `host-passthrough` — the same
interlocking set `docs/WINDOWS-VM.md` warns not to improvise on. `powercfg
/h off` before anything touches the NTFS from Linux (Fast Startup leaves it
dirty).

**The recipe**, as a first-run flow the Setup app could drive:

1. *Still in native Windows:* save the recovery key; decrypt; `powercfg /h
   off`; install virtio-win guest tools; confirm the account link under
   Activation; note `OA3xOriginalProductKey`.
2. *From the Linux installer, before repartitioning:* image the Windows
   partitions to external storage — the rollback for everything after.
3. *Define the domain:* private-ESP composite (or, laptop-becomes-Linux, a
   qcow2 assembled from the images, optionally `virt-v2v-in-place` on the
   copy — never the original; virt-v2v 2.8 handles Windows 11 and injects
   virtio); MSDM + SMBIOS from the host; TPM, Secure Boot, host CPU; the
   Layer 1 display and input devices.
4. *First boot on AHCI:* let PnP settle, bind virtio, flip the disk, check
   activation, run the troubleshooter if needed.

Failure modes to design for, each recoverable: recovery-key prompt (escrowed
key); `INACCESSIBLE_BOOT_DEVICE` (keep the AHCI config); dirty NTFS (refuse
to assemble while mounted, and `/h off` is a hard prerequisite); activation
drop (troubleshooter, then honest UI); blocked feature update (the full
hardware kit, or the `AllowUpgradesWithUnsupportedTPMOrCPU` escape).

## Milestones

**M0 — the display spike** (dev box, existing `win11` domain, no product
code): a listener in Python or C receives `ScanoutDMABUF` from a Windows
guest on `viogpudo` with `gl=on` on the 680M; a moving window renders at
guest frame rate; qnum keyboard and absolute mouse work; the cursor arrives
as `CursorDefine`. Settles the one fact Layer 1 rests on. **Done 2026-09-02**
(`docs/windows-vm/dbus-display.py`; Results).

**M1 — Windows in a window**: `GuestDisplay` in the compositor; `windows.app`
in the registry; launch starts the domain and presents its console; input,
cursor sprite, clipboard through vdagent; resize through `SetUIInfo` if the
resolution service cooperates, fixed size otherwise. Replaces `wshot.py` /
`type-keys.py` for the terminal work's VM too. **Done 2026-09-02** — the plan
and its status are `docs/plans/guest-display.md`, the guest-side setup is
`docs/WINDOWS-VM.md` §"Windows in a window". Verified on stock QEMU 10.2.1,
unprivileged. Open at the end of M1: guest-to-host clipboard (needs
`patches/0003`), and a guest reboot with the window open still needs
`patches/0005`.

**M2 — the helper and seamless mode**: the virtio-serial bridge in
FlutterWin32; window list and events; crop-per-window; z-order mirroring;
per-app registry records; `WinShellBar --session` as the guest shell with
the bridge role.

**M3 — agents**: `Kind=windows` in the broker; the seat lease; UIA
`semantic_tree`/`perform_action`; per-window WGC capture over IVSHMEM;
`computer-use-mcp.py` grows nothing — the ops are the same.

**M4 — Layer 0 as a flow**: the Setup app's first-run page, the libvirt hook,
the AHCI-first domain, the recovery-key and activation states as UI.

**Tracks beside them, not gates:** *GPU-A* — Triton on the 680M: build
virglrenderer's `neptune` branch + DXVK-native, install the v0.3 x64 package in
the `win11` domain, and answer in order: does it load with Secure Boot on;
does DWM run on it (dxdiag, `dwm.exe` GPU time); does WebView2/Edge; does
Layer 1's scanout still arrive as dma-buf (it should: the primary adapter is
still virtio-gpu); does stock 26.04 QEMU suffice or is UTM's fork needed; an
hour of ordinary use without a TDR. **Answered 2026-09-02**, in that order:
yes; yes; no (software GL); yes (with one listener patch); the fork is
needed; not shown — the first run was OOM-killed on the host at 19 min, the
15-minute re-run held (Results). *GPU-B* — the 3050 domain (`win11-gpu`)
with a Virtual Display Driver, Looking Glass host in the guest, stock client
as a Wayland window: the "native" reference point and the Path B smoke
test. *Intel* — no Intel box here; the SR-IOV tier is
unverified locally and stays a documented option until one exists.

## Experiments, in order, each with what it settles

1. **`gl=on` + `viogpudo` → `ScanoutDMABUF`** on the 680M, vs a silent
   fallback to `ScanoutMap`/`Update`; damage granularity and sustained fps.
   *If this fails, Layer 1 becomes a pixel path and loses zero-copy — still
   edition-independent, just slower.* → **dma-buf, per-rect damage, at guest
   rate** (Results A1).
2. **QEMU version on 26.04** and whether `ScanoutDMABUF2` is present; whether
   single-plane import works on AMD with the modifiers QEMU chooses. →
   **10.2.1, `ScanoutDMABUF2` used, modifier `INVALID`, EGL import proven**
   (A2).
3. **`p2p=on` `addr` semantics** standalone (who listens), or go through
   libvirt's `<graphics type='dbus'>` and `virDomainOpenGraphicsFD`. →
   **libvirt + `openGraphicsFD`; one control client at a time** (A3).
4. **The ack timeout** — what QEMU does when our reply is late (drops, or
   stalls the guest), so a stalled compositor cannot wedge Windows. → **a
   late reply throttles and coalesces; nothing drops, nothing wedges** (A4).
5. **Resolution service** reliability on current virtio-win; single- vs
   multi-head under `viogpudo`. → **8/8 with `vgpusrv`; multi-head untested**
   (A5).
6. **Clipboard chain** end to end: dbus Clipboard ↔ qemu-vdagent ↔ Windows
   vdagent. → **host→guest yes; guest→host needs a QEMU patch** (A6).
7. **Helper transport**: a JSON-lines echo over `vioser` from a program in
   session 1, latency per round trip; whether the stock virtio-win ISO ships
   `viosock`.
8. **Crop-and-mirror** with two overlapping guest windows: how visible the
   z-order seam is in practice.
9. **Path B** on `win11-gpu`: VDD + Looking Glass host + stock client under
   Starling; a WebView2 app side by side with the same app on Path A.
10. **Triton** on the 680M: stock vs forked QEMU; Secure Boot load; DWM and
    WebView2 on the adapter; scanout still dma-buf; an hour without a TDR.
    → **fork required; loads; DWM yes, WebView2 no; dma-buf yes; the hour
    not reached — one host OOM kill at 19 min, a 15-minute re-run held**
    (Results B).
11. **P2V on a real Home laptop** (not the dev box): the four phases,
    activation state after step 4, and the native-boot round trip.

## Risks and traps

- **Resolution changes are the soft spot** of the whole virtio-gpu Windows
  stack; ship a fixed-size fallback and never make seamless depend on live
  resize working.
- **A late listener reply throttles the guest** by design; a hung one may
  stall it. Put the import on its own thread and reply on a deadline.
- **NVIDIA hosts and dma-buf import** are a known bad pairing around
  Boxes/libmks (black screens; unconfirmed on current drivers). Our AMD box
  is fine; do not promise NVIDIA-host Path A without testing.
- **`SendInput` is foreground-only** and `PostMessage` does not reach
  Chromium: an agent clicking pixels in a shared VM *will* steal the
  foreground. The seat lease is the answer; do not try to be clever with
  message injection.
- **PrintWindow returns black for the shell's own Flutter window** (measured
  in `flwin32_capture.c`) and for some DirectComposition surfaces; WGC first.
- **Alternating native/VM boots re-seal BitLocker each way.** Decrypt is
  the only stable state; treat a still-encrypted disk as a blocking
  first-run condition, not a warning.
- **Windows Update replaces the Intel VF driver** with a broken older one;
  the SR-IOV tier needs a driver-update block as part of its setup.
- **Muxless NVIDIA passthrough** needs the vBIOS through patched ACPI and a
  fake battery; `win11-gpu` has the card but as a headless render device.
- **Every seamless project uses RemoteApp**, and none of them work on Home:
  there is no shortcut to borrow, and the helper is on the critical path
  for Layers 3 and 4.
- **One p2p control client.** The dbus display closes the previous client's
  connection when a new one registers. Anything that "just connects to take
  a screenshot" (a debug tool, an agent) disconnects the compositor.
- **A flipping guest and the stock dbus listener.** Blob scanouts arrive as a
  new `ScanoutDMABUF` per frame and stock `ui/dbus-listener.c` answers each
  with a `Disable`; the listener needs `patches/0004` (or upstream's
  eventual fix) or it shows a stale frame. Only shows with a 3D guest.
- **Guest reset with a listener registered** asserts stock QEMU
  (`dbus_scanout_texture: tex_id`) — a Windows reboot kills the VM until
  `patches/0001` is in.
- **The guest's display-off timeout** blanks a "monitor" nobody can see:
  after it fires, mode changes and frames stop until input arrives. Set
  `powercfg /change monitor-timeout-ac 0` (and `-dc`) as part of guest
  setup.
- **Triton's host memory is per D3D11 device, not per guest**: every device
  is a render-server worker with its own Vulkan device and ~50 MB of GTT,
  Windows creates dozens, and the pages are neither the guest's RAM nor
  anyone's RSS — invisible to `free` until the OOM killer picks QEMU.

## Open decisions, each with a recommendation

- **libvirt or bare QEMU for the shipped domain?** libvirt: `<graphics
  type='dbus'>`, the hook mechanism for the mdadm composite, and the
  existing `docs/WINDOWS-VM.md` tooling all assume it.
- **Where does the helper live in the tree?** In `sdk/Sources/FlutterWin32`
  as a bridge role of `WinShellBar`, not a separate program: it needs the
  same window, catalog and capture code, and the session slot.
- **Crop vs per-window capture for seamless v1?** Crop, with z-order
  mirroring; per-window WGC only for agent capture until the seam is shown
  to matter.
- **Which GPU tier does the first release claim?** Path A, 2D — on every
  machine — plus Path B documented for hybrid laptops. Triton is the
  acceleration for Path A and the bet for the AMD/Core-Ultra population;
  it ships when GPU-A passes, not before. Secure Boot is no longer the gate
  (it loads); the gates now are Chromium's GPU process surviving the UMD
  and a host-memory budget that survives an hour (Results B).
- **The OEM license reading.** Surface it in the first-run flow in plain
  words ("your Windows, moved into a window on this laptop; a second copy
  needs a second license") and take the product decision explicitly.

## Results (2026-09)

The M0 spike and the Triton evaluation, run 2026-09-02 on the dev box (AMD
680M, `renderD128`, Ubuntu 26.04: QEMU 10.2.1, libvirt 12.0, 15 GB RAM), on
two overlay clones of the clean Win11 26200 image — `win11-dbus` (stock
QEMU, `viogpudo`) and `win11-triton` (`/opt/triton`'s QEMU, Triton v0.3).
Tooling: `docs/windows-vm/dbus-display.py` (the listener and the input,
resize and clipboard client), `dmabuf-shot.c` (EGL import of the scanout,
for pixels), `win11-dbus.xml`, and `triton/` (`build-host.sh`, the domain,
the AppArmor rules, four QEMU patches). Both domains are left defined and
off. The recipe is in `docs/WINDOWS-VM.md`; what follows is what was seen.

### A. The dbus display, from a 2D guest

**A1 — `gl=on` + `viogpudo` → dma-buf: yes.** Registering a listener that
exports `org.qemu.Display1.Listener` and `.Unix.ScanoutDMABUF2` produces,
within 25 ms: a placeholder `ScanoutDMABUF2 1920x1080 XB24 modifier=INVALID
y0_top=false` (the surface QEMU shows before the guest's first frame), then
the real one — `AB24`, one plane, stride 7680, 8896512 bytes,
`modifier=INVALID`, **`y0_top=true`** — and `UpdateDMABUF` damage rects
after it. Damage is per rect, not per frame: a caret blinking in Notepad is
57 updates/s of ~2.4 kpx; a window being dragged is 8–11 updates/s of
0.16–0.53 Mpx (275 updates over a 25 s drag), which is `viogpudo`'s
`RESOURCE_FLUSH` cadence, not a frame-rate ceiling. Never a `Scanout`
(pixel) or `ScanoutMap` fallback.

**A2 — 26.04's QEMU is 10.2.1 and takes `ScanoutDMABUF2`** when the
listener offers it; `--v1` (not advertising) gets single-plane
`ScanoutDMABUF` with the same buffer. `modifier=INVALID` on the GL-texture
export means the fd is **not CPU-mappable** (`mmap` → `EPERM`; the plan's
"if LINEAR, dump a PNG" branch never applies to this path), so the pixel
proof is `dmabuf-shot.c`: `EGL_EXT_image_dma_buf_import` of the fd on the
same render node, `glReadPixels`, PNG — the Windows desktop, correct, once
the `y0_top` flip is honoured. Under `gl=on` `virsh screenshot` reports "no
surface": the listener is the only picture.

**A3 — p2p through libvirt.** `<graphics type='dbus' p2p='yes'>` plus
`virDomainOpenGraphicsFD` (python3-libvirt does the socketpair and the QMP
`add_client`); no `addr=`, no socket on disk. QEMU is the D-Bus
*authentication server* on both the control socket and the listener
socket, so both of our ends are `AUTHENTICATION_CLIENT`, and the listener
end needs `DELAY_MESSAGE_PROCESSING` until the object is exported, because
QEMU's first act is a synchronous `GetAll` on our `Interfaces` property
(that is how it picks `ScanoutDMABUF2`). **One control client at a time**:
`dbus_display_add_client_ready` moves the object-manager server to the new
connection and the previous client sees `The connection is closed`.
Listeners registered on either survive; the *control* interfaces
(Keyboard, Mouse, Clipboard) belong to the newest. The compositor must be
that client, and every tool that wants to poke the guest must go through
it.

**A4 — a late ack throttles, coalesces, never drops.** With
`--reply-delay 200` on every `UpdateDMABUF`, the guest's damage arrived at
4.3 updates/s of 1.39 Mpx mean (the rects merge while we hold the reply),
sixteen typed key chords took 10.4 s to be reflected, the guest stayed
responsive throughout, and nothing appeared in the domain log. The default
`DBUS_DEFAULT_TIMEOUT` (1000 ms) bounds how long QEMU waits. So: the reply
is a real frame ack, and a slow compositor slows the guest's display
without wedging it. (A *hung* one still holds the console's GL for the
timeout per frame; keep the import off the main loop.)

**A5 — resize works, given the service.** `Console.SetUIInfo` alone is
accepted and changes nothing. With the virtio-win 0.1.285 resolution
service installed (`vgpusrv.exe -i` from the `viogpudo-w11` directory — a
session-0 service, no user session needed), a new `ScanoutDMABUF2` at the
requested size arrived **30–45 ms** after the call, 8 of 8 (1600x900,
1280x800, 1920x1080). The intermittent "mode changed, no scanout" seen
before that count was Windows' display-off timeout (300 s on AC) blanking
the panel: `powercfg /change monitor-timeout-ac 0` / `-dc 0` ends it.
Multi-head not tried.

**A6 — clipboard: host→guest yes, guest→host needs a patch.** With the
`qemu-vdagent` chardev and Windows' `vdagent` 0.10.0 from virtio-win: our
`Clipboard.Grab` → the agent's request → our `GetText` reply landed in
Notepad. In the other direction nothing ever reaches the listener: the
Windows agent announces caps `0x46b7`, which lacks
`VD_AGENT_CAP_CLIPBOARD_GRAB_SERIAL`, and `ui/dbus-clipboard.c` drops every
serial-less grab. `triton/patches/0003` forwards them with serial 0; it is
in the fork build and **unverified** (the Triton guest has no vdagent, the
vdagent guest runs stock QEMU).

**Cursor.** No `CursorDefine` at all until `HWCursor=1` under the adapter's
class key (the INF ships `0`); after a reboot, `CursorDefine 64x64` +
`MouseSet` on every shape change and move, and the pointer leaves the
scanout. **Input:** `Keyboard.Press/Release` with qnum from an evdev-name
table (chords, `leftmeta+r`), `Mouse.SetAbsPosition` on the `usb-tablet`
(`IsAbsolute` true), press/release, and timed drags — all as expected.

**Stock-QEMU bugs met on the way** (patched in `triton/patches/`, not in
26.04's package): a guest reboot with a listener registered asserts
`dbus_scanout_texture: tex_id` and kills the VM (0001, no EGL context
current when the console switches surfaces); a listener that disconnects
stays registered and QEMU logs `Failed to call update: The connection is
closed` per frame forever (0002; upstream b6506de40f, after 10.2).

### B. Triton on the 680M

**Stack** (`triton/build-host.sh`, pinned): DXVK `osy/dxvk` 404240fdacf4
(native, headless, D3D11+DXGI only) → virglrenderer `utmapp/virglrenderer`
482f9d8b on **`macos-next`** (`-Dneptune=true -Dvenus=true`,
`-Drender-server-worker=process`) → QEMU `utmapp/qemu` 227f8b678b0f
(`utm-edition`, 10.0.12; `--enable-dbus-display --disable-spice
--enable-spice-protocol`, since the fork's SPICE display does not build on
Linux and the spice *protocol* headers are what builds the vdagent
chardev). Host packages beyond `apt build-dep qemu`: meson, ninja-build,
glslang-tools, libepoxy-dev, libvulkan-dev, libdrm-dev, libgbm-dev,
vulkan-tools; `deb-src` lines have to be enabled for `build-dep`. Two
traps: QEMU's configure finds the system virglrenderer unless
`PKG_CONFIG_PATH` names `/opt/triton`'s; and the `neptune` branch is dead
— against the v0.3 guest it desynchronises on DWM's first present
(`unknown transport command: subgroup=0 method=11`, worker SIGSEGV). The
wire protocol is unversioned: bump guest and host together.

**Under libvirt** (`triton/win11-triton.xml`): `<emulator>` in `/opt`,
machine `pc-q35-10.0`, `<memoryBacking><source type='memfd'/><access
mode='shared'/>` (blob resources map guest RAM), `blob='on'`,
`qemu:property neptune=true` and `hostmem` — **4 GiB hangs the guest in
early boot** (no display, no qga), 256 MiB boots and runs everything below;
the ceiling between them is not bisected — and `qemu:env` for
`LD_LIBRARY_PATH` and the two `NPT_*_LIBRARY_PATH`s. AppArmor denies the
custom emulator silently (nothing in the domain log; QEMU never starts,
or the render server's `Failed to create Vulkan instance` because the ICD
manifests are unreadable) — `triton/apparmor-*` add `/opt/triton` and
`abstractions/vulkan` (which also covers `/dev/udmabuf`, `amdgpu.ids`, the
shader caches) through `local/`. And `seccomp_sandbox = 0`: the render
server is `fork()`ed from QEMU and libvirt's default `spawn=deny` makes
that `EPERM`.

**Secure Boot: loads.** `viogpu3d.cat` is signed by `CN=Microsoft Windows
Hardware Compatibility Publisher` (issuer Microsoft Windows Third Party
Component CA 2014, not after 2027-05-11) — attestation-signed, not the
virtio-win test certificate. `Confirm-SecureBootUEFI` true; `pnputil
/add-driver viogpu3d.inf /install` on the live `viogpudo` device, reboot;
`Get-PnpDevice`: *Red Hat VirtIO GPU 3D controller*, `CM_PROB_NONE`;
`oem15.inf` (viogpu3d) outranks `oem7.inf` (viogpudo) at equal rank
`00F90000`. `dwm.exe` crashed once about two minutes after the live
switch, restarted, and was stable after. No test mode, nothing touched on
the varstore.

**The adapter**, `dxdiag`/`Win32_VideoController`: driver
100.6.101.58000, WDDM 2.2, DDI 11.1, feature levels 11_1 … 9_1, 256 MB
"dedicated" (the `hostmem` BAR), LUID `0x72d8`.

**DWM runs on it.** `\GPU Engine(*)\Utilization Percentage` for the
`dwm.exe` instances: 31–75 % while a window is dragged, 0 on `win11-dbus`
(WARP has no engine counter at all). Windows created **one Neptune context
per D3D11 device** — Settings, Explorer, the shell hosts, every Edge GPU
process attempt — each its own `virgl_render_server` worker with its own
Vulkan device, logged `npt: created Neptune context N` (459 created over
the session, ~50 alive at a time).

**Scanout stays a dma-buf — after a listener fix.** DWM on Triton
presents by *flipping* a triple-buffered blob chain: `SET_SCANOUT_BLOB` +
`RESOURCE_FLUSH` per frame (QMP `trace-event-set-state` on
`virtio_gpu_cmd_set_scanout_blob`/`virtio_gpu_cmd_res_flush`), ~58/s
during a drag. The listener sees `ScanoutDMABUF 1920x1080 AR24
modifier=LINEAR y0_top=false`, 8294400 bytes, a *new* one per frame — the
fork is 10.0-based and has no `ScanoutDMABUF2`. Stock `ui/dbus-listener.c`
answers the guest's release of the buffer it just flipped away from with
`dbus_scanout_disable`, i.e. a `Disable` per frame, and that `Disable`'s
discard mark makes the dbus filter drop the next `ScanoutDMABUF`: measured
224 `UpdateDMABUF` / 223 `Disable` / 22 `ScanoutDMABUF` in 9.8 s, the
listener holding a stale frame. `triton/patches/0004` remembers the last
scanned-out `QemuDmaBuf` and ignores release of a superseded one:
352/352/0 in 10.2 s, every frame delivered. The same code is in upstream
QEMU; the bug only shows with a guest that flips, which no 2D guest does.
A degraded state was also seen before one reboot — `SET_SCANOUT_BLOB` only
at drag start and end, with `DxvkContext: Cannot relocate image: Current
usage 0x17, flags 0x8 … Requested usage: 0x80` per flip in the domain log;
a fresh boot flips every frame. Cause unknown; recorded as instability.

**Chromium is not accelerated.** Edge's `edge://gpu`: every feature
*Software only*, GPU0 vendor/device 0, "GPU process crashed too many
times with software GL". The log messages say why: ANGLE's D3D11 backend
fails in `ResourceManager11::allocate` — `HRESULT 0x887A0005`, removal
reason `0x887A0020 DXGI_ERROR_DRIVER_INTERNAL_ERROR`, "Error allocating
RasterizerState" (later a vertex shader; a Skia program that "link failed
but did not provide an info log"), then `Present1 … device suspended`,
`RESULT_CODE_GPU_EXIT_ON_CONTEXT_LOST` three times and `kFatalFailure:
Failed to create shared context for virtualization`; the D3D11 video
device is absent too (`Failed to retrieve video device`). Nothing matching
appears host-side: the device-removal is raised inside the guest UMD. Dawn
sees only SwiftShader and the D3D12 "Basic Render Driver" (D3D12 is not in
the driver, and `libvkd3d-proton-d3d12.so` is not built host-side — the
`NPT_D3D12_LIBRARY_PATH` warning is benign). So WebView2, Electron and
Edge run on software GL on Triton today, while DWM and win32 D3D11 apps
(the Settings and Explorer chrome, Notepad's DirectWrite path) are on the
GPU.

**The hour of ordinary use: not reached. The first run died on host
memory at 19 min; a sampled 15-minute re-run held.** Scripted drags (the
flip chain), Settings and Explorer through Win+R/Win+E, an iteration every
50 s. The first run ended 18 min 53 s into the guest's uptime, four
iterations in, with the kernel OOM-killing QEMU (`Out of memory: Killed
process … (qemu-system-x86) … shmem-rss:5817108kB`, machine scope peak
11.1 GB + 2.4 GB swap, ~55 render-server workers alive, the memfd 1.8 GB
into swap) — a guest that had spent the previous quarter-hour of the same
boot on the Edge tests above, i.e. on a GPU process creating D3D11 devices
in a crash loop. The re-run (a fresh boot, a watchdog at MemAvailable
< 900 MB, `memstat.sh` sampling MemAvailable, GTT and the worker count
every 15 s, an iteration every 30 s) ran its whole 12-minute action
window, 23 iterations, and was destroyed on schedule at 15 min of uptime:
workers 14 at the idle desktop → 25–28 in steady state (contexts came and
went with Settings and Explorer; no monotonic growth), GTT 0.9 → 1.6–1.8
GB, MemAvailable 3.9 → 2.8 GB with no trend after the third minute, swap
flat, the watchdog never fired, and `virsh destroy` gave everything back
(MemAvailable 12.0 GB, GTT 141 MB, Shmem 0 — nothing leaked). Where it
goes: the guest's 8 GiB memfd is resident within 30 s of boot (MemAvailable
3.9 GB on the 15 GB host), and each live D3D11 device costs its worker
~55 MB of GTT on top (14 → 28 workers was 0.95 → 1.73 GB) — pages that are
neither the guest's RAM nor anyone's RSS, so `free` does not show them and
the OOM killer, when it comes, picks the biggest process, which is the
guest. So the budget holds for the desktop, Settings and Explorer, and
does not for a Chromium that churns devices; what an hour of *real* use
does in between is unmeasured. No `Display` 4101 (TDR) and no
render-server crash in either run; the guest itself was healthy until the
host killed it. A 16 GB laptop running Triton wants a 6 GB guest, or fewer
D3D11 devices, and this is the finding that keeps Triton off the shipping
tier for now. (The re-run also re-proved the one-client rule by accident:
the first run's loop was still alive and driving the same domain, and each
time its drag overlapped the re-run's, the earlier connection got `The
connection is closed (18)` mid-drag — 6 of 23 iterations. The load above
includes those extra drags; `mouse --drag` now reports the step it died
at.)

**Verdict.** The two facts the design rested on hold: a 2D Windows guest
scans out as dma-bufs at guest rate through the dbus display on stock
26.04 (Layer 1 is a zero-copy path, and M1 can be planned on it), and
Triton loads under Secure Boot and keeps the scanout on virtio-gpu so
Layer 1 is unchanged when it lands. What Triton does *not* yet do is run
Chromium or fit an 8 GB guest on a 16 GB host for an hour — two blockers,
both upstream, both nameable in a bug report. The QEMU fork is required
(the capset lives only there), and both stock and fork need `patches/0004`
before any flipping guest looks right through a dbus listener.

## Sources

QEMU: `docs/interop/dbus-display`, `ui/dbus-display1.xml`, `ui/dbus-listener.c`
(gl_block ack; `dbus_gl_gfx_switch`), the multi-plane pull (2025-05), the
DMABUF3 series and chergert's 2026-08-21 post; libvirt `formatdomain` for
`<graphics type='dbus'>`; the `qemu-display` crate and libmks as client
references. virtio-win: `viogpudo`, PR #943, issues #1391/#1314/#560, the
`vgpusrv` installer issue #86; `vioser`, `viosock`. Drivers: UTM's Triton
announcement (2026-08-09, v0.3 2026-09-01), `arehnman/yttrium-virtio-gpu`,
`winboat-org/helios`; Collabora's virglrenderer state post (2025-01);
QEMU 9.2 Venus. Intel: `strongtz/i915-sriov-dkms` releases (2026),
Phoronix on Xe SR-IOV in 6.17/6.18 and the MTL/LNL/ARL gap (2026), Derek
Seaman's guide (updated 2026-05). AMD GIM (2025-04). NVIDIA vGPU 19.x
support matrix; `vgpu_unlock`. Looking Glass B7 release notes, IDD nightlies,
LGMP/KVMFR docs; muxless guides (ArshamEbr 2025, lantian). VMware Workstation
free (2024-11) and 26H1 (2026-05); VirtualBox 7.2. Home edition: WinApps docs
and `RDPApps.reg`, WinBoat 0.9, Cassowary, dockur/windows; rdpwrap forks;
Thinstuff; Microsoft's Remote Desktop client end-of-support posts; the OEM
Windows 11 UseTerms PDF (April 2024) for 2(c), 2(d)(iv), 2(d)(v); agent
workspace (Windows blog 2025-10-16, support page); Windows MCP/ODR docs.
Agents: MS Learn for PrintWindow, WGC, DWM thumbnails, SendInput, UIA;
Chrome's UIA rollout post; UFO² (arXiv 2504.14603); OmniParser V2; cua.ai's
Windows driver write-up (2026-05). P2V: simgunz (2021) and the Proxmox
same-install thread (2024); 24H2 Device Encryption reports (2024–2025);
KubeVirt #13929/#15701; virt-v2v 2.8 notes; Red Hat KB on the virtio boot
binding.
