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

**macOS-only build note.** The engine is `FlutterMacOS.framework` plus a
separate `libswift_bridge.dylib`, and `--mac-cpu arm64` decides both the ABI
and the output directory (`out/host_debug_arm64`). Full commands in the
README's *Building → macOS*.

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
