# winshell — task list

The Windows shell branch: WinShellBar (dock, launcher, settings, files) on
the Win32 host. This file tracks what remains, ordered by what a hand on the
mouse notices first.

CHECKPOINT 2026-08-21, later still — both machines reconciled: NOTHING
IS IN FLIGHT anywhere. Both repos pulled and pushed on both boxes; the
pair is winshell `cc36773` + engine `starling` `e0ed4e31068`. **Every
phase of winshell-shell-replacement.md is now DONE and VM-proven**:
0a namespace, 0b popup surfaces, 1 explorer-the-app, 2 the desktop
surface (gate run from the Linux box — it caught the first-frame bug
only explorer-absent can see, fixed 7c8cc9a), 3 tray/appbar, 4 banners
+ Run, 5 the session slot, whose Shell= soak passed through real
Winlogon logons: register → reboot → our session with startup replayed
and a real HKLM RunOnce consumed exactly once → kill/respawn →
kill-kill/bail → explorer back with taskbar restored → voluntary
unregister → stock explorer. Two soak-caught bugs (the supervisor's
console window, the bail's taskbar state) fixed and re-proven in a
second round. The VM ends on stock explorer; both boxes' dists run the
final tree. Cross-machine plumbing that made the soak drivable: the
build host's SSH key is in the Linux host's authorized_keys, so either
box can drive the VM harness (docs/windows-vm, `-d win11-gpu`, host
192.168.68.61). One local note for the LINUX desktop: e0ed4e31068
touches shell/common (shared core), so this box's host_debug /
host_release binaries predate the checkout — rebuild before the next
Linux run that cares. WHAT REMAINS of the plan: the long-tail audit
(DDE ShellExecute paths, autoplay, safely-remove — VM checks), EV
signing (release concern), and the standing follow-ups: desktop OLE
drag OUT, multi-monitor, wallpaper watch, Alt-Tab previews, the OSD
survival check, engine frame-dispatch, and the idle-CPU items in
winshell-perf.md's addendum (unfocus-on-hide, NotificationChanged over
the raw ABI). **Half the parked-engine floor is diagnosed and fixed** —
our own 8 ms main-queue drain timer, not the engine; both hosts now wait
on libdispatch's wakeup handle. Measured on the physical box 2026-08-22
with two identical processes side by side: **0.447% vs 0.882% of one
core, exactly 2.0x**, ~2 points across the five surfaces. The other half
of the floor survives the fix and is still the engine's own idle cadence
(winshell-perf.md's addendum has the method and the caveat about nested
modal loops). **The other half is fixed too**, in the engine: the
DirectManipulation gesture poll (a 14 ms `WM_TIMER` armed per view at
creation and never killed) now runs only while a gesture is in flight —
engine `2974d27e73f`, on the engine's mainline `starling`.
Same one-binary A/B: **0.013% vs 0.786% of one core, 62.5x**, and 1
context switch a second for a parked surface. The whole idle session is
**2.92% of one core**, and then **0.31-0.73%** once the shell stopped
drawing at idle: the dock rebuilt the whole 4K chrome twice a second to
repaint a clock with no seconds and a status poll whose answer had not
changed, and the parked Run dialog blinked a caret in a window nobody
could see (1.9 frames/s). Both fixed, and the clock then moved OUT of the
shell-wide tick entirely — `DockClock` schedules itself to the next minute
boundary and rebuilds its own leaf, leaving a 5 s tick for the two guards
that are periodic for nobody in particular (chrome at idle: 1.64% → 0.44%
→ **0.13%**). An ordinary parked window reads 0.000%. `dwm` fell with them, ~5% → **0.05%**: it was recompositing the
colour-keyed layer because we kept redrawing it, not because it exists.
Then the polls: the notification centre only ticks while it is on screen
(it is opened by the user, so a hidden one has nothing to keep current),
and the banner — the one surface no gesture brings up — got its arrival
event wired through the raw ABI, which **Windows refuses to an unpackaged
process** (ERROR_NOT_FOUND), so its poll follows PRESENCE instead: 2 s
while someone is at the machine, 15 s while nobody is. Bigger than either:
`Task.detached { while true { await Task.sleep } }` costs ~46 context
switches a second on Windows and is now a libdispatch timer. Whole session
at idle: **2.34% → 0.65% → 0.08% of one core**, dwm 0.03%. Then the
chrome's own 5 s tick went the same way — five subscriptions
(`WM_POWERBROADCAST`, `WM_SETTINGCHANGE`, `TaskbarCreated`, WLAN + IP
callbacks, `RegNotifyChangeKeyValue`) in `Win32Status.watch`, leaving the
chrome at **0.00% and 2 context switches a second**, and a promoted tray
icon reaching the strip in 1.2 s instead of up to five. Two polls remain:
the banner store (the OS refuses the arrival event to an unpackaged
process) and the supervisor's 5 s wait timeout.

**The dock's flyouts dismiss on click-away now** — the tray overflow that
opened and never closed, and Quick Settings and a tile's menu with it.
They are drawn INSIDE the panel window and the overhang around them is a
colour-keyed hole, so a press anywhere else was never ours to see: each
flyout's "outside closes it" branch only ever ran for presses that landed
on the strip. The panel now holds activation while a flyout is down (the
one-view launcher layer's handoff — WS_EX_NOACTIVATE takes activation
programmatically), so click-away arrives as WM_ACTIVATE/WA_INACTIVE, and
`takeFocus`'s global Escape hotkey closes a flyout for free. A second
press on the chevron closes it too: the overflow handler consumes that
one now, where before it closed the flyout and the caller's toggle
reopened it in the same press. Verified on the box: open → click the
desktop / the chevron / Escape all leave the identical closed frame, and
the hover labels a stuck flyout used to suppress come back.

