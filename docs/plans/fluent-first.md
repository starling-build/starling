# Fluent first: the Linux desktop adopts the latest Fluent style

Draft for approval, 2026-09-05.

**Status, 2026-09-05 (later the same day):** the user redirected the order —
**build the Fluent style in the SDK first, independent of the desktop**, and
grow it into a demo app like Microsoft's WinUI 3 Gallery. That is now the
first phase, and its first cut is in: the tokens (`FluentTokens.swift`),
the materials as recipes with real Acrylic, Mica and Smoke widgets
(`FluentMaterials.swift`, `Surfaces/Acrylic.swift`, `Surfaces/Mica.swift`),
Windows' accent shades as the default accent, the corrected type ramp, the
flyout/dialog/tooltip surfaces on the elevation and corner tokens, a
framework `Icon` widget, a scrolling navigation pane, and
`sdk/Examples/FluentGallery` — a NavigationView app with eight design pages
and 44 control pages. 19 unit tests pin the values. Building the gallery
found and fixed four framework bugs that would have hit the desktop's Fluent
surfaces too: the leader/follower layers behind every flyout were stubs and
their children were culled out of their pictures (every drop-down, combo
box and picker was blank), chevrons and check marks were text glyphs the
UI font does not carry (now painted by `FluentGlyph`), the navigation
pane neither scrolled nor top-aligned short pages, and icon buttons had no
ink in the dark theme. Phase 0 below is
therefore mostly done on the SDK side; what remains of it is the desktop's
half (defaults, maximized corners, inactive fallback) and the `CLAUDE.md`
rewrite.

**Status, 2026-09-06:** the gallery driven with a real pointer (a freshly
started dev shell delivers `shell-drive` clicks; a long-running one does
not). That found three more framework bugs no screenshot sweep could:
`Navigator(home:)` never followed a changed `home`, so every app-level
`setState` — page selection, dark mode, the wallpaper sample — was
invisible; menu items "closed" themselves by popping a navigator that had
nothing to pop; and submenus carried a barrier over their parent menu.
Fixed (58d6e8b): flyouts carry a `FlyoutScope` (`closeAll()` closes a
menu chain), submenus open on hover after Windows' 400 ms `MenuShowDelay`
and close when another item is hovered, WinUI's edge-aligned placements
exist and drop-downs use `BottomEdgeAlignedLeft`. All verified on screen.
Every surface the desktop's Fluent chrome will need from the SDK — menus,
flyouts, dialogs, teaching tips, acrylic, Mica, the entrance motion — now
works under real input; the desktop phases below can start.

**Phase 0, 2026-09-06:** landed on the desktop side. Fluent is the default
for a machine that has never chosen — through a named `ShellStyles.
defaultStyle` rather than by reordering `ShellStyles.all`, because that
order is the wire format apps receive a style as (`StarlingStyleId`'s raw
values match it) and reordering it would have repainted every app in the
wrong palette. `ShellMetrics.fluent` reads its corners from `FluentCorners`;
maximized windows square their corners in Fluent only
(`ShellMetrics.squareWhenMaximized`); an unfocused window drops to the
untinted solid (`ShellTheme.windowSurfaceInactive`, the Mica inactive
fallback) in both its body and its caption; apps assume Fluent when no
style has been pushed; the styles paragraph in `CLAUDE.md` is rewritten per
§3 and the 2025 prerequisites audit carries a status header.

**Scope: the Linux desktop, and only it** — the shell in `shell/`, its
chrome, and the first-party apps in `apps/`. The Windows shell
(`sdk/Examples/WinShellBar`, the Explorer replacement that runs *on*
Windows) is **not changed by this plan**; it appears below only as a
measured reference, and nothing in any phase edits it.

The Linux desktop has had two switchable styles since 2026-08-28: macOS (the
default, and the one every surface was designed for first) and a Fluent
style — the one the style menu calls "Windows" — that replaces the menu bar
and dock with a taskbar and Start (`ShellStyle.swift`'s header has the
history). The user's direction now is to **double down on Fluent**: bring the
Linux desktop's Fluent style, chrome and apps alike, up to what Microsoft
ships and documents *today*, and make it the look the desktop leads with.
This plan says what "today" means, audits how far we are from it, and lays
the work out in phases that each ship on their own.

The macOS style does not go away. The style seam (`ShellTheme` +
`ShellMetrics` + `ShellChrome`, one registry, no `if style ==` anywhere) is
the right shape and stays. What flips is the *direction of fallthrough*:
today every unported Fluent surface falls through to a macOS builder; after
this, new chrome is designed Fluent-first and macOS is the style that has to
keep up.

## 1. What "the latest Fluent" is, in September 2026

