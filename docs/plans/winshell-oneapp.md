# winshell-oneapp — launcher, tray, dock and wallpaper in ONE app

Branch `winshell-oneapp`, explored 2026-08-21 on the physical box. The
question: can the shell's surfaces — the dock, the desktop
(wallpaper + icon grid), the launcher, with the tray already living in the
dock — be ONE process instead of a process per surface?

**Answer: yes, and the prototype runs.** `WinShellBar.exe --oneshell` brings
up the dock as the process's implicit view and the desktop and launcher as
two more ENGINE VIEWS of the same process (`flwin32_surface.c` +
`Win32Surfaces`), riding the multi-view path the popup surfaces proved.
Driven on the box (3840x2160 @200%, explorer absent): wallpaper + icon grid,
full dock with hosted tray and live clock, Start opening on the toggle
broadcast, typing filtering the app list ("note" → Best match), click-away
dismissal. Pixel-identical to the process-per-surface shell.

## Why bother

Measured on the box, same build, same session:

| | processes | working set |
|---|---|---|
| process-per-surface | dock + desktop + launcher | 108 + 151 + 89 = **348 MB** |
| one-app | `--oneshell` | **172 MB** |

Half the memory — one engine, one Swift runtime, one texture registrar —
and that is BEFORE consolidating the duplicated work the merge exposes
(DockBloc and LauncherBloc each walk the Start Menu and rasterize their own
icon set; one catalog + one IconCache is the obvious follow-up). Toggles
stop being broadcasts into the void: the launcher window exists from
process start, its tree already composited.

## The architecture

- `flwin32_surface.c` — the popup machinery generalized to shell surfaces.
  Two kinds: `DESKTOP` (full monitor, WM_WINDOWPOSCHANGING-clamped to
  HWND_BOTTOM, shown SW_SHOWNOACTIVATE **on its view's first composite** —
  the 7c8cc9a empty-first-paint bug is unreachable by construction) and
  `OVERLAY` (sized, work-area-anchored, DWM-rounded, created hidden,
  ACTIVATABLE, answers the launcher toggle broadcast in its own wndproc,
  dismisses on WA_INACTIVE).
- `Win32Surfaces` (Swift) — shares Win32PopupSurfaces' builder registry
  (one `multiViewContentBuilder` per process, so one table) and its
  first-composite hook; carries per-surface toggle callbacks WITH the new
  visibility, so the tree never has to ask.
- `--oneshell` — the dock branch plus `openOneshellSurfaces()` in the
  dock's initState (the engine exists exactly then): desktop view (gated on
  explorer-absent / STARLING_DESKTOP_TRIAL, same as the plan mandates) and
  launcher view. `StarlingDesktop`/`StarlingLauncher` take an optional
  `surfaceId` and otherwise run unchanged.

## What the exploration settled

1. **A hidden engine view still composites.** The launcher's tree mounts at
   process start while its window is hidden — `[Adapter] view 2 first
   composite` before any toggle. The ENTIRE parked-overlay apparatus of the
   process world (full-size parks, same-size WM_SIZE kicks,
   LauncherPreload's careful threading) is unnecessary in this
   architecture. First open is ShowWindow on current content.
2. **Keyboard rides real focus.** The overlay takes activation and focuses
   its view child; keys arrive tagged with the view and land in the
   launcher's tree through the ordinary focus manager. Search works with no
   RegisterHotKey and no WM_CHAR forwarding. The framework's focus manager
   is process-global, but only the launcher's field ever holds focus, so
   sharing it across three trees caused no conflict in practice.
3. **HWND_BROADCAST does not reach invisible OWNED windows.** The first cut
   made the overlay owned by the dock's window (for z-order) and Start
   silently ignored every toggle — PostMessage(HWND_BROADCAST) delivers to
   invisible windows only when they are UNOWNED (the process-world launcher
   was unowned by accident of being a process). The surface is unowned;
   TOPMOST + activation-on-show provides the z-order instead.
4. **"The host's client size" is a process-world assumption.** The desktop
   bloc measured the process host's window — in one-app that is the dock's
   246pt-tall panel, giving a one-row icon grid and a dock-sized wallpaper.
   `flwin32_surface_client_size`/`Win32Surfaces.clientSize` answer for the
   surface's own window; same for the OLE drop target, which must register
   on the desktop's window, not the dock's.
5. **The desktop's process-wide key hook coexists.** Only Desktop (and
   Files, not consolidated) set `PlatformDispatcher.onKeyData`, and the
   desktop's dispatches FocusManager first — so dock and launcher keys are
   unaffected. Real per-view key routing is still the honest design for
   the full version.

## Not done, known, and next

- **Popups from surface trees are anchored to the wrong window.**
  Win32PopupSurfaces converts host-client points against the DOCK's window;
  the desktop's right-click menu computed in desktop-client points will
  land offset (the fallback in-window menu still works). Fix: an `anchor:`
  (surface id) parameter on popup open, converting against that window.
- **Notifications, banners and Run** are still their own processes. Same
  consolidation applies (three more overlay-kind surfaces, channel toggles);
  another ~250 MB across the three.
- **One catalog, one icon cache**: DockBloc + LauncherBloc each walk the
  Start Menu and rasterize 79 icons. Post-merge they can share.
- **`--session` integration**: the supervisor should spawn `--oneshell`
  instead of dock + desktop when the mode graduates; the crash-loop
  contract gets SIMPLER (one critical child instead of two), at the cost of
  a wider blast radius per crash — the trade to weigh before switching the
  default.
- **Multi-monitor**: surfaces open on the host's monitor only (the popup
  layer's same assumption).
- Escape inside the launcher unfocuses the search field (TextBox behavior)
  but does not yet dismiss the panel; click-away and the toggle do.

## Verification on the box

`C:\dist\oneshell-run.ps1` (baseline + teardown), `StarOneshell` task
(launch), `oneshell-verify.ps1` (processes/logs), `StarDrive2` (types into
search + click-away). Oracles: `[WinShell] oneshell desktop view: 1` /
`launcher view: 2` in `C:\st\oneshell.out`, `[Adapter] view N pipeline
created / first composite` on stderr.