## The desktop surface (wave 2) — built 2026-08-21, VM trial pending

`--desktop`: wallpaper and the icon grid at the bottom of the z-order,
the plane explorer's Progman owns until the Shell= endgame. Driven live
on this box under STARLING_DESKTOP_TRIAL=1 (the gate in main.swift
otherwise refuses while explorer runs — the plan's own decision,
enforced): wallpaper cover-fit, icons with real textures and thumbnails,
click/Ctrl-click selection, double-click opening through the shell, icon
drag persisting to our own store (`--print-desktop` read it back from a
separate process), and both right-click menus on popup surfaces — the
desktop menu is 0b's first consumer with NO parent window at all.

What it took, beyond assembly of parts that already existed:
- **The window shape** is `flwin32_host_set_desktop`: full rcMonitor (the
  wallpaper runs under the dock), WS_POPUP + TOOLWINDOW, pinned to
  HWND_BOTTOM through every activation by a WM_WINDOWPOSCHANGING clamp —
  focusable but never raised, which is what explorer's own desktop is.
- **The wallpaper raster** (flwin32_wallpaper_raster) decodes through the
  shell's image factory and cover-crops with a hand bilinear sampler.
  Hand-rolled because GDI would not say which way was up: a StretchBlt
  between DIB sections came out vertically flipped through two different
  orientation "fixes", and GetDIBits rows arrived inverted even against a
  top-down request — the sampler now walks the source bottom-up, found
  EMPIRICALLY, with a comment telling the next reader to probe before
  believing either orientation.
- **ShellMenuModel grew surface hooks** (backgroundDirectory / activate /
  openWith, joining afterVerb): the menu reached into the file explorer's
  bloc for those four things, and in the desktop's process that bloc is
  dormant — the first background menu asked the shell about an EMPTY
  path and came up with three rows and no New submenu. The hooks default
  to the old Files behaviour; the desktop redirects them.
- Icons are per PATH (a desktop is shortcuts, each with its own face and
  arrow badge), unlike the listing's per-type keys; labels are the
  shell's display names, white with the drop shadow that survives a
  white wallpaper.

- **A monitor-sized window shown WITH ACTIVATION is a "fullscreen app"
  to the shell, and it demotes every appbar.** The desktop surface's
  first activated show knocked the DOCK out of topmost — it landed
  beneath the bottom-pinned surface and stayed (a manual topmost
  re-assert stuck, which is how the trigger was pinned to the show).
  flwin32_host_show now shows a desktop-mode window SW_SHOWNOACTIVATE;
  focus follows the first click, which does not trip the check. For the
  endgame: when OUR tray service is the appbar authority (explorer
  absent), it must special-case ABN_FULLSCREENAPP for the desktop's own
  window, or the same demotion returns wearing our name.

V1 boundaries, mostly closed in the second pass (2026-08-21, later),
each lifted from the file explorer's machinery and driven live:
- **Rubber band**: same BandModel/BandOverlay split; the covered set is a
  per-item cell intersect (desktop cells sit at arbitrary stored
  positions, not list order). Ctrl-drag adds to the selection it started
  over.
