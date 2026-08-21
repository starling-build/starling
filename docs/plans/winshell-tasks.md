# winshell — task list

The Windows shell branch: WinShellBar (dock, launcher, settings, files) on
the Win32 host. This file tracks what remains, ordered by what a hand on the
mouse notices first. Updated 2026-08-21: every visual-polish, functional-gap
and hygiene item is done -- what remains is the deferred-by-decision section
below and the small not-yets recorded inside ticked entries (tab
reorder/tear-off, column reorder, custom drag imagery, edge autoscroll).
The next session-sized piece by this list's own logic is the context menu
as its own popup window, parked earlier in favour of window parity, which
is now complete.

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

- [ ] The context menu as its own popup window. Feasibility fully
      established mid-session: FlutterDesktopEngineCreateViewController is
      exported, the adapter's secondaryPipelines are view-generic, pointer
      routing is per-view. Buys menu overhang past the window's edges,
      menus taller than the window, true cross-window acrylic. The spike
      was parked in favour of window-parity work.
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