Checked against Microsoft's current guidance rather than memory. Two layers
matter, and they are different documents:

**Fluent 2** (fluent2.microsoft.design) is the cross-platform design system:
a token system (global tokens → alias tokens with semantic names), a cohesive
neutral/brand/shared colour model, standardised corners, elevation as a
shadow ramp, motion as durations + curves, and accessibility notation on every
component. Its Windows expression *is* WinUI 3 — the site's Windows section
points at the WinUI resource dictionary and gallery, nothing else. The SDK's
`FluentUI/Styles/ColorResources.swift` is a port of exactly that dictionary
(88 tokens, light and dark), which is why the shell's Fluent palette is a
mapping onto it and not a hand-picked set. That decision was right and holds.

**Windows 11 signature experiences** (learn.microsoft.com, Windows App SDK
design docs, several pages revised 2026-02 through 2026-08) is how Fluent 2
lands on the Windows desktop specifically. The values that bind us:

| Area | The rule | Source |
|---|---|---|
| Geometry | **8px** radius on top-level containers (windows, flyouts, dialogs, menus). **4px** on in-page elements (buttons, list backplates, tooltips, progress/scroll bars). **0** where straight edges meet, and **0 on a window that is snapped or maximized.** | signature-experiences/geometry |
| Materials | **Mica**: opaque, tinted by the wallpaper's colour, for long-lived windows; samples the wallpaper *once*; falls back to `SolidBackgroundFillColorBase` when the window is **inactive**, transparency is off, or battery saver is on. **Mica Alt**: stronger tint, for tabbed title bars. **Acrylic**: blur + tint + luminosity + 2% noise, **transient light-dismiss surfaces only** (menus, flyouts, Start), brighter in Win11 than Win10, never on large window backgrounds, and never two acrylic panes edge to edge. **Smoke**: translucent black dim under a modal dialog, same in both themes. | style/mica, style/acrylic, signature-experiences/materials |
| Layering | Two layers: **base** (Mica; commands, navigation, menus) and **content** (`LayerFillColorDefault`, a low-alpha wash, contiguous or as cards). | signature-experiences/layering |
| Elevation | Shadow + 1px stroke per level: window **128**, dialog **128**, flyout **32**, tooltip **16**, card **8**, control **2** (rest and hover), **1** pressed and for a plain layer. | signature-experiences/layering |
| Type | **Segoe UI Variable** (weight 300–700, optical-size axis). Ramp: Caption 12/16 Regular, Body 14/20, Body Strong 14/20 Semibold, Body Large 18/24, Subtitle 20/28 SB, Title 28/36 SB, Title Large 40/52 SB, Display 68/92 SB. Regular for most text, Semibold for titles; **no Bold, no Italic**; minimum 12 Regular / 14 Semibold; sentence case; ellipsis. **Selawik** is Microsoft's own recommended metric-compatible open stand-in — what we bundle. | signature-experiences/typography, xaml-theme-resources |
| Colour | One neutral set per mode, accent shades generated for contrast, accent used sparingly, `TextOnAccentFillColorPrimary` for ink on accent (black in dark mode). Windows controls get *lighter* as you interact with them. | signature-experiences/color, fluent2 color |
| Motion | Direct entrance `cubic-bezier(0,0,0,1)` 167/250/333 ms; point-to-point `(0.55,0.55,0,1)` 167/250/333; direct exit `(0,0,0,1)` 167 **always with a fade**; gentle exit `(1,0,1,1)` 167; bare fade linear 83; strong entrance three keyframes (0.85,0,0,1)/167 → (0.85,0,0.75,1)/167 → (0.85,0,0,1)/333. Principles: taskbar flyouts **slide up** on open and down on dismiss; minimize bounces the taskbar icon; windows stay "the same window" through snap and maximize. | signature-experiences/motion |
| Spacing | 8 between buttons, button and its flyout, control and header; 12 control to label, between content areas; 16 from a surface's edge to its text; 40×40 minimum target. | basics/content-basics |
| Title bar | **32px**; Mica or the window's own surface; **all elements semi-transparent when inactive**; 16px app icon 16 from the left, title 16 from the icon in **Caption** style; full-bleed caption buttons with ChromeMinimize/Maximize/Restore/Close; **48px** when it carries search or an account picture; double-click toggles maximize; right-click opens the system menu. | basics/titlebar-design |
| Icons | Segoe Fluent Icons: monoline, 16/20/24. Fluent System Icons (what we ship) is the open twin. | iconography |

**What Windows itself changed in 2025–26** (Insider blogs and coverage,
2025-06 through 2026-08). This is the part memory gets wrong, because the
2021 shapes are the ones everyone remembers:

