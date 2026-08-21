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
- [ ] OneDrive sidebar row when %USERPROFILE%\OneDrive exists (honest: it is
      a real folder). Gallery/Network/Linux stay out until a backing view
      exists — a row that navigates nowhere is worse than absence.
- [ ] Mica titlebar tint: native's caption area picks up a desktop-tinted
      mica; ours is flat windowBg.
- [ ] This PC in the sidebar is not expandable (drives are simply always
      shown — same picture for one drive, wrong for many).

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
- [ ] Real tabs: one tab per window now; "+" opens a new window. Real tabs
      need per-window multi-directory state and a tab strip model.
- [ ] View modes: Details only; the View button is honest about it (drawn
      disabled) but icon/tile/list views are the ask.
- [ ] Drag & drop, in and out (ties into the shell's IDataObject work
      already done for the clipboard).
- [ ] Column resize/reorder; type-to-jump in the listing; Backspace and
      Alt+arrow navigation keys.
- [ ] New dropdown with the ShellNew templates (New currently creates a
      folder only).
- [ ] A This PC / computer view, which would also make the breadcrumb's
      "This PC" crumb navigate instead of being a label.

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

- [ ] Theme changes need a relaunch: AppsUseLightTheme is read once at
      boot; listen for WM_SETTINGCHANGE and restyle live.
- [ ] Dock and launcher still draw Cupertino glyphs; the FluentIcons
      conversion covered Files and its menu. Same mechanical swap.
- [ ] Push: the winshell commits here and the three engine commits on
      `starling` are local only.
