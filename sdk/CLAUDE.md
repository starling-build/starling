# CLAUDE.md

Starling SDK: the Flutter framework ported to Swift, driven by the Flutter
engine's C core. No Dart VM. (The SwiftPM package name remains `FlutterSwift`.)

## Layout

- `Sources/` — SDK targets only (the framework, bridges, and the three windowed
  hosts: `FlutterGTK` on Linux, `FlutterCocoa` on macOS, `FlutterWin32` on
  Windows, each with a `*Bridge` target holding the platform C/ObjC glue).
- `Examples/` — everything app-related: `FlutterDemoApp`, the ported samples,
  their shared `ExampleHost`, and `Examples/Calendar/` (the kalender port:
  `Library/` is the `CalendarKit` target, `App/` is `CalendarApp`).

## Build and test

```bash
swift build -c release
tools/run-tests.sh        # not `swift test` — see README (Ubuntu 26.04 <cmath> clash)
```

## The hosts, and the one thing they must each get right

Every host starts the engine in **Swift mode** and then runs the platform's own
event loop. What differs is when the embedder would otherwise start a *Dart*
engine on its own, and each host is pinned around that moment:

- **GTK** — the engine starts when the view realizes, so
  `fl_engine_set_swift_runtime` is set before the window is shown.
- **Win32** — the engine starts inside view-controller creation, so Swift mode
  is set on the engine before that call.
- **Cocoa** — `FlutterViewController.viewWillAppear` calls `runWithEntrypoint:`
  if the engine is not already running. So the order in `flcocoa_host.m` is
  load the view (assign `contentViewController`), *then* run the engine, *then*
  show the window — and both halves matter. Running before the view loads means
  the engine's initial `FlutterWindowMetricsEvent` is skipped
  (`updateWindowMetricsForViewController` returns early for an unloaded view)
  and nothing composites; showing before running hands you a Dart isolate.
- **UIKit** — the mirror image of Cocoa: `FlutterViewController.initWithEngine:`
  takes an engine as given and never starts one (`initWithProject:` is the path
  that would), so there is no race to win. What is forced instead is the
  *shape*: `UIApplicationMain` owns the launch sequence and never returns, so
  the engine can only be built inside a delegate callback, the widget tree is
  mounted from there, and `UIKitHost` therefore has no create/mount/run split
  like the other three. That is why `windowedHostBoot`'s `root` is `@escaping`.

**The UIKit host insets its view, and every app depends on it.** The
FlutterViewController is a child of `FlUIKitRootViewController`, pinned to the
safe-area layout guide rather than made the window's root. The framework has
no MediaQuery padding and no `SafeArea` widget — it grew up on a desktop,
where nothing overlaps a window — so a tree given the whole screen draws its
first row under the status bar. If a `SafeArea` is ever ported, this is what
it replaces.

**macOS-only build note.** The engine is `FlutterMacOS.framework` plus a
separate `libswift_bridge.dylib`, and `--mac-cpu arm64` decides both the ABI
and the output directory (`out/host_debug_arm64`). Full commands in the
README's *Building → macOS*.

## Fluent: the design system lives here, and the gallery is its proof

`Sources/Flutter/FluentUI/` is Windows 11's Fluent, as Microsoft ships it in
2026, independent of any desktop or app:

- **Tokens are code, never literals.** `Styles/FluentTokens.swift` holds the
  shape ramp and Windows' corner roles (`FluentCorners.control` 4,
  `.overlay` 8), the spacing ramp and layout rules (`FluentSpacing`), stroke
  widths, the Fluent 2 motion ramp plus Windows' named animations
  (`FluentMotion.directEntrance` = 250 ms on `decelerateMid`), and the
  elevation roles with Fluent 2's two-layer shadow recipe
  (`FluentElevation.shadows(32, brightness:)`). Colours are WinUI's own
  resource dictionary (`Styles/ColorResources.swift`); the default accent is
  Windows' default blue with Windows' seven shades
  (`FluentColors.windowsBlue`), and controls take Dark 1 in light and Light 2
  in dark exactly as `AccentFillColorDefaultBrush` does. A Fluent surface
  with a bare `8` or `Color(0x…)` in it is a bug.