- **Inline rename**: F2, the menu pill's Rename cell, click-away commits,
  Escape cancels. The basename arrives SELECTED (Explorer's gesture) —
  the first cut prefilled with caret-at-end and a driven type APPENDED,
  renaming the file to a concatenation. The only honest cancel is
  `onFocusChanged`: the field consumes Escape internally, so no shortcut
  handler ever sees it (the typed-path lesson, reapplied). And bloc-level
  Ctrl chords must be gated off while a rename is open — a chord the
  field does not consume falls through, and Ctrl+A selected every icon
  under the open edit.
- **Keyboard**: arrows walk the grid spatially (nearest item in the
  direction, same column/row preferred), Enter opens, Ctrl+A/C/X/V, and
  Ctrl+Z through `FilesBloc.performUndo` — the undo case extracted to a
  static so the desktop pops the same per-process journal the explorer
  feeds. Verified: copy-paste on the desktop, Ctrl+Z recycles the copy.
- **The menu pill's Paste/Rename cells** were the remaining dormant-bloc
  couplings: ShellMenuModel grew `pasteInto`/`beginRename` hooks
  (defaults keep the explorer's behaviour). Paste-into-folder-icon
  driven: clipboard file landed inside the folder.
- **OLE drops IN**: Win32DropTarget on the desktop window; external files
  land in the Desktop folder AT THE DROP CELL (written to the position
  store before the refresh) or in the folder icon under the pointer,
  drawn lit. Driven from the Files window: same-volume default moved the
  file, placed at the drop point.
- **Icon drag onto a folder icon** moves the file into it (Explorer's
  gesture); any other occupied cell still snaps back.
- The position store PRUNES dead paths at refresh: `placed()` reserves
  every stored cell, so a stale key (renamed/deleted file) was a hole no
  icon could ever fill.

Still deliberate not-yets: OLE drag OUT (an icon drag stays a
window-internal reposition — making tile drags real DoDragDrop with the
desktop as its own self-drop target is the honest architecture, a
session of its own), multi-monitor, wallpaper read once at start.
Also seen again, worth its weight: **the appbar demotion returns on
ACTIVATION, not just on show.** A minimize-cascade that lands foreground
on the monitor-sized desktop window trips explorer's fullscreen-app
check and the dock loses topmost — SW_SHOWNOACTIVATE only cured the
first show. Trial-mode artifact while explorer is the appbar authority;
the endgame's ABN_FULLSCREENAPP special-case (tray phase) is the real
fix, and this is more evidence it must key on the WINDOW, not the show
path. That gate has now been RUN (below), and with explorer ABSENT the
demotion did NOT return: work area held at 712 with the dock above the
desktop in the z-order, through a click-activated surface and an app
launch. So the artifact really is explorer-as-appbar-authority, and the
endgame's special-case is still the fix to write, not a bug to chase.

Small gap noticed while driving: the file explorer window itself has NO
F5 (refresh is the toolbar button only); the desktop has it. One case in
Files.handleShortcut when track 1 next opens those files.

**THE GATE IS RUN — PASSED 2026-08-21, and it caught a real bug.** The VM
trial with explorer absent: killed explorer, launched `--desktop`, and the
surface came up BLACK and stayed black. Everything else passed once that
was fixed — wallpaper cover-fit the right way up, both icons with real
textures, shortcut badges and shadowed labels, click and Ctrl-click
selection, the background menu (New submenu populated — the dormant-bloc
hooks hold with explorer gone) and the icon menu with its pill row, both
on popup surfaces with no parent window; icon drag snapped to its cell and
persisted (`desktop-icons.json` read back `NVIDIA App.lnk: [4,2]` from a
separate process); double-click launched Edge THROUGH the shell with
explorer absent; the dock kept its reservation (work area 712, dock above
the desktop in the z-order — the ABN_FULLSCREENAPP demotion did not
return); and explorer restored cleanly with all four surfaces alive.

**The bug the gate existed to find: the desktop never got its first
frame.** `desktop_apply_placement` runs BEFORE the tree mounts (the
restyle has to settle the client size) and shows the window with
SWP_SHOWWINDOW, so the one WM_PAINT the child gets paints an EMPTY tree.
By the time `flwin32_host_show` runs the window is already visible, so
ShowWindow is a no-op, UpdateWindow finds nothing invalid, and no second
paint is ever requested. **With explorer running its window traffic
invalidates the desktop within a frame or two and the content appears** —
which is exactly why the dev box's trial mode looked perfect and why only
the explorer-absent gate could see it. Fixed by forcing the redraw in the
desktop branch of the show, the same call and the same reason as the one
in set_visible. A nudge from outside (SetWindowPos by one pixel) was what
proved the tree was fine and only the frame was missing.

**Re-run on the FINAL merged tree** (the second pass landed mid-gate):
first frame correct cold with explorer absent, the dragged position
remembered across the restart, the rubber band drawing live and taking
the icon it swept, F2 opening the inline rename with the basename in the
field — then explorer restored, four surfaces alive, the shortcut
untouched. So the verdict covers what is actually on the branch, not the
tree the gate started against.

Two harness lessons, both paid for in this run: an injected DRAG needs
`/rl HIGHEST` **and** a hidden wscript wrapper — a bare
`schtasks /tr powershell ...` opens a console that takes the foreground
and eats the gesture as a QuickEdit text selection (an orange block in
the screenshot is the tell), and UIPI drops medium-integrity input into
the elevated shell's windows. wclick.py already does both; copy it.
Screenshot DURING the hold to tell "gesture not delivered" from "drop
rejected".

## Popup surfaces (0b) — landed and verified 2026-08-21

Track 2's prerequisite, and the last one: every panel of the file
explorer's menu — the menu, its submenu, the command bar's flyouts — is now
its own POPUP WINDOW, so it overhangs the window's edges and outgrows its
height, the way Windows' own menus are windows. Driven on the box: a
right-click near the window's right edge opens a menu standing mostly on
the desktop, "Give access to"'s submenu draws beside it in a second popup,
"Show more options" grows the popup in place, a verb runs (Copy as path →
the clipboard), and dismissal works from all three directions (a click in
the window, a click in another app, the popup rows themselves).

The machinery, reusable as-is for wave 2's desktop menu, tray flyouts and
toast banners: `flwin32_popup.c` opens/places/closes a second engine view
(FlutterDesktopEngineCreateViewController — exported from
flutter_windows.dll but declared only in upstream's INTERNAL header; the
declaration is copied into the .c) inside a WS_POPUP | WS_EX_NOACTIVATE |
TOOLWINDOW | TOPMOST window, addressed in HOST-CLIENT LOGICAL POINTS;
`Win32PopupSurfaces` (Swift) keys content builders by the returned view id
through the adapter's existing multiViewContentBuilder — the multi-view
path the Linux multi-monitor work built, never before used on Windows.
DWMWCP_ROUND + an opaque panel fill IS the native menu anatomy: DWM clips
the surface to the radius and paints the menu shadow outside it. NOACTIVATE
means the keyboard never leaves the host window (menu keys keep working
unchanged), and the engine view never takes focus on a click — verified in
the embedder: FlutterWindow::Focus runs only on an explicit request.

Three findings, each bought with a black rectangle:
- **The swift-mode render path could only commit ONE view per pass**
  (engine fix, shell.cc). The render callback ended the frame after every
  view's Render; EndFrame consumes the pipeline's single producer
  continuation, so the second view's tree in the same Swift pass staged
  against an empty continuation and was silently dropped — the submenu
  composited exactly once, in the same pass as the resizing menu, and
  stayed black forever. The commit is now POSTED to the tail of the
  current UI task: all views of a pass stage first, one EndFrame commits
  them (Dart-mode batching restored), and inside a real vsync task the
  posted commit finds the recorder null and no-ops. This also fixes the
  same latent drop on Linux multi-monitor, where it self-healed and hid.
- **Warming a derived cache outside a tracked build starves observation**
  (geometryEpoch). syncPopups reads mainMenu to size the popup, filling
  the @ObservationIgnored cache; the popup's build then hits the warm
  cache, never reads the observed rows underneath, and misses the next
  change — the popup window resized for the full verb tier while the
  panel inside kept drawing the fast tier. Every geometry mutation bumps
  an observed epoch (inside scheduleSync, which every mutator already
  calls) and the surface build reads it.
- **Popup calls must be DEFERRED off the popup's own event dispatch.** A
  press arrives from the popup's view; closing that view inline would
  destroy the window under the call stack delivering the event. All popup
  window ops go through one coalesced main-queue sync (scheduleSync).

The in-window drawing survives as the fallback when a popup cannot be
created (popupsEnabled=false, flipped on first failure), sharing the same
panel painters so it cannot drift. Menu clamping switched from the window
to the monitor's WORK AREA (flwin32_popup_frame). Oracles:
"[Adapter] view N pipeline created/first composite/disposed" and
"[Win32Popup] view N has no content builder" on stderr.

How a popup becomes visible, tightened after the box showed both faults:
a popup window is created HIDDEN with a menu-coloured erase brush (the
host's black class brush flashed a black rectangle for the frames before
the first present — burst screenshots caught it), shown no earlier than
its view's first composite (multiViewFirstComposite, the adapter's
per-view hook), and a menu's popup holds PAST that until the menu has
SETTLED — the full verb tier in, or a flyout's rows, which arrive whole
(Win32PopupSurfaces holdUntilRevealed/reveal, plus a 1.5s hang rescue).
The two-tier query stays, but the fast→full growth now happens off
screen: an earlier cut that revealed on a 250ms budget showed the fast
tier exactly when the full one was slow (a cold shell's first menu,
~700ms) and the full set then reshuffled rows under the pointer — "Add
to Favorites" lands mid-panel and everything below it stepped down.
Waiting is what native does; warm menus appear once, complete, in
~100-300ms, and the cold first menu costs what Explorer's own does.

Not done, deliberately: per-pixel-alpha acrylic in popups (the popup fill
is opaque; real cross-window acrylic needs DirectComposition, not a GL
swapchain colorkey), and the launcher/notification-centre overlays still
use their own full-window machinery rather than popup surfaces.

Updated 2026-08-21: every visual-polish, functional-gap and hygiene item
is done -- what remains is the deferred-by-decision section below and the
small not-yets recorded inside ticked entries (tab reorder/tear-off,
column reorder, custom drag imagery, edge autoscroll).

Updated again 2026-08-21, later: PHASE 1 OF THE SHELL-REPLACEMENT PLAN IS
COMPLETE (namespace enumeration + bin/Network/zip, Ctrl+Z, thumbnails,
typed path entry, subtree search, Quick Access pinning -- sections
below). Track 1 rejoins the wave plan (winshell-shell-replacement.md);
by that plan the next work is wave 2's desktop surface (needs 0a, done
here, AND 0b's popup surfaces from track 2) or whatever track is open.

## Quick Access pinning — landed and verified 2026-08-21

The sidebar's pin section is now EXPLORER'S pin set, not a hardcoded
six-name list: read from the Quick Access folder and re-read after every
shell verb (a pin/unpin IS a shell verb, and nothing else announces one).
Pin from any folder's context menu (pintohome was already in the modern
verbs); unpin by clicking the row's pin glyph, which runs unpinfromhome
through the same location-addressed menu session the Recycle Bin's
Restore uses. Round trip driven on the box: pin docs -> row appears,
click its pin -> row leaves, and the shell's own set confirms both.

