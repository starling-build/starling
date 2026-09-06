# Fluent UI Prerequisites Audit

Audit of flutter_swift capabilities required for the Fluent UI port.
Searched: `Sources/Flutter/` and `Sources/FlutterSwiftBridge/`

**Status, 2026-09-06:** rows 1, 2, 4 and 5 are DONE — `Overlay`/
`OverlayEntry`, `ImplicitlyAnimatedWidget` and the `Animated*` wrappers,
`GestureDetector`, and the `BackdropFilter` widget all exist, and
`FluentUI/Controls` holds 48 ported controls on top of them (`MenuFlyout`,
`Flyout`, `ContentDialog`, `Tooltip`, `NavigationView`, `TabView`,
`CommandBar`, `Expander`, `InfoBar`, `ToggleSwitch`, `Slider`, …), proven
under real input by `Examples/FluentGallery`. Row 3 (Focus) is still stubs.
The table below is the 2025 audit as written; the rows marked done are kept
for the record of what was missing.

## Summary Table

| # | Capability | Status | Notes |
|---|-----------|--------|-------|
| 1 | Overlay / OverlayEntry | :white_check_mark: Done (2026) — was: Missing | No classes found anywhere in the codebase |
| 2 | Implicit animation widgets (AnimatedContainer, AnimatedOpacity, etc.) | :white_check_mark: Done (2026) — was: Missing | No widget-level implicit animations. Rendering layer has `RenderAnimatedOpacity` and `RenderSliverAnimatedOpacity`, but no `ImplicitlyAnimatedWidget` base class or any `AnimatedFoo` widget wrappers |
| 3 | FocusNode / FocusManager / Focus widget | :warning: Stubs only | `FocusManager` and `FocusScopeNode` are minimal stubs in `Widgets/FocusManagerStubs.swift`. No `FocusNode`, no `Focus` widget, no `FocusScopeWidget` |
| 4 | GestureDetector widget | :white_check_mark: Done (2026) — was: Missing | Gesture recognizer infrastructure exists (`Gestures/Recognizer.swift`, `Gestures/Tap.swift`, `Gestures/Multitap.swift`) but no `GestureDetector` widget that wraps them |
| 5 | BackdropFilter widget | :white_check_mark: Done (2026) — was: Partial | `RenderBackdropFilter` exists in `Rendering/ProxyBox.swift` (complete render object). `BackdropFilterLayer` exists. `BackdropFilterEngineLayer` + `SceneBuilder.pushBackdropFilter` exist in `FlutterSwiftBridge/Compositing.swift`. But no `BackdropFilter` **widget** in `Widgets/Basic.swift` |
| 6 | PageStorage / PageStorageBucket | :white_check_mark: Complete | Full implementation in `Widgets/PageStorage.swift` — includes `PageStorageKey`, `PageStorageBucket`, and `PageStorage` widget with `maybeOf`/`of` lookups |
| 7 | MouseRegion widget | :white_check_mark: Complete | Full implementation in `Widgets/Basic.swift:1743`. Widget creates `RenderMouseRegion` (in `Rendering/ProxyBox.swift:4895`). Supports onEnter, onHover, onExit, cursor, opaque, hitTestBehavior |
| 8 | Listener widget | :white_check_mark: Complete | Full implementation in `Widgets/Basic.swift:1669`. Widget creates `RenderPointerListener`. Supports onPointerDown, onPointerMove, onPointerUp, onPointerHover, onPointerCancel, onPointerPanZoomStart, onPointerSignal |

## Detailed Findings

### 1. Overlay / OverlayEntry -- MISSING

No `Overlay`, `OverlayEntry`, or `OverlayState` classes found in any source file. This is a significant gap -- Fluent UI tooltips, flyouts, dialogs, and command bars all rely on the overlay system.

**Action needed:** Implement `Overlay`, `OverlayEntry`, and `OverlayState` (from `packages/flutter/lib/src/widgets/overlay.dart`).

### 2. Implicit Animation Widgets -- MISSING

No `ImplicitlyAnimatedWidget` base class or `AnimatedWidgetBaseState` found. No widget-level animated wrappers (`AnimatedContainer`, `AnimatedOpacity`, `AnimatedAlign`, `AnimatedPadding`, `AnimatedPositioned`, etc.).

The rendering layer does have:
- `RenderAnimatedOpacity` in `Rendering/ProxyBox.swift:725` (animation-driven opacity)
- `RenderAnimatedOpacityProtocol` in `Rendering/ProxyBox.swift:616`
- `RenderSliverAnimatedOpacity` in `Rendering/ProxySliver.swift:671`