- **Materials are recipes.** `Styles/FluentMaterials.swift` carries WinUI's
  acrylic brushes and the MicaController defaults as `FluentMaterialRecipe`
  (tint, tint opacity, luminosity opacity, fallback, blur), and the colour
  arithmetic Windows composes them with (`FluentColorMath.luminosityBlend`).
  `Controls/Surfaces/Acrylic.swift` is the real recipe over a
  `BackdropFilter`; `Mica.swift` resolves an OPAQUE colour from one wallpaper
  sample (`MicaBackdrop` above the tree supplies it, a host's business) and
  goes to the documented fallback when inactive or when
  `FluentMaterialSettings` has transparency off; `Smoke` is the modal dim.
- **Type ramp** is WinUI's (`Styles/FluentTypography.swift`): Caption is
  Regular, Body Large Strong exists, nothing is Bold or Italic. Selawik
  (`FluentSystemIcons` target) is Microsoft's own metric-compatible stand-in
  for Segoe UI Variable; a theme passes it as `fontFamily`.
- **`Icon`** (`Widgets/Icon.swift`) is the framework's glyph widget, sized
  and inked by `IconTheme`. The example host's older `Icon` stays for the
  Material samples' CupertinoIcons auto-registration; do not use both in one
  file.
- **`StarlingApp`** (`Sources/Flutter/Starling/StarlingApp.swift`) is the
  root a Starling desktop app hangs from: it seeds light/dark and the style
  from what the shell pushed over the DMA-BUF socket, rebuilds on a push
  WITHOUT changing the tree's shape (a root that swapped `FluentApp` for
  `MacosApp` would remount `home` and drop the app's state for a colour
  change), and installs both `AnimatedFluentTheme` and `AnimatedMacosTheme`
  over one `Navigator`, each from `StarlingPalette`. `StarlingFonts` loads
  the SDK's own faces by family on first use — `Icon` asks for its glyph's
  family, `StarlingApp` for the palette's — so the three icon modules'
  `registerFont()` are aliases and an app registers nothing.
  `FluentAppMountTests` mounts `FluentApp`+`ScaffoldPage` and `StarlingApp`
  through the element harness.
- **Escape is the `DismissStack`** (`Widgets/DismissStack.swift`): whatever
  opens a transient surface pushes a closer and pops it when the surface
  goes away by other means; `FocusManager.dispatchKeyData` hands an
  unclaimed Escape to the top. Flyouts, modal routes and the file dialog's
  overlay already do this. A control that swallows Esc (returns true from
  its `onKeyData`) hides it from the stack — `FluentTextBox` unfocuses and
  returns false for exactly that reason.
- **Every control must be a tappable semantics node.** `HoverButton`
  presses on raw pointer events, which the agent endpoint cannot see; it
  wraps itself in `_GestureSemantics` so the functional tier and any agent
  can tap what a pointer can. A new control that takes presses some other
  way needs the same wrapper, or it is a label with nothing to do.
- **`Controls/Dialogs/FluentFilePanel.swift`** is the desktop's file
  dialog (open/save/directory, an overlay for apps, full-window for the
  portal picker). Its glyphs are Fluent System Icons by code point,
  because `FluentSystemIcons` depends on this module and cannot be
  imported here — keep them in step with the generated file.
- **`Examples/FluentGallery`** is the WinUI 3 Gallery's shape on this SDK:
  a NavigationView of design-guidance pages (the tokens, drawn) and one
  `SamplePage` per ported control, light and dark, over Mica. It is the
  acceptance test for anything in `FluentUI/`: a token or control change that
  looks wrong there is wrong. Run it on a live desktop with
  `swift build -c release --product FluentGallery` and the GTK host;
  `FLUENT_GALLERY_PAGE=design/Color FLUENT_GALLERY_DARK=1` opens a page
  directly for screenshots. Adding a control's page is one `GalleryEntry`.
- Values are pinned by `Tests/FlutterTests/FluentUI/FluentTokensTests.swift`
  against WinUI's XAML, @fluentui/tokens and `UISettings` — a failure there
  means the SDK drifted from Windows, not that a test is stale.