Three findings, each probed before believed:
- QUICK ACCESS REFUSES BHID_EnumItems outright (the modern enumeration
  that works for the bin, Network and zips) while answering the classic
  IShellFolder::EnumObjects. flwin32_ns_list grew the classic fallback,
  and the menu session's resolve_item switched to the classic walk
  entirely -- the folder handle it binds to walk is exactly the parent
  GetUIObjectOf wants.
- The bare "::{679F85CB-...}" spelling DOES NOT PARSE for Quick Access
  (it does for the bin and Network); the "shell:::{...}" URI does. The
  NamespacePlace constant carries the working spelling and a warning.
- Pinned vs merely-frequent is System.Home.IsPinned, resolved BY NAME at
  runtime (PSGetPropertyKeyFromName -- the SDK ships no PKEY_ for it).
  Everything outside Quick Access answers -1/unanswered, which must not
  be read as "not pinned".

`--ns-probe <location>` joined the CLI oracles (it is how the two
enumeration findings were caught), and `--menu-probe` takes `--location`
now -- the QA child's menu is where unpinfromhome lives; the folder
addressed by its own path only ever offers pintohome.

## Subtree search — landed and verified 2026-08-21

Phase 1's last functional gap but one: the search box now walks the
subtree behind the instant in-folder filter -- the honest cancellable-BFS
version the plan asked for, not an index. Hits stream in batches of 50
(first results while deep directories are still reading), named by
RELATIVE path so the existing Name column says where each hit lives,
appended below the folder's own matches. 300ms debounce so "notes" costs
one walk, not five; generation token + Task cancellation kill a stale
walk on retype or navigation; the filter surviving navigation restarts
the walk under the new root. Deliberate limits, each the cheap honest
choice: 1000 hits, 500k entries scanned (junction-loop backstop), no
descent into symlinks/junctions, and no walk at all on This PC or a
namespace listing (FileManager cannot enumerate those; the in-memory
filter still applies). The status bar appends "searching…" while the
walk runs, because 10% done looks identical to finished. Verified on the
box: "TextBox" typed over the sdk tree surfaces
Sources\Flutter\FluentUI\...\TextBox.swift within a second.

## Typed path entry — landed and verified 2026-08-21