These are render-level primitives driven by explicit `Animation<Double>` objects, not the implicit animation widget system.

**Action needed:** Implement `ImplicitlyAnimatedWidget`, `AnimatedWidgetBaseState`, and key implicit animation widgets. Also requires the `Animation` / `AnimationController` / `Tween` system if not already present.

### 3. FocusNode / FocusManager / Focus Widget -- STUBS ONLY

File: `Widgets/FocusManagerStubs.swift`

Contains minimal stubs:
- `FocusManager` -- empty class with `init()` and `registerGlobalHandlers()` (no-op)
- `FocusScopeNode` -- empty class with `init()` only

Missing entirely:
- `FocusNode` (the core focus management primitive)
- `Focus` widget
- `FocusScope` widget
- `FocusTraversalPolicy` and related traversal classes
- Key event handling integration

**Action needed:** Full focus management system implementation. This is critical for Fluent UI -- nearly every interactive widget needs focus support (buttons, text fields, navigation views, etc.).

### 4. GestureDetector Widget -- MISSING

The gesture recognizer infrastructure exists at the low level:
- `GestureRecognizer` base class in `Gestures/Recognizer.swift`
- `TapGestureRecognizer` in `Gestures/Tap.swift`
- `DoubleTapGestureRecognizer` in `Gestures/Multitap.swift`

But there is no `GestureDetector` widget that wraps these recognizers into a convenient widget API. Comments in recognizer files reference `GestureDetector` as a related widget, confirming it is expected but not yet implemented.

**Action needed:** Implement `GestureDetector` and `RawGestureDetector` widgets (from `packages/flutter/lib/src/widgets/gesture_detector.dart`).

### 5. BackdropFilter Widget -- PARTIAL (render layer only)

Present:
- `RenderBackdropFilter` in `Rendering/ProxyBox.swift:1043` -- full render object with filter, blendMode, enabled properties, paint override using `BackdropFilterLayer`
- `BackdropFilterLayer` in `Rendering/ProxyBox.swift:368` -- compositing layer stub
- `BackdropFilterEngineLayer` in `FlutterSwiftBridge/Compositing.swift:463` -- engine layer wrapper
- `SceneBuilder.pushBackdropFilter` in `FlutterSwiftBridge/Compositing.swift:996` -- fully implemented

Missing:
- `BackdropFilter` widget in `Widgets/Basic.swift` (the `SingleChildRenderObjectWidget` that creates `RenderBackdropFilter`)

**Action needed:** Add `BackdropFilter` widget wrapper -- straightforward since the render object is already complete.

### 6. PageStorage / PageStorageBucket -- COMPLETE

File: `Widgets/PageStorage.swift`

Full implementation including:
- `PageStorageKey<T>` (generic, Hashable-conforming)
- `PageStorageBucket` with `writeState`/`readState` methods
- `PageStorage` widget (StatelessWidget) with `maybeOf`/`of` static lookups
- Internal `_StorageEntryIdentifier` for path-based key resolution
- Internal `_PageStorageKeyProtocol` for type erasure

No action needed.

### 7. MouseRegion Widget -- COMPLETE

File: `Widgets/Basic.swift:1743`

Full `SingleChildRenderObjectWidget` implementation:
- Creates `RenderMouseRegion` (in `Rendering/ProxyBox.swift:4895`)
- Properties: onEnter, onHover, onExit, cursor, opaque, hitTestBehavior
- Both `createRenderObject` and `updateRenderObject` implemented

No action needed.

### 8. Listener Widget -- COMPLETE

File: `Widgets/Basic.swift:1669`

Full `SingleChildRenderObjectWidget` implementation:
- Creates `RenderPointerListener`
- Properties: onPointerDown, onPointerMove, onPointerUp, onPointerHover, onPointerCancel, onPointerPanZoomStart, onPointerSignal, behavior
- Both `createRenderObject` and `updateRenderObject` implemented

No action needed.

## Priority Order for Implementation

1. **Focus system** (FocusNode, FocusManager, Focus widget) -- blocks nearly all interactive Fluent UI widgets
2. **GestureDetector widget** -- blocks buttons, tappable surfaces, drag interactions
3. **Overlay / OverlayEntry** -- blocks tooltips, flyouts, dialogs, dropdown menus
4. **Animation system + implicit animation widgets** -- blocks animated transitions, hover effects
5. **BackdropFilter widget** -- low effort (render object exists), needed for acrylic/mica materials