- **Start was redesigned** (Dev channel 2025-06, general 2025-11 with
  KB5067036, "rolled out to all" 24H2/25H2 by 2026-07; the WinUI-native
  rebuild ships with **26H2 in October 2026**). It is one **scrollable
  page**: search box → **Pinned** (rows, "Show all") → **Recommended**
  (renamed *Recent*; **can be hidden**) → **All apps inline**, in
  **Category** view by default (groups like Productivity, Entertainment;
  most-used apps bubble up), or **Grid** (alphabetical) or **List**; the menu
  remembers the view. The panel **sizes to the screen** and 26H2 adds
  **Small/Large** presets and toggles to hide Pinned, Recent, and the account
  row. A **Phone Link** side panel glides in from the edge. Microsoft's own
  words: quicker, more personal, calmer, clear hierarchy.
- **Taskbar**: 26H2 restores **placement on any edge** (top, bottom, left,
  right; shipping September–October 2026); a **smaller taskbar buttons**
  option exists; alignment left/centre is a setting.
- **Dark mode reach**: legacy dialogs (Run, Folder Options, file-operation
  progress and conflict dialogs, account dialogs) went dark-mode aware
  through late 2025 and 2026.
- **Quick Settings**: consolidating power/battery toggles into a sub-page,
  a **Dark mode** tile, removable and re-orderable tiles.
- **WinUI 3 replacing shell surfaces** one by one (AutoPlay, the Properties
  sheet, Control Panel pages), centred on screen, 8px corners, more spacing,
  both themes. Microsoft said in 2026-04 it is "finally focusing on Windows
  11's design", starting with Settings.

The bar we are aiming at is therefore **Windows 11 as it looks in late 2026**,
not the 2021 launch. Where the two disagree (Start, above all) this plan
picks 2026.

## 2. Where the desktop is today

Audit of the Fluent style as it sits on the branch, against the table above.
✔ done and right; ◐ present but not to spec; ✗ still the macOS surface or
absent.