Phase 1's address-bar edit: a click on the breadcrumb's empty space flips
the crumbs into a field over the same footprint, everything selected
(typing replaces, Explorer's gesture). Enter expands %VARS%, trims Copy-
as-path quotes, roots a bare "C:", takes "This PC" by name, and navigates
-- directories, "::" locations and zips through the listing's routing, a
FILE by opening it. A nonexistent path stays in the field to be fixed;
Escape backs out; a navigation landing underneath (sidebar click, Back)
folds the field back to crumbs, checked against the directory it opened
over.

Took a framework addition: FluentTextBox/MacosTextField grew
`onFocusChanged`. The field consumes Escape internally (unfocus), so an
ancestor's shortcut handler NEVER sees it while the field is focused --
the first build left the field open-but-unfocused forever, and the only
honest dismissal signal is the focus node's own. The inline rename has
the same latent quirk (its Escape path in handleShortcut is unreachable
while the field is focused; the second press works); wiring it to
onFocusChanged is a follow-up.

Driving note: the click that OPENS the edit and a second click both land
in the same place -- and the second collapses the select-all (the field's
own caret placement, correct). One click, then type.

## Thumbnails — landed and verified 2026-08-21

Phase 1's per-file thumbnails, in every view mode: IShellItemImageFactory
with SIIGBF_THUMBNAILONLY (flwin32_icon_thumbnail), so a type without a
thumbnail handler fails fast and the row keeps its type icon -- and gated
by an extension set BEFORE asking, because a ten-thousand-source listing
should not pay ten thousand disk-touching misses to learn what the set
already says. The result is letterboxed onto a transparent square in C
(the factory preserves aspect; stretching is what a wrong thumbnail looks
like), so IconCache's square texture slots take it unchanged. Thumbnails
are per FILE where icons were per TYPE -- keyed by path and raster edge --
and ride the same serial rasterize queue BEHIND the type icons: every row
gets its instant shared answer, then upgrades in place as decodes land.
The shell's own thumbnail cache does the heavy lifting on revisits.

Verified on the box: a folder of jpgs shows per-file pictures in Details
(16px) and Large icons (96px, aspect kept), notes.txt keeps its type icon,
and a mixed Downloads folder still draws folder/exe/zip icons untouched.
Not done: no eviction (a 10k-photo folder at 96px is ~350MB of textures if
fully warmed -- fine at today's folder sizes, worth an LRU if it ever
shows), and no video-badge overlay on video thumbnails.

## Ctrl+Z — landed and verified 2026-08-21

Phase 1's undo item, done the only way it can be done: FOFX_ADDUNDORECORD
feeds Explorer's undo stack but that stack has NO REPLAY API -- it is
shell32 per-process state Explorer alone can pop -- so the app keeps an
inverse journal of its own. An IFileOperationProgressSink (C, static
vtable, flwin32_fileops.c) records what each operation ACTUALLY did, in
the names the shell settled on (" - Copy", "(2)"); undoing the name we
asked for instead of the name we got deletes the wrong file. FilesBloc
keeps a static 32-deep stack of these journals -- static because Explorer's
undo is per session, not per folder: delete here, Ctrl+Z from any tab.

The inverses: copy/new → recycle the produced files; move → each item back
to its OWN folder under its OWN name, one IFileOperation over the set
(flwin32_fileop_undo_moves); rename → the old name back; delete → the
bin's own "undelete" verb on the recorded $R... slots
(flwin32_fileop_bin_restore) -- addressed by ENUMERATION of the bin folder,
the same lesson resolve_item paid for, because no string parses to a bin
item, and through the verb because moving a slot back by hand orphans its
$I record.

All four verified on the box: delete→Ctrl+Z and copy-paste→Ctrl+Z driven
through the UI (file restored to its original path; the " - Copy" landed
in the bin); move and rename round-tripped through `--fileop-probe`, which
is the journal's oracle and stays in main.swift. Two honest gaps, both
deliberate: operations run through the context menu's SHELL VERBS are not
journaled (InvokeCommand reports nothing back), and there is no Ctrl+Y
redo yet -- the records to build it from are all there.

The driving lesson, again: synthetic Ctrl-key delivery to the window is
FLAKY (an injected keystroke silently vanishes when foreground shifts),
and the first "undo is broken" was exactly that. The stderr breadcrumb
proved the app never received the key; the probe then proved the machinery
without the UI. Judge input plumbing by logs and probes, not by one
keystroke's apparent effect.

## Shell-namespace enumeration — landed and verified 2026-08-21

Track 1 / Phase 0a of `winshell-shell-replacement.md` is DONE, deployed and
driven on the box. The Recycle Bin, Network and zip-as-folder all list, and
the bin's own verbs work: Restore was driven end to end (row leaves the
listing, file returns to its original path).

What it took, beyond the enumeration itself:

