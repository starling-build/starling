# Screen-reader support: a Semantics widget and platform bridges (plan, U-A11Y-2)

Status: plan, not built. Author: amd-perf, 2026-11-25. Asked for by starling-bd.

## Where we are
- The render layer has the pieces: `SemanticsNode`, `SemanticsOwner`, `SemanticsConfiguration`, `SemanticsData`,
  `RenderSemanticsAnnotations` (Rendering/ProxyBox.swift) and `describeSemanticsConfiguration` on render objects
  (RenderParagraph labels, gesture handlers).
- There is NO widget that builds `RenderSemanticsAnnotations` (no `Semantics`, `MergeSemantics`, `ExcludeSemantics`).
  Apps cannot name a control. A few widgets take a `semanticLabel` (HoverButton, TabView) but nothing reads it.
- The only consumer of semantics today is `AgentSemanticsEndpoint` (sdk/Platform): a snapshot walker for agents on Linux.
  It is not Flutter's incremental semantics compiler, so no semantics update ever reaches the engine.
- The engine side exists: `PlatformDispatcher.setSemanticsEnabled`, `FlutterSemanticsUpdate2` in embedder.h, and
  `SemanticsUpdateBuilder` bridges (web: FlutterSwiftBridgeWeb/Semantics.swift). The C++ `UpdateSemantics` bridge is a STUB.
- What the apps carry today: our sweep test (AccessibleNameSweepTests) shows every ribbon button has a tooltip or text,
  every dialog field a placeholder or label. That is the label data to feed in; it is not yet announced by anything.

## Smallest first slice (S1: widget + tree, no platform yet)
1. `Semantics` widget (label, hint, value, button, textField, checked/selected, enabled, onTap) building
   `RenderSemanticsAnnotations`; plus `MergeSemantics` and `ExcludeSemantics`.
2. Make the shared controls use it once: `FlatButton` (tip becomes label, `checked` becomes toggled), `FluentTextBox`
   (placeholder or `label:` parameter), `DialogShell` (dialog role, title), `MenuFlyoutItem`. One edit each, so every
   app gets names for free.
3. Run the real semantics compiler: `SemanticsOwner.sendSemanticsUpdate` into a `SemanticsUpdateBuilder`, only when
   `semanticsEnabled` is true (cost is zero otherwise).

## Test (S1, headless, no platform needed)
- Extend WidgetTester with `semantics()`: the node list (label, flags, actions) from the owner.
- The sweep asserts on THAT list, not on tooltips: every node with a tap action or text-field flag has a non-blank label.
  Failing-without check: remove a tip from one button and the sweep names it.
- `AgentSemanticsEndpoint` switches to the same tree, so agent tests and a11y tests share one source.

## Slice 2: bridges, one platform at a time (the engine delivers `FlutterSemanticsUpdate2` nodes to the embedder)
1. Web (ARIA): FlutterSwiftBridgeWeb/Semantics.swift already exists. Map nodes to a hidden DOM layer with role, aria-label,
   aria-checked, tabindex. Testable with a browser snapshot.
2. Linux (AT-SPI): our DRM embedder implements `update_semantics_callback2`; export nodes over D-Bus
   (org.a11y.atspi Accessible, Action, Text). Needs `atk-bridge`-free path: write the small subset ourselves
   (name, role, state, bounds, DoAction). Test with `dogtail` or `accerciser`-style query script on a headless session.
3. macOS (NSAccessibility): an `NSAccessibilityElement` per node under the Flutter view; labels, role, frame, press action.
4. iOS (UIAccessibility): `UIAccessibilityElement` containers, same node mapping, `accessibilityActivate` for tap.
Order by value to the user: Linux (this desktop) first, then web, then macOS, then iOS.

## Risks and questions
- Incremental update correctness (node ids stable across frames): reuse Flutter's compiler, do not hand-roll.
- Text editing (Writer's canvas editor) is a custom render object: it needs its own node with value, selection and
  text-field actions. Largest single item; defer to S3.
- AT-SPI over D-Bus on our minimal session: confirm a bus is available to the app (the shell owns the session bus).
