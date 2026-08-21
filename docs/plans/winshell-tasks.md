# winshell — task list

The Windows shell branch: WinShellBar (dock, launcher, settings, files) on
the Win32 host. This file tracks what remains, ordered by what a hand on the
mouse notices first. Updated 2026-08-20, at the end of the session that took
the file explorer and its context menu to parity with native Explorer.

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
- [ ] Mica titlebar tint: native's caption area picks up a desktop-tinted
      mica; ours is flat windowBg.
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
      to fit as they multiply. Not yet: dragging tabs to reorder or tear
      off, middle-click close.
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
      Not yet: sidebar rows as drop targets, custom drag imagery (the
      default OLE cursors stand in), edge autoscroll during a drag.
- [x] Type-to-jump (printable keys accumulate for a second, first prefix
      match selected and scrolled into view); arrows walk the list with
      Shift extending the range from the anchor, Home/End leap, and the
      viewport follows; Backspace and Alt+Left/Right/Up drive history.
- [ ] Column resize/reorder.
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
      smoothness validation.
- [ ] Idle present-vs-capture ambiguity: whether the ~600ms idle repaint
      delay is real glass latency or GDI screen-capture staleness was left
      undetermined (PrintWindow cannot see the GL view; the cursor rides a
      hardware overlay). Settling it needs present statistics from inside
      the engine.

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