| Surface | State | Gap |
|---|---|---|
| Palette | ✔ | Mapped onto WinUI's dictionary. Mica tint from the wallpaper's average colour. Missing: `LayerFillColorDefault` content layer, Mica Alt, Smoke, and the **inactive-window fallback to solid** — a Fluent window looks the same focused and not, apart from a stroke colour. |
| Type | ◐ | Ramp is used in the taskbar and Start; the title bar and every status popup still set 10/12/13px by hand. SDK `caption` is weight **300** (a port slip — WinUI's Caption is Regular; Selawik ships no Light so it renders Regular by accident). |
| Corners | ◐ | 8/4 in the right places. **Maximized windows stay rounded** (`DesktopWindow` only squares them for fullscreen). |
| Window material | ✗ | Every window sits on the macOS **liquid-glass** backdrop: an 18px blur with saturation *boosted* — the exact opposite of Mica (opaque, one sample) and of acrylic (saturation pulled). The Fluent theme sets `material: .acrylic` but the window path does not read it. |
| Window shadow | ✗ | No shadow at elevation 128; windows are a 1px stroke on the wallpaper. |
| Title bar | ◐ | 32px, caption trio 46×32, red close, left title — right. Missing: 16px app icon, Caption ramp for the title, inactive semi-transparency of *all* elements, right-click system menu, **snap layouts flyout** on hovering maximize. |
| Window motion | ✗ | Open/minimize/close are macOS's scale effect (380 ms easeInOutCubic zoom from the dock; close shrinks to 72% in place). No fade anywhere — the framework's `RenderAnimatedOpacity` gates at alpha 0 and does not blend partial alpha, which is the reason recorded in `OpenAnimations.swift`. Windows: 167–250 ms, `(0,0,0,1)`, fade + scale, minimize flies to the taskbar icon and the icon bounces. |
| Taskbar | ◐ | Full-width, reserves its strip, centred tiles, two-line clock, one tray button, bell, live hover previews — good. **56pt tall with 34pt icons**, numbers borrowed from our Windows shell; real Windows 11 is **48 with 24**. Missing: search button/box, Task View button, tray overflow chevron, show-desktop corner, pin/unpin, **jump-list** menu (the tile menu is `MacosMenu`), tooltips, slide-up motion for its flyouts. |
| Start | ◐ | A panel above the bar, Windows' 832×864 proportions, pinned grid, search caret, user + power footer. It is the **2021** Start. No Recommended/Recent, no inline All apps, no Category/Grid/List, no Small/Large, no hide-section toggles, search is a caret not a field. |
| Quick Settings | ✗ | The macOS **control centre** (Cupertino icons, macOS tile shapes) hung from the bottom-right. Windows: tile grid with accent-filled active tiles, brightness and volume sliders, battery %, gear and pencil, Wi-Fi/Bluetooth as chevron sub-pages. |
| Notifications + calendar | ✗ | The macOS bell popup. Windows joins **notification centre and month calendar** into one panel from the clock; toasts appear bottom-right above the taskbar; "Do not disturb". We show **no toasts at all** in either style. |
| Wi-Fi, battery, power panels | ✗ | macOS shapes. In Windows these live *inside* Quick Settings (Wi-Fi sub-page, battery row) and Start's footer (power, which we already route there; its confirm should be a `ContentDialog` over Smoke). |
| Desktop context menu | ✗ | `MacosMenu`. Windows: acrylic `MenuFlyout`, 8px, 16px icons, a top row of icon commands. |
| Overview | ✗ | Mission Control (spaces strip on **top**, macOS exposé). Windows: **Task View** with the desktops strip at the **bottom** above the taskbar, windows grid above it; and **Alt+Tab** with thumbnails over a dimmed acrylic. |
| Key chords | ◐ | Ctrl+Up opens the overview, Ctrl+arrows and Ctrl+Tab move between spaces. **Nothing opens Start from the keyboard**; the Windows key is not handled at all. Windows expects **Win** → Start, Win+Tab → Task View, Win+D, Win+E, Win+I, Win+A (Quick Settings), Win+N (notifications), Win+arrows → snap. |
| Apps | ✗ | Every app is `MacosApp` with `Macos*` controls and `CupertinoIcons`, recoloured through `StarlingPalette.fluent`. `FluentApp`'s scaffold **traps on mount as a DMA-BUF child** (`apps/FileExplorerApp/.../main.swift:14`), which is the whole reason. `SettingsApp` already keeps a per-style layout table, so the seam exists. |
| Fonts | ✔ | Selawik Regular + Semibold bundled — exactly the two weights the ramp needs. |
| Cursor | ◐ | One cursor set for both styles; a Windows arrow is a small but constant tell. |
| Tests | ◐ | `test/functional.py` proves a style switch is a *shape* change (bar moves) and that the style persists. Nothing checks the Fluent surfaces themselves. |

The SDK side is further along than the 2025 prerequisites audit
(`fluent_ui_prereqs_audit.md`) says: `Overlay`, `GestureDetector`,
`ImplicitlyAnimatedWidget`/`AnimatedContainer`, `BackdropFilter` and
`AnimationController` all exist now, and `FluentUI/Controls` holds 48 ported
controls including `MenuFlyout`, `Flyout`, `ContentDialog`, `Tooltip`,
`NavigationView`, `TabView`, `CommandBar`, `Expander`, `InfoBar`,
`ToggleSwitch`, `Slider`. `Focus`/`FocusNode` are still stubs. `Acrylic` is a
tint-only approximation (no blur), so the real material has to be composed
from `BackdropFilter` the way the shell already does for glass.

Our own **Windows shell** (`sdk/Examples/WinShellBar`, running on real
Windows as Explorer's replacement) has already built several of these against
the native panels: a Start with pinned grid, All apps and Recommended
(1501df1), a Quick Settings band, an Action Center with a real month calendar
(332 wide, measured), a Windows-shaped Files, and a WinUI palette sampled off
the native flyouts. All of it is `#if os(Windows)` and process-per-surface, so
it is a **design reference and a source of geometry**, not code the Linux
shell can import as-is — and it stays exactly as it is.

## 3. The direction, stated as rules

These replace the "Standing directions" paragraph on styles in `CLAUDE.md`
when Phase 0 lands:

1. **Fluent is the default style** for a machine that has never chosen
   (`ShellStyles.all` order; persisted ids are untouched, so nobody who
   picked macOS is moved). Apps that have not yet been told a style assume
   Fluent (`StarlingStyleId.current`).
2. **New chrome is designed Fluent-first.** A surface lands in
   `shell/…/Fluent/` first; the macOS builder either follows in the same
   change or `MacosChrome` carries an honest note naming what it still falls
   through to. Today's `FluentChrome` notes invert.
3. **Match Windows 11 as shipped in 2026**, measured where we can (the
   Windows box, `test/win/capture-reference.sh`) and documented where we
   cannot. When memory and the 2026 docs disagree, the docs win.
4. **Tokens, not numbers.** Every Fluent duration, curve, radius, shadow and
   spacing value comes from one token file in the SDK's `FluentUI/Styles/`
   (Phase 0 adds the motion, elevation and spacing tokens WinUI has and the
   port lacks). A literal `250` or `Color(0x…)` in Fluent chrome is a bug,
   the same way it already is for colours.
5. **Apps go Fluent too** — see Phase 6 and the open question at the end.
   Until that phase lands the existing "apps are macOS-only, a Fluent widget
   in `apps/` is a bug" rule *stays in force*, because the trap that created
   it is still there.

## Phase 0 — foundations (small; unblocks everything after)

- **Tokens.** Add `FluentMotion` (the duration and curve table from §1 as
  named `Duration`/`Curve` values), `FluentElevation` (a `BoxShadow` list
  per level 1/2/8/16/32/128, light and dark), `FluentSpacing` (4/8/12/16/40)
  and `FluentCorners` (`control = 4`, `overlay = 8`, `window = 8`) to
  `sdk/Sources/Flutter/FluentUI/Styles/`. Fix `Typography.caption` to Regular.
  `ShellMetrics.fluent` reads corners from these.
- **Default flip.** `ShellStyles.all = [fluent, macos]`;
  `StarlingStyleId.current` defaults to `.fluent`. Update the functional
  check that assumes macOS first.
- **Corners on maximized windows go to 0** (`DesktopWindow`: `isMaximized`
  joins `isFullscreen` in the radius decision, in the Fluent style only —
  macOS keeps its rounding, so this is a `ShellMetrics` flag, e.g.
  `squareWhenMaximized`).
- **Inactive fallback.** `ShellTheme.fluent` gains the unfocused-window
  surface (`SolidBackgroundFillColorBase`, untinted) and `DesktopWindow`
  paints it for unfocused windows.
- **Docs.** Rewrite the styles paragraph in `CLAUDE.md` per §3; move the
  prerequisites audit's stale rows to "done".

Verify: `test/run.sh`; a fresh config dir boots into Fluent; maximize a window
and read the corner pixel; unfocus a window and read its title-bar colour.

## Phase 1 — windows: material, shadow, title bar, motion

- **Mica instead of glass.** A `ShellMaterial`-driven window backdrop: for
  `.acrylic`-style themes, no live blur under the window at all — an opaque
  fill of `windowGlassTint` (the wallpaper-leaned Mica base), which is what
  Mica *is*: one sample, no per-frame blur. This is also a measurable
  performance win (one `BackdropFilter` per window gone). Mica Alt is a
  second tint constant for later tabbed title bars; not built now.
- **Elevation-128 shadow** behind every non-maximized window, from
  `FluentElevation`; none when maximized (the edges touch the work area).
- **Title bar to spec.** Caption ramp for the title; 16px app icon 16 from
  the left (the same visual the taskbar tile uses); title 16 from the icon;
  every element at reduced alpha when inactive; right-click on the bar opens
  a `MenuFlyout` system menu (Restore/Move/Size/Minimize/Maximize/Close).
- **Snap layouts.** Hovering maximize for ~500 ms opens the six-layout flyout
  (2 halves, 3 columns, 2/3+1/3, quarters); clicking a cell snaps the window
  there. `WindowManager` already has a tiling mode; snap is a one-shot rect
  assignment on top of it. Win+Left/Right/Up/Down drive the same code.
- **Motion.** Open: scale 0.94→1 + fade, 250 ms, `(0,0,0,1)`. Close: scale
  to 0.94 + fade, 167 ms. Minimize: shrink toward the taskbar tile + fade,
  250 ms, then the tile's indicator bounces (the "delightful" principle).
  This needs the SDK's `RenderAnimatedOpacity` to **blend partial alpha** for
  a texture child — the limitation `OpenAnimations.swift` documents. That
  fix is the first task of this phase and is framework work in `sdk/`
  (`Rendering/ProxyBox.swift`), with a test in `sdk/Tests`.
- Flyouts everywhere in the Fluent chrome (Start, Quick Settings,
  notifications, menus) get the **slide-up-and-fade** entrance (167 ms,
  `(0,0,0,1)`) and slide-down exit, via one `FluentFlyoutTransition` widget
  so they cannot drift.

Verify: screenshot a focused and an unfocused window against the Windows
box's capture of the same layout; `perf`/frame-time before and after the
blur removal; snap via Win+Left and read the rect over the broker.

## Phase 2 — taskbar completion

- **Height.** The bar is 56pt with 34pt icons only because those numbers
  were copied from our Windows shell. Real Windows 11 is **48pt with 24pt
  icons**, and matching Windows is the point, so the Linux bar moves to
  48/24 (and `FluentBar`'s comment, which today argues for keeping the two
  shells identical, is rewritten to say this is a deliberate divergence).
  The Windows shell keeps its own numbers.
- Search button (opens Start with the search box focused — Windows has no
  separate search UI we need), **Task View** button (Phase 5's overview),
  tray **overflow chevron** (hidden icons flyout), **show desktop** strip at
  the far right (hover peeks, click toggles), pin/unpin.
- **Jump list** on right-click: pinned/recent files (from the app's recent
  documents when it reports them; otherwise the app name, "Unpin from
  taskbar", "Close window"/"Close all windows"), as a `MenuFlyout` on
  acrylic, replacing `dockIconMenuWidget` in this style. The VM console's
  extra items (Show Windows Desktop, Send Ctrl+Alt+Del) stay, as jump-list
  tasks.
- Tooltips (4px, elevation 16) on the tray buttons and Start; the live
  preview stays as it is (208×117 thumbnails, already sized to Windows).
- Taskbar settings, in the Settings app's Personalization page: alignment
  centre/left, auto-hide, show on all displays. Edge placement (26H2) is
  deliberately **out** — it changes `ShellMetrics` from insets to an edge
  enum and touches every output's layout; a plan of its own if wanted.
- Flyouts slide up from the bar (Phase 1's transition).

Verify: `shell-drive.py dock NAME` still lands (the broker's `barSlots`
answers the new layout); functional check: right-click a tile → jump list
present → Esc dismisses.

## Phase 3 — Start, 2026 shape

Replace `FluentStartMenu`'s grid+footer with the single scrollable page:

- **Search** as a real `TextBox` (the SDK has autofocus and Backspace fixed
  since 03a4517/8033c51), fed by the same key routing Launchpad uses so the
  agent-driver path keeps working. Typing switches the page to results.
- **Pinned**: rows of 8 (the 92×88 cell our Windows shell measured), two
  rows by default with "All ›" expanding; pin/unpin from the tile's menu.
- **Recent** (Windows' renamed Recommended): recently installed apps and
  recent files from the portal's recent list; **hideable** from Settings.
- **All apps inline**, below Recent, in three views the user picks and the
  menu remembers: **Category** (groups derived from the registry's
  `Categories=`; most-used first within a group — `AppRegistry` gains a
  launch counter), **Grid** (alphabetical), **List**.
- **Small/Large**: the panel picks its width from the screen (Windows'
  832×864 on a 1080p-class display; narrower on a 1280×800 panel) with an
  explicit override in Settings. Account row hideable.
- Footer keeps user + power. Power confirm becomes a `ContentDialog` over
  Smoke, not a swapped panel.
- Phone Link's side panel: **not** built (nothing to link to).

Sizing continues to come from measurement: run `capture-reference.sh` on the
Windows box with the 2026 Start visible and re-measure before coding the
cells, because the redesign moved Pinned's row count and the section headers.

Verify: functional check drives Start over the broker: open, type, launch,
switch view, hide Recent; screenshot side by side with the reference.

## Phase 4 — Quick Settings, notification centre, toasts

All three are new Fluent builders replacing `_buildControlCenterPopup`,
`_buildNotificationsPopup`, `_buildClockPopup`, `_buildWifiPopup`,
`_buildBatteryPopup` *in this style*; the macOS ones remain macOS's.

- **Quick Settings** (tray button, Win+A): a grid of toggle tiles
  (Wi-Fi with chevron, Dark mode, Tiling, Sound/mute, Record, Record App,
  Night light if the backlight service can do it — otherwise omitted rather
  than dead), accent fill when on with `accentInk` glyphs; brightness and
  volume sliders (`Slider` from the SDK — the Fluent one, correctly, since
  this is shell chrome); a bottom row with battery %, the Settings gear and
  the edit pencil (reorder/hide tiles, per 2026 Windows). **Wi-Fi sub-page**
  slides in from the chevron: network list, password prompt, back arrow —
  today's `_buildWifiPopup` content, Fluent-shaped.
- **Notification centre + calendar** (clock button, Win+N): one panel, 332
  wide, pinned above the bar at the right: notifications on top with
  per-item dismiss, "Clear all" and a Do-not-disturb bell; the **month
  calendar** below, collapsible, today ringed in accent — port the geometry
  from our Windows shell's `ActionCenter.swift`, which was measured off the
  native panel.
- **Toasts**: a `NotificationIntegration` banner surface, bottom-right above
  the taskbar, acrylic, 8px, slides in from the right and out after
  `expire_timeout`; click opens, X dismisses. (In the macOS style the same
  banner goes top-right — new chrome, both styles, per rule 2.)
- Battery detail moves into Quick Settings' bottom row and the power flyout
  is gone from the bar (already the case).

Verify: functional checks for each panel opening from its button and from
its chord; a toast appears for a `notify-send` from a terminal in the
session.

## Phase 5 — menus, dialogs, Task View, Alt+Tab

- **Desktop context menu** → `MenuFlyout` on acrylic with icons: View
  (icon sizes are moot — we have no desktop icons — so: Change wallpaper,
  Appearance, Style ▸, Display settings, Task View, New desktop, Workspace,
  Remove desktop), 8px, elevation 32.
- **Dialogs**: shutdown/restart/logout confirm, the Wi-Fi password prompt,
  and the guest VM's prompts become `ContentDialog`s centred on the invoking
  output over **Smoke**. One `showShellDialog` helper so every dialog is the
  same object.
- **Task View** (Win+Tab, taskbar button): `ShellChrome` gains an
  `overview()` builder — the *layout* of the spaces overview is a style
  question, not a colour one. Fluent: windows grid in the upper area,
  **desktops strip along the bottom** above the taskbar with a "New
  desktop" tile at its right; drag a window onto a desktop; live thumbnails
  are the same textures `MissionControl.swift` already draws. macOS keeps
  its strip on top. Shared geometry helpers move out of `MissionControl.swift`
  into a style-neutral file so neither copies the other.
- **Alt+Tab**: a centred acrylic panel of live window thumbnails with titles,
  cycles on repeat, releases to switch; Esc cancels. Both styles want this;
  the Fluent shape is the reference.

Verify: functional checks for Win+Tab open/close and Alt+Tab switching focus
(the broker reports the focused window).

## Phase 6 — apps, Fluent-first

The largest phase. The Linux desktop is the shell *and* its apps, so the
apps become Fluent-shaped too; the macOS style keeps a palette over the same
controls rather than a second widget tree per app.

1. **Fix the trap.** Reproduce `FluentApp` under `GpuDmaBufRenderer`
   (`STARLING_APP_GTK=1` will not show it — the crash is the DMA-BUF child
   path; use the hot-swap recipe from memory). The recorded signature is a
   `RenderObjectElement` insert cast in the scaffold; fix it in `sdk/`, add
   a test that mounts `FluentApp`+`ScaffoldPage` in the child harness.
2. **One app root.** `StarlingApp` in `sdk/Sources/Flutter/Starling/`
   builds `FluentApp` or `MacosApp` from the pushed style and re-roots on a
   style push (the apps already rebuild on `onStyleChanged`). Controls are
   the Fluent set; the macOS style *recolours* them through
   `StarlingPalette` rather than swapping widget trees — the same bargain
   the shell struck for colours, and the one that keeps this from being a
   second port of every app.
3. **Settings** → `NavigationView` (left pane, search on top) with Windows
   Settings' page shape: `Expander` rows with a `ToggleSwitch` or
   `ComboBox` on the right, cards on the content layer. This is where
   Personalization gains the style, taskbar, Start and colours pages the
   earlier phases need. The three bare Fluent `Slider`s in Settings that
   contradict the current rule become correct rather than removed.
4. **Files** → Explorer's shape (tab strip in the title bar on Mica Alt,
   command bar, breadcrumb + search row, Details columns, status bar) —
   our Windows shell's `Files.swift` was built to exactly this spec and is
   the layout reference; the Linux app is rebuilt on its existing
   `FilesBloc`, and the Windows file is not touched.
5. Remaining first-party apps: swap `Macos*` controls for their Fluent
   counterparts (mechanical: the SDK has each one), `CupertinoIcons` →
   `FluentSystemIcons`, and the type ramp.
6. **Rewrite the standing direction**: apps are Fluent; the check moves from
   "a Fluent widget in `apps/` is a bug" to "a `Macos*` widget in `apps/`
   is a bug"; `MacosApp` stays in the SDK for the macOS style's palette and
   for iOS.

Verify: every app under both styles on the dev box (`build/app-run`), the
DMA-BUF child path specifically (that is where the trap lives), and the
functional tier's app checks.

## Phase 7 — polish that makes it *feel* like Windows

- **Key chords**: Win opens Start; Win+D, Win+E, Win+I, Win+A, Win+N,
  Win+Tab, Win+L (screensaver/lock), Win+arrows (snap), Alt+F4 closes;
  Ctrl+Up stays as an alias for the macOS style.
- **Cursor set** per style (the Windows arrow, hand, I-beam, resize glyphs;
  `DesktopCursor.setShape` already dispatches shapes, the images are a
  style asset).
- **Accent from wallpaper** as an option ("Automatic" in Windows), derived
  where `shellMica` already is.
- **Transparency effects** and **animation** toggles in Settings honoured by
  `ShellTheme.fluent` (solid fallbacks, zero-duration motion) — the same
  switches Windows exposes and the cheapest accessibility win available.
- Focus visuals: the 2px black/white focus ring on keyboard focus, from the
  SDK's `FocusBorder`, once `Focus`/`FocusNode` are real (SDK work, tracked
  separately).

## Files this touches (by phase)

| Phase | Shell | SDK | Elsewhere |
|---|---|---|---|
| 0 | `Utils/ShellStyle.swift`, `Window/DesktopWindow.swift` | `FluentUI/Styles/` (new token files), `FluentTypography.swift`, `Starling/StarlingPalette.swift` | `CLAUDE.md`, `test/functional.py`, `docs/plans/fluent_ui_prereqs_audit.md` |
| 1 | `Window/DesktopWindow.swift`, `Window/FluentTitleBar.swift`, `Shell/OpenAnimations.swift`, `Shell/WindowManager.swift` (snap) | `Rendering/ProxyBox.swift` (partial-alpha opacity) | — |
| 2 | `Fluent/FluentTaskbar.swift`, `Fluent/FluentChrome.swift`, new `Fluent/FluentJumpList.swift` | — | `apps/SettingsApp` (taskbar page) |
| 3 | `Fluent/FluentStartMenu.swift` (rewrite), `Launcher/`, `Shell/DesktopShell.swift` (launch counter) | — | `registry/` (`Categories=` read), `apps/SettingsApp` (Start page) |
| 4 | new `Fluent/FluentQuickSettings.swift`, `Fluent/FluentNotificationCenter.swift`, `Fluent/FluentToast.swift`; `Shell/DesktopShell.swift` popup switch | — | — |
| 5 | new `Fluent/FluentMenus.swift`, `Fluent/FluentTaskView.swift`, `Shell/MissionControl.swift` (split), `Shell/DesktopShell.swift` (Alt+Tab) | — | — |
| 6 | — | `FluentUI/FluentApp.swift` + scaffold (trap), new `Starling/StarlingApp.swift` | every `apps/*/Sources` root; `CLAUDE.md` |
| 7 | `Shell/DesktopShell.swift` (chords), `Utils/DesktopCursor.swift` | `Widgets/FocusManagerStubs.swift` → real focus | `shell/Resources` (cursor set) |

## Traps already known

- **`Positioned` with `right:` and no width hit-tests as nothing** — the
  taskbar clock was visible and dead. Span full width and align inside.
- **`accentInk` is not white** — Fluent's dark accent takes black glyphs.
- **`onDoubleTap` kills tap on the DRM embedder**; detect double-clicks by
  hand (the title bars already do).
- **The window-widget cache keys on flip/texture, not just size** — see
  6fd9080; any new window wrapper (Mica backing, shadow) must not reintroduce
  a build-time bake.
- **`RenderAnimatedOpacity` does not blend partial alpha** for texture
  children; every fade in Phase 1 waits on that fix and must be verified on
  a *real app window*, not a painted box.
- **Acrylic was tried on the taskbar and rejected on measurement** — the
  real bar reads as one flat colour across whatever is behind it. Keep it
  solid; acrylic is for the transient surfaces only, which is also what the
  docs say.
- **Borrowed geometry.** Several Fluent numbers (bar height, icon size,
  Start's cell) were copied from `WinShellBar` so the two shells would
  match, and the comments beside them say so. Where this plan changes a
  number on Linux to match real Windows, the Windows shell stays as it is —
  rewrite the comment at the same time, or the next reader "fixes" the
  divergence back.
- **`DispatchQueue.main` is not the framework thread**; new timers (snap
  flyout dwell, toast expiry, Alt+Tab repeat) use `onPlatformThread(after:)`.

## Decisions taken from the user's direction, and what is still open

Taken, 2026-09-05:

- **Linux desktop only.** The Windows shell is untouched.
- **Fluent is the default** for a fresh install; macOS stays selectable
  (it costs nothing given the seam, and the check that a style is a *shape*
  needs two of them).
- **Apps are part of the desktop** and go Fluent (Phase 6); the macOS style
  recolours them rather than keeping its own controls.
- **The taskbar matches real Windows** (48/24), not our Windows shell.

Still open:

1. **Order.** Phases 1–5 are independent of 6 and of each other apart from
   Phase 1's motion work feeding the rest. Suggested: 0 → 1 → 3 → 4 → 2 → 5
   → 6 → 7, because Start and Quick Settings are what a person sees in the
   first ten seconds and the window material is what they see in every
   screenshot.
2. **Phase 6's size.** It is the one phase measured in weeks rather than
   days; it can follow the chrome phases or run alongside them once the
   DMA-BUF trap is fixed, which is its first step either way.

Sources checked (all read 2026-09-05): fluent2.microsoft.design (home,
What's new, Windows, color, elevation, motion);
learn.microsoft.com/windows/apps/design — signature-experiences/{geometry,
materials, typography, layering, motion, color}, style/{mica, acrylic,
rounded-corner}, basics/{titlebar-design, content-basics},
develop/platform/xaml/xaml-theme-resources; Windows Latest 2026-02-01,
2026-07-01, 2026-08-16; gHacks 2026-07-27; Windows Central and Windows
Forum coverage of the 25H2/26H2 Start, taskbar, Quick Settings and dark-mode
work.