- **Marks are painted, never typed.** `Styles/FluentGlyph.swift` draws the
  chevrons, check, dismiss, dot, ellipsis and InfoBar badges the controls
  need. They were text glyphs (`"\u{25BC}"`, a Segoe MDL2 code point for
  the pane expander) and Selawik has none of them, so a missing glyph drew
  as nothing — no twisties, no chevrons, a checked box that was a plain
  square. A `"\u{…}"` in a control is a bug; add a `FluentGlyphKind`.

Two framework traps the gallery found, both of the "blank subtree, no
error" kind:

- **A `CompositedTransformTarget` painted nothing.** Every flyout-anchored
  control (drop-down, combo box, split button, the date and time pickers,
  auto-suggest, teaching tip, menu bar) was invisible. `LeaderLayer` and
  `FollowerLayer` were stubs that never applied their offset — fixed, they
  are real ports now — but the deeper cause is this port's painting model:
  there are no interior repaint boundaries, so every `PaintingContext` is
  bounded in ABSOLUTE coordinates, while a leader paints its child at the
  layer origin (Dart's contract). The child's picture was then recorded with
  a cull rect it lay entirely outside of, and the engine drops such ops at
  record time. `RenderLeaderLayer.paint` now hands the child a giant
  `childPaintBounds`, as `RenderFollowerLayer` always did. Anything else that
  pushes a layer and paints its child at `.zero` needs the same.
- **`NavigationView` centred short pages and let its pane overflow.** Its
  body row now stretches and its items scroll; the WinUI Gallery was the
  first consumer with a page shorter than the window and a pane longer than
  it.
- **A flyout filled the window.** The overlay lays its entries out TIGHT
  to its own size, so a `CompositedTransformFollower` placed straight in an
  entry was as big as the overlay, anchored by the overlay's centre, and its
  content stretched across the whole window. `_FlyoutPositioner` now aligns
  the follower top-left under loose constraints and sizes the content with
  `IntrinsicWidth`/`IntrinsicHeight` inside WinUI's flyout box
  (`kFlyoutThemeConstraints`, 96–456 wide, 40–756 tall). Anything else that
  puts a follower in an overlay needs the same.
- **Showing a flyout from inside a build does nothing.** `TeachingTip` asked
  its controller to show during its first build and in `didUpdateWidget`,
  when the target below was not attached yet; the guard returned and the tip
  never appeared. `addPostFrameCallback` is still a stub, so it defers with a
  one-shot `Ticker` (`_deferShow`) — the frame boundary that exists.
- **`Navigator(home:)` showed its first `home` forever.** The initial route
  carried the widget it was created with, and nothing updated it when the
  app above rebuilt with a new one — so the gallery's page selection, its
  dark-mode switch and its wallpaper setting all ran `setState` and changed
  nothing on screen. Every click was arriving (the pane items highlighted,
  the expanders toggled — those have their own state) and only the
  app-level state was inert, which is the signature. `NavigatorState.
  didUpdateWidget` now swaps the route's child and rebuilds its entry.
  Env-var page selection (`FLUENT_GALLERY_PAGE`) never showed this because
  it is applied in the first build.
- **A menu is an overlay entry, not a route.** `MenuFlyoutItem` used to
  close itself with `Navigator.maybePop`, which pops nothing; the menu stayed
  open after every click. Content closes the flyout it is in through
  `FlyoutScope` (`FlyoutScope.of(context).closeAll()` for a menu chain,
  `.close()` for one), which `showFlyout` puts at the root of every flyout
  and links to the flyout its target sat inside.
- **A submenu has no barrier of its own** (`showFlyout(barrier: false)`).
  With one, the parent menu was covered: its other items could not be
  hovered, and a click on one dismissed the submenu instead of reaching the
  item. Without one, the parent stays live — hovering another of its items
  for `FluentMotion.menuShowDelay` (Windows' 400 ms `MenuShowDelay`) closes
  the submenu, resting on the sub-item opens it — and a click anywhere else
  lands on the parent's barrier, which closes both. Submenus sit
  `.rightEdgeAlignedTop`; drop-down buttons and menu-bar items hang
  `.bottomEdgeAlignedLeft`, as WinUI's do.
- **`Foundation.Timer` fires on no host we run.** Not the DRM embedder
  (documented) and not the GTK host either — its main loop is GLib's, and
  Foundation's run loop never turns. `Tooltip` waited on one and never
  appeared under a resting pointer. Anything in `FluentUI/` that waits uses
  `FluentDelay` (`Styles/FluentDelay.swift`, a one-shot on the frame clock);
  `FluentTextBox`'s caret still has a Foundation timer and is the next to
  move. (The control is `FluentTextBox`, not `TextBox` — that name is the
  framework's text-layout struct, and `Scrollbar` is likewise
  `FluentScrollbar`.)
- **`RenderAnimatedOpacity` never pushed an opacity layer.** It painted
  its child straight for every non-zero alpha, so a `FadeTransition` was a
  one-frame blink at its end — the desktop's window motion stayed
  scale-only for months on the strength of a comment recording exactly
  that. It now paints through `pushOpacity` like `RenderOpacity`
  (`Tests/FlutterTests/Rendering/AnimatedOpacityTests.swift` pins it). A
  transition that "does nothing" on this port: check the render object
  pushes its layer before blaming the compositor.
- **`HoverButton` pressed on ANY button.** Its press detection is raw
  pointer events (older than `GestureDetector`), and it fired `onPressed`
  on every pointer release whatever the button — a right-click on a Start
  tile launched the app under the menu that was opening. It is the primary
  button only now, and only after a press that began on it, which is what
  `GestureDetector.onTap` means. A control that wants a secondary action
  takes its own `Listener` and reads `event.buttons & kSecondaryButton`.
- **`Text(rich:)` dropped its `style:` and the ambient DefaultTextStyle.**
  Dart hangs a rich span under the effective style; the port handed the
  span over bare, so a tooltip's caption painted in the paragraph default —
  white on the light surface, invisible. Fixed in `Widgets/Text.swift`.
  The other rich-text user is `TerminalView`, whose rows must NOT inherit
  (a theme body style's line height would stretch them off the grid): its
  row and run styles are `inherit: false` now, which `TextStyle.merge`
  honours. Anything laid out on a grid wants the same.

Flyouts are Windows' now in every respect the gallery can show: acrylic
(`Acrylic` over the thin default recipe, the flyout stroke drawn in the
foreground so the blur does not soften it, the elevation-32 shadow under),
and they enter with `FluentEntrance` — Windows' direct entrance, a 167 ms
slide from the target's side with a fade on the decelerate curve. Wrap any
transient surface in `FluentEntrance` to make it enter the same way.

The gallery opens its own flyouts, menus, dialog and teaching tip when
`FLUENT_GALLERY_AUTO=1` is set (`AutoTrigger`), which is how those were
screenshotted on a shell whose pointer injection had gone stale.

## Widget composition: use the trailing-closure result builders

`Sources/Flutter/Widgets/ResultBuilders.swift` gives every common container a
trailing-closure overload (`ChildrenBuilder` for `children:`, `ChildBuilder`
for `child:`). Prefer it over building `var children: [Widget]` imperatively
or standing a `SizedBox` in for "no child" — `if`, `if let`, `switch`, and
`for` work directly in the block, and a helper returning `Widget?` splices in
as zero-or-one children:

```swift
Column(crossAxisAlignment: .stretch) {
    HeaderRow()
    if state.showLane { _buildLane() }        // _buildLane() -> Widget? also works
    for date in dates { Expanded { DayCell(date) } }
}
```

Both spellings compile to the identical tree, and the ported
`children: [Widget]` / `child:` initializers remain the canonical 1:1 Dart
mapping — keep the array form where the children are a data-driven `.map`
(e.g. `LayoutId`-keyed tiles for a `CustomMultiChildLayout`), and note that
some widgets (`GestureDetector`, inherited widgets) have no builder overload.
When adding a builder overload, mirror the wrapped initializer's parameters
exactly, defaults included — a divergence is silently unexpressible in the
builder spelling rather than an error.

## App state: the BLoC pattern

Apps and app-level packages (see `Examples/Calendar/Library/CalendarBloc.swift`,
modeled on the desktop's `FileExplorerBloc`) use one value-type `State` struct,
one `Event` enum, and an `@Observable` bloc whose `add(_:)` is the only way the
UI mutates anything. Widgets read `bloc.state`, dispatch events, and rebuild
through `withObservationTracking` — not controllers, callbacks, or
`ValueNotifier` subscriptions (`ChangeNotifier.removeListener` is a documented
best-effort stub; avoid patterns that depend on it).