- **A parsing name does not address a Recycle Bin item back.** This is the
  finding that cost the most and the one to remember. A recycled item's
  `SIGDN_DESKTOPABSOLUTEPARSING` name is its raw slot --
  `C:\$Recycle.Bin\S-1-5-21-…\$RODZ69V.txt` -- so `SHParseDisplayName` on it
  resolves the FILESYSTEM file and hands back that file's context menu: Open,
  Edit in Notepad, Cut, "Restore previous versions" (the VSS verb, not the
  bin's Restore). Every one of those verbs would have operated on the slot,
  orphaning the `$I` record beside it. Nor is there a spelling that works --
  the Recycle Bin folder implements no `ParseDisplayName` at all, checked
  against the live folder with both the slot name and the display name. So
  `flwin32_shellmenu_open` grew a `location` parameter: given one it finds
  the item the way the listing found it (bind the location, enumerate, match
  on parsing name, `SHGetIDListFromObject`), and `SHBindToParent` then lands
  on the bin rather than on any filesystem folder the name happens to spell.
  The old note here predicted "the existing menu session should just work" —
  it did not, and the evidence is above.
- **Display name, not normal display name.** `SIGDN_NORMALDISPLAY` on a bin
  item is the original FULL PATH, which filled the Name column with paths.
  `SIGDN_PARENTRELATIVE` is what a Name column wants.
- **`ext` comes from the PARSING name.** The display name honours "hide
  extensions for known file types", so `a - Copy.txt` arrives as `a - Copy`
  with an empty extension -- cosmetic in the Name column and load-bearing as
  the icon cache key, where it collapsed every known type in the bin onto one
  key (a text file wearing the zip's icon).
- **The shell's Type text is carried through** (`Win32FileEntry.typeName`).
  The extension route asks the association database about a `$R…` slot and
  answers "TXTX File" for a text document.
- Everything file-shaped gates behind `canMutateHere` (command bar, New,
  keys including Ctrl+V, dropResolve, the menu's Rename cell) and the footer
  drops its Open / Open with / "opens with" -- all of them would have run on
  a slot. Delete and Properties are NOT gated: in a namespace listing they
  re-route through the shell's own verb (`runShellVerb`), which is the same
  machinery the context menu uses and the only thing that reaches the item.
- **A shell verb now refreshes the listing.** `Win32ShellMenu.invoke` gained
  a completion (InvokeCommand is modal, so it fires after the user has
  answered any dialog). Nothing watches a directory here, so without it
  Restore left its row on screen.
- The Recycle Bin is a deliberate dead end for activation: double-click opens
  nothing, as in Explorer. `isFileSystem` does not catch this -- recycled
  items report it TRUE, because the slot really is a file.

Not done, and deliberately: no Original Location / Date Deleted columns (the
bin's own, which this window has no column model for), no multi-item shell
verbs (a menu session addresses ONE item, which is why the context menu is
single-item everywhere), and Network devices show an empty Type because the
shell offers none for them -- better than the "File" the extension route
invented.

## Done, for context

The context menu matches native structurally and visually: modern tier with
"Show more options" (expands in place, instantly — native re-queries for
~250ms), six-cell labeled icon row with live enablement, acrylic material,
accelerator column backed by working keys. File operations run through the
shell's own IFileOperation (recycle bin, conflict dialogs, undo): cut, copy,
paste, rename (inline, Explorer's F2), delete, new-folder-into-rename-field,
Compress to ZIP (tar.exe), Share (windows.modernshare). The window itself
took Explorer's shape: tabs in the titlebar (custom caption, drawn caption
trio, drag/snap/double-click-maximize), full-width bar rows in Explorer's
order, shell display names and Windows' own date format, themed light/dark
from AppsUseLightTheme, and every glyph from Segoe Fluent Icons — the
system's own font, registered from C:\Windows\Fonts.

Engine (starling branch): swift-mode scenes commit to the raster pipeline at
Render time; first frame after idle fires immediately instead of snapping to
the tick grid; programmatic setState gets a real embedder frame on Win32
(hostScheduleEngineFrame).

## Phase 4 surfaces: banners + Run — landed and verified 2026-08-21

Toast banners (`--banners`, passive parked overlay, polls the store, pops
only where the native shell cannot) and the Win+R Run dialog (`--run`,
bottom-left parked overlay, ShellExecute with %VAR% expansion) are DONE and
VM-verified end to end — the full account, including the passive-overlay
mode, the left-edge anchor, and the dock's Files-tile texture-retain fix
this work surfaced, lives in `winshell-shell-replacement.md` under Phase 4.
The dock now holds four chords: Win+A, Win+N, Win+E, Win+R.

## The file-manager role is ours

Starling Files now answers the dock's File Explorer tile (wearing
explorer.exe's own yellow folder) and Win+E — the third chord the shell
keeps, after Win+A and Win+N. Deliberately NOT taken: explorer.exe itself
(the desktop, dialogs and tray stay its), and the global Directory
association — apps that ShellExecute a folder still get the handler they
assume. Revisit the association only when view modes and the address bar
reach parity.

## Retractions and traps, from the flyouts

- **The engine does NOT lose scroll packets — retraction.** An earlier
  version of this entry claimed Windows swift-mode dropped signalKind=scroll
  between the embedder and the SwiftRuntime callback. False, twice over, and
  worth recording because both halves will bite again:
  1. *Injected wheel routes by FOCUS, not position* — a test harness's
     hidden console holds focus, SetForegroundWindow from background is
     refused, so synthetic wheels vanish while hovers (position-routed)
     work. Post WM_MOUSEWHEEL at the frame from an in-session task instead
     (wclick.py --wheel has the account).
  2. *print() through a redirected pipe is FULLY BUFFERED on Windows* — the
     same trap the desktop's CLAUDE.md documents for Linux. Diagnostic
     prints that "never appeared" were sitting in a 4KB buffer; absence of
     a print is not absence of the event. Judge input plumbing by PIXELS
     (screenshot-diff before/after), never by prints.
  What survives as real: the frame forwards WM_MOUSEWHEEL down to the
  engine's child, for the paths where focus is on the frame itself.

## File explorer — visual polish (small)

- [x] Hover states — everywhere native has them: caption trio (close goes
      red), nav arrows, command bar, sidebar rows, listing rows. Took a
      three-part framework fix first: MouseRegion had never fired anywhere
      (tracker unfed, annotation cast against the wrong type, targets boxed
      in AnyHitTestTarget). See commits d296a91 + 454429d.
- [x] Dropdowns that drop: the context-menu machinery gained a flyout mode;
      New (Folder / Window) and Sort (keys + direction, checkmarked) open
      real menus under their buttons. View still disabled — it waits on
      view modes existing.
- [x] OneDrive sidebar row: %OneDrive% (falling back to
      %USERPROFILE%\OneDrive), only when the folder really exists, shell-named
      and cloud-glyphed under Home. Gallery/Network/Linux stay out until a
      backing view exists — a row that navigates nowhere is worse than absence.
- [x] Mica titlebar tint, the honest approximation: real mica is DWM
      compositing a blurred desktop behind transparent window regions,
      unreachable behind an opaque GL swap chain -- but what the eye reads
      off Explorer's chrome at rest is the TINT, so the chrome (windowBg /
      navPane) now blends 20% (light; 15% dark) of the wallpaper's average
      colour, computed off-thread from a shell thumbnail
      (flwin32_wallpaper_average) when the window opens. Listing and field
      surfaces stay pure, as native's do.
- [x] This PC in the sidebar expands and collapses: a chevron in the row's
      left gutter (icons stay aligned), the row itself toggles since it has
      nowhere to navigate, and the state lives on the window — tabs share a
      nav pane, as in Explorer.

## File explorer — functional gaps (medium)

- [x] Multi-select: Ctrl-click toggles, Shift-click spans from the anchor,
      Ctrl+A, "n items selected", background click deselects, right-click
      keeps a selection it lands inside. Delete recycles the set as ONE
      IFileOperation (one progress dialog, one undo); Ctrl+C/X put the set
      on the clipboard as one data object. Same-folder paste now lands
      " - Copy" files instead of the shell's conflict dialog, and a
      same-folder cut-paste is the no-op Explorer makes it. Rubber-band
      drag selection is the piece that remains.
- [x] Rubber-band selection: a background press dragged past 4px draws the
      accent rectangle (its own model + overlay, like the menu, so the drag
      rebuilds one box and not the window) and the rows it spans become the
      selection live; Ctrl-dragging adds to what was selected. No edge
      autoscroll yet -- the band selects what is on screen.
- [x] Real tabs: one FilesBloc per tab (history, selection, sort, filter
      and scroll each tab's own for free), an observable active index, and
      the `filesBloc` global becomes a computed view of the active tab --
      which keeps the context menu and every other consumer pointed at the
      tab the user is looking at without knowing tabs exist. "+" and
      Ctrl+T open a Home tab as Explorer does, Ctrl+W and the per-tab
      close glyph close one (the window when it is the last), tabs shrink
      to fit as they multiply, and middle-click closes the tab under it.
      Not yet: dragging tabs to reorder or tear off.
- [x] View modes: Details, Tiles, Medium icons, Large icons, per tab,
      behind a live View dropdown. One ListingGrid struct describes cell
      geometry for every mode (Details is its columns == 1 case), consumed
      by the lazy ListView (grid modes scroll by strip: one item = one run
      of cells) AND every arithmetic hit test -- menu targeting, the
      rubber band (now a true 2D intersect), drop targeting, arrows
      (up/down move a strip, left/right a neighbour where one exists),
      type-to-jump's scroll-into-view. Icons re-warm per mode edge
      (48/96) under size-suffixed cache keys. Verified live: band, menu,
      2D arrows, double-click open, selection surviving mode switches.
      List and Content stay out -- List is a column-major sideways
      scroller, a different scroller rather than a different cell.
- [x] Drag & drop, in and out. In: the window is an OLE drop target
      (flwin32_dragdrop.c); files from any source land in the open folder
      or the folder row under the pointer (drawn lit), with Explorer's
      effect rules -- Ctrl copies, Shift moves, default moves within a
      volume and copies across, a drop back into the files' own folder
      refused. Out: a row press dragged past 4px starts DoDragDrop with
      the selection (the shell's own data object, so Explorer's optimized
      move works), which also gives window-internal drags. Verified against
      a real OLE source, our own window, and native Explorer as target.
      The sidebar's rows are drop targets too now -- each row's folder,
      lit while a drag hovers it, resolved by an arithmetic mirror of the
      sidebar's layout. Not yet: custom drag imagery (the default OLE
      cursors stand in), edge autoscroll during a drag.
- [x] Type-to-jump (printable keys accumulate for a second, first prefix
      match selected and scrolled into view); arrows walk the list with
      Shift extending the range from the anchor, Home/End leap, and the
      viewport follows; Backspace and Alt+Left/Right/Up drive history.
- [x] Column resize: the header gaps are draggable dividers (root
      Listener arithmetic, like everything else) -- a boundary follows the
      pointer, the column right of it gives or takes the width, clamped
      50..400, rows and headers reading the same window-state numbers.
      Reorder remains unbuilt.
- [x] New dropdown carries the ShellNew templates: a registry walk
      (flwin32_shellnew_templates, cached per process) finds every
      extension whose ShellNew describes a file we can honestly create --
      NullFile, a template copy, or literal Data bytes; Command and Handler
      entries (wizards, .lnk) are skipped rather than faked. Each row
      creates "New <Type><ext>" uniqued and drops into inline rename,
      the newFolder gesture. On this machine that is one row (Compressed
      (zipped) Folder) -- the list is the machine's, not a hardcode.
- [x] A This PC computer view: a sentinel non-path directory
      (kThisPCPath, U+0001-prefixed so no folder can collide) draws
      Devices and drives -- each tile the shell's name, Explorer's
      capacity bar (red under 10% free), "x GB free of y GB", double-click
      opens the drive. The sidebar row and the breadcrumb's This PC crumb
      both navigate there now; the sidebar chevron became its own tap
      target so collapsing does not navigate. Everything file-shaped gates
      itself off the sentinel: New disabled, no background menu, no drops,
      no headers -- and drive tiles keep their highlight OUT of the
      bloc's selection, so no file operation can ever see C:\ selected.

A performance profile of all of the above is in `winshell-perf.md`
(2026-08-21): idle is clean everywhere, the heaviest interaction is the
column drag at ~4ms CPU per move (the pre-existing full-window rebuild
cost, no regression), and the follow-ups it names are grid-hover raster
cost, isolating the listing's rebuild scope, and present-side frame
statistics -- the last of which is the same plumbing the idle-present
question below needs.

The road past this list -- replacing explorer.exe itself -- is planned in
`winshell-shell-replacement.md` (2026-08-21): shell-namespace enumeration
and the popup-surface spike as the two prerequisites that pay four times
each, then the desktop surface, tray ownership, toast banners, and the
Winlogon Shell= slot, every phase VM-proven before the dev box tries it.

## Deferred by decision (session-sized)

- [x] The context menu as its own popup window — DONE, see "Popup surfaces
      (0b)" at the top of this file. (Of the three things the deferral
      predicted it would buy, two arrived — overhang and height; true
      cross-window acrylic did not: the popup fill is opaque, because
      per-pixel alpha over a GL swapchain needs DirectComposition.)
- [ ] Engine frame-dispatch latency: ~40ms request-to-begin-frame across
      five queue hops (documented in engine commit e077473108b). Worth
      ~25-30ms off every first paint, but it is upstream-forked scheduler
      surgery with animation-jank risk — needs its own pass with
      smoothness validation. Present-side confirmation (engine 319173a327f,
      STARLING_PRESENT_LOG): hover-driven repaints present every 2-5
      vsyncs, p50 46ms request-to-glass — the dispatch latency wearing its
      runtime face. The smoothness validation the fix needs can now be
      read off gap_us histograms.
- [x] Idle present-vs-capture ambiguity: SETTLED (engine 319173a327f).
      STARLING_PRESENT_LOG=1 logs every present with a QPC timestamp in
      the same counter external tooling reads; five idle-then-click probes
      showed the click's frame presenting within milliseconds of the
      input after 8s of true idle. The ~600ms was GDI screen-capture
      staleness. Screenshots of the GL view lag reality; the log is the
      truth now.

## Hygiene

- [x] Theme changes restyle live: the host turns WM_SETTINGCHANGE
      ("ImmersiveColorSet") into a callback (flwin32_host_on_theme_change /
      onThemeChange); Files re-reads AppsUseLightTheme, flips Win11.light,
      rebuilds from the root and pokes each tab's bloc for the lazy rows;
      the launcher restyles its glass through a themeChanged event. The dock
      already polled. Verified both directions with a live registry flip +
      broadcast.
- [x] Dock, launcher AND Settings draw Segoe Fluent Icons now -- every
      Cupertino glyph in WinShellBar swapped for the system's own codepoint,
      each verified against the font's cmap and rendered to be looked at
      first (SignOut F3B1 and WifiError EB5E are absent from the Fluent doc
      page but present in the font). CupertinoIcons stays registered for
      whatever the framework's own controls draw.
- [x] Push: winshell and the engine's `starling` are both on origin
      (2026-08-20; the engine took a merge of upstream's rdp work first).
      The flutter githooks cannot run on this box -- they are vpython3
      wrappers and depot_tools is not installed -- so engine pushes need
      --no-verify until that changes.
- [x] A surface no longer opens with a CONSOLE behind it. Clicking Files in
      the dock put a full-screen Windows Terminal window under the Files
      window -- engine log text around its edges, and a second tile in our
      own dock for a window nobody opened. `open_surface` reached for
      `ShellExecuteW(..., SW_SHOWNORMAL)`, and this is a console-subsystem
      binary, so Windows popped a console for the child. The parked surfaces
      (notifications, banners, Run, launcher) never showed it only because
      they pass SW_HIDE.
      **SW_HIDE is the trap, not the fix.** It suppresses the console by
      setting `STARTUPINFO.wShowWindow`, and Windows applies that to the
      process's FIRST `ShowWindow` whatever nCmdShow the call passes -- so
      the surface's own window never appears either. Measured on the box:
      the `--files` process came up with the console gone and zero visible
      windows. The fix is `CreateProcessW` with `CREATE_NO_WINDOW`, which is
      what the supervisor already does for the dock and the desktop
      (`flwin32_sessionslot_spawn_self`). Same treatment for Files' own
      File > New window, which used Foundation's `Process` and popped one
      too, and for Compress-to-ZIP's `tar.exe` (`flwin32_run_hidden`).
      Verified from the dock tile: Files opens, no console class on screen
      at all; New window spawns `--files "<dir>"` quoted and console-less;
      the zip is a valid archive with the entries still relative.

CHECKPOINT 2026-08-23 — mainline, and measured against Windows. `winshell`
is merged into `main` (`2c7e5ab`); the engine half is on `starling`, not a
paired branch. The box runs mainline as the real `Shell=`.

Landed since: the file explorer opens with no console behind it (`4002f83` —
`open_surface` used ShellExecuteW/SW_SHOWNORMAL on a console-subsystem
binary; SW_HIDE is the trap, CREATE_NO_WINDOW the fix); the listing stopped
waiting on Quick Access (`178c4e9`); the caption is claimed before the window
exists (`7cca01e`); and the desktop stays under app windows (`a667a8b` — a
P0: open, close, open and the second window was invisible, 21 of 24).

Latency vs the native shell, warm medians: Start menu **67 ms vs 300 ms**,
file manager **500 ms vs 1149 ms**, and **449 ms vs File Pilot's 515 ms**
like-for-like. The remaining budget is not ours: ~110 ms is ANGLE bringing up
a D3D device (per process, no cheaper configuration exists) and ~100 ms is
DWM's window-open animation. Numbers and method in winshell-perf.md's
addendum; the rig and the film pipeline in `test/bench/win-latency/`.

- [ ] **Park or share the engine for Files.** The only way past the ~110 ms
      ANGLE cost is to stop creating a process per surface: either park a
      Files process the way the launcher, banners, Run and the notification
      centre already are (`flwin32_shell_ensure_*`, ~100-150 MB resident), or
      make Files a second VIEW in the oneview process, which pays nothing and
      is cheaper in RAM. The second is the real fix and the bigger change.
- [ ] **Audit the other surfaces for the resize handshake.** `setPanel`,
      `setDesktop` and `setOverlay` all run AFTER `host_create` in
      `Win32WindowedHost.boot`, which is the same shape that cost Files 90 ms
      — the dock, the desktop and the launcher may each be paying it at logon.
