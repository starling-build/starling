# A native Apple UI framework on Core Animation and UIKit

Design note, 2026-09-16. Status: proposal, nothing implemented. Supersedes
the first draft (`native-ca-backend.md`), which framed this as a second
backend for the ported Flutter SDK. This version is a fresh framework that
copies what it needs from the SDK rather than porting the SDK.

## Context

The goal is a declarative Swift UI framework that is native on iOS and
macOS, measurably faster than SwiftUI on real workloads, and as fast as
UIKit wherever UIKit is fast. App authors never write against UIKit's
imperative API, but every control they use is the real UIKit object.

What the SwiftUI/UIKit investigation (Sept 2026) established:

- SwiftUI is layer-backed: every pixel goes through `RBLayer`, a `CALayer`
  subclass in the private RenderBox framework. The real comparison is
  SwiftUI-managed animation against explicitly submitted `CAAnimation`.
- A submitted `CAAnimation` keeps moving through a blocked main thread
  because the render server interpolates it. SwiftUI samples its springs in
  the app every frame and pushes the already-sampled value to Core
  Animation as a presentation override (Macomber, 2026-09-16). It can do
  that off-main, but stalls on three traced conditions: contention on a
  shared update lock, content needing main-thread reconciliation, and
  structural tree changes when an animated effect reaches identity.
- SwiftUI's measured slowness on real workloads is its update cycle and its
  bridged containers, not its animation engine. The iOS 26.1 benchmark that
  found 3.4 hitches/s in `List` against 0.7 in `UICollectionView` was
  measuring the bridge and the body/diff/layout loop.
- Native feel comes from UIKit objects, not from pixels: navigation
  transitions, sheet presentation, scroll physics, text entry, menus,
  Dynamic Type, right-to-left, VoiceOver, Liquid Glass. Reimplementing any
  of them drifts within one OS release.

The design follows from those four points: match UIKit's vocabulary and
behaviours by wrapping its objects; do not match its node model, because a
`UIView` per node is UIKit's performance ceiling and SwiftUI's bridging
architecture at once.

## Goal

1. A declarative Swift API using Apple's vocabulary (`HStack`, `VStack`,
   `ZStack`, `Grid`, `Text`, `Image`, `Button`, `Toggle`, `ScrollView`,
   `List`, `NavigationStack`, sheets, menus).
2. Layout and content live in a retained render tree committed to a
   `CALayer` tree once per frame. Core Animation composites. No Skia, no
   engine.
3. Every control, scroll container, navigation container and presentation
   is the UIKit (later AppKit) object, wrapped as a native node with a size
   contract.
4. Opacity, transform, clip and position animations on content are
   submitted to the render server as `CAAnimation`s and survive a blocked
   main thread. Everything else animates in-process, as in UIKit and
   SwiftUI.
5. Lists recycle at the layer level over a `UIScrollView`, which is where
   "faster than SwiftUI" is measured.

Non-goals: Linux, Windows, and the Starling desktop, which stay on the
ported SDK and the engine; reimplementing system chrome; a Catalyst build;
matching SwiftUI's full API surface.

## The three kinds of node

| Kind | Examples | Backed by | Owns |
|---|---|---|---|
| **Layout** | `HStack`, `VStack`, `ZStack`, `Grid`, `Spacer`, padding, overlays, alignment | Nothing, or a `CALayer` when it is a repaint boundary or animated | Layout only |
| **Content** | `Text`, `Image`, shapes, `Color`, gradients, custom drawing | `CALayer` (properties, `CAShapeLayer`, `CAGradientLayer`, or a CoreGraphics bitmap) | Drawing, render-server animation |
| **Native** | every `UIControl`, `UITextField`/`UITextView`, `UIScrollView`, `UINavigationController`, `UISheetPresentationController`, `UIMenu`, `WKWebView`, `AVPlayerLayer`, maps | The UIKit object itself | Native behaviour, accessibility, text input |

A native node is a leaf with a size contract: the framework sizes and
positions it, it never sizes itself, and its internal state changes are
ordinary rebuilds that never participate in animation frames. A container
native node (`ScrollView`, `NavigationStack`) hosts a framework subtree
inside the UIKit object, and the framework renders that subtree into layers
under the object's own layer.

This is SwiftUI's actual structure with the drawing side made explicit and
the update model replaced.

## What is copied from the ported SDK

Copied, not depended on. The SDK keeps serving Linux and Windows unchanged.

- The retained render-object pipeline: `markNeedsLayout` /
  `markNeedsPaint`, relayout and repaint boundaries, the layout protocol
  (`Rendering/RenderObject.swift`, `Rendering/Box.swift`).
- Layout algorithms for flex, stack, wrap and grid
  (`Rendering/Flex.swift`, `Rendering/Stack.swift`, `Rendering/Wrap.swift`).
- The gesture arena and recognizers (`Gestures/`), minus their
  `Foundation.Timer` use, which is replaced by display-link time.
- Animation curves, springs and the `Tween` types (`Animation/`).
- The element/rebuild model with `InheritedWidget`-style dependencies, so
  state changes rebuild the subtree that read them and nothing else.

Not carried: slivers, `Material`, `Cupertino`, `Fluent`, the `Macos*`
control library, the engine bridge, the painting backend, libtxt text,
platform-view stubs, and the Flutter widget API surface itself.

## No Skia

| Job | Done by |
|---|---|
| Recording drawing | A Swift command list on the content node, resolved at commit |
| Rasterization | CoreGraphics on a raster queue for bitmaps; `CAShapeLayer` and `CAGradientLayer` for vector fills; Core Animation composites on the GPU |
| Compositing | `CALayer` tree, one `CATransaction` per frame |
| Text | CoreText |
| Image decoding | ImageIO, `CGImage` as `contents` |
| Path operations | `CGPath`, including boolean ops on macOS 13 / iOS 16+ |
| Blur, colour matrices, masks | Core Image on the raster queue; not compositor-animatable in v1 |
| Custom shaders | Not in v1; would be a `CAMetalLayer` native node |
| External textures | `IOSurface` as `contents` |
| Frame scheduling | `CADisplayLink` / `CVDisplayLink` |

## Rendering

### Content resolution

A content node records drawing into a command list. At commit the list
resolves to one of:

1. **Layer properties.** Solid fill, rounded corners, border, shadow map
   onto `backgroundColor`, `cornerRadius`, `borderWidth`, `shadow*`. A
   gradient becomes a `CAGradientLayer`; a single path becomes a
   `CAShapeLayer`. Cheap, resolution-independent, animatable by the render
   server.
2. **CoreGraphics bitmap.** Everything else replays into a `CGContext` on
   the raster queue and becomes `contents`. The commit waits only when the
   layer is new or resized.

Text is always a bitmap layer of its own, so a decorated box with text
animates the box on the server and reuses the text bitmap.

### Text

CoreText for shaping, line breaking and metrics, rasterized on the raster
queue. Text editing is a native node (`UITextField`, `UITextView`), so the
framework's own text layout never has to support editing, selection or
IME. That removes the largest risk the earlier draft carried.

### Layer twins and commit discipline

Each repaint boundary, animated node and content node has a retained
`CALayer`, created on first commit and reused while the node lives. The
frame loop is: display link → gesture and animation tick → rebuild →
layout → paint → commit. Commit diffs the render tree against the layer
tree and writes every change inside one `CATransaction` with implicit
actions disabled. One commit per frame, at one point, never from a UIKit
callback.

Two rules keep UIKit's update cycle out of ours: no Auto Layout on the host
or on any ancestor of a native node, and `layoutSubviews` on the host does
nothing but forward its size as a resize event. This is the one seam where
"all bugs are bridging bugs" applies, so it is one function with a debug
assertion that nothing else touches a `CALayer`.

## Animations

Two classes, chosen by the framework:

- **Compositor-owned.** An animation whose only effect is opacity,
  transform, clip, corner radius or position on a content node or repaint
  boundary. The framework submits one additive `CABasicAnimation` or
  `CASpringAnimation` per property, sets the model to the end state, and
  stops ticking. It keeps a *shadow spring* per animation: the same math
  and start time, evaluated only when a retarget arrives, giving current
  displacement and velocity without reading `presentationLayer`. This is
  the deliberate departure from SwiftUI: we hand Core Animation the
  timeline for stall immunity and keep the state for retargeting.
- **In-process.** Layout-changing animations, custom animatable data,
  custom drawing. Sampled at display-link time with SwiftUI's formula
  (`presentation = target + animation(delta, t) - delta`), written through
  the public `CABasicAnimation` presentation-override form (`beginTime =
  -1`, fill forwards, never removed, `toValue` only) so per-frame writes
  never trigger implicit actions or layout. `CAPresentationModifier` is
  private and is not used.

Three rules from the SwiftUI stall analysis:

1. No shared lock between the commit and off-main work. The raster queue
   reads an immutable snapshot taken at commit.
2. No structural change at identity. A transform reaching identity or an
   opacity reaching 1.0 keeps its layer until the node goes away.
3. Native nodes never participate in animation frames.

## Native nodes

### Controls

Each control is a thin wrapper: a declarative description on the framework
side, a `UIControl` on the UIKit side, and a reconciler that applies
property changes and translates events into the framework's state model.
Initial set, in priority order: `Button`, `Toggle`, `Slider`, `Stepper`,
`SegmentedControl`, `TextField`, `TextEditor`, `SecureField`,
`ProgressView`, `DatePicker`, `Picker` (menu form), `Menu`,
`ColorPicker`, `Label` with symbol images. Sizing uses the control's
`intrinsicContentSize` and `sizeThatFits` under the framework's
constraints; the control never runs Auto Layout.

### Containers

- **`ScrollView`** is a `UIScrollView`. The framework sets `contentSize`,
  reads `contentOffset` every frame, and lays out the visible subtree into
  layers under the scroll view's content layer. Physics, indicators,
  rubber banding and the scroll-to-top gesture are UIKit's.
- **`List`** is a `ScrollView` plus layer-level recycling: rows keep their
  layers across scrolls and a fixed pool is reused for rows entering the
  viewport. No `UICollectionView`, so no bridge, and the row content is
  framework content nodes, so row animations are compositor-owned.
  Swipe actions, selection and reordering are added in a second pass,
  possibly by falling back to `UICollectionView` for lists that need them.
- **`NavigationStack`** is a `UINavigationController`; each destination is
  a `UIViewController` hosting a framework subtree. Push, pop, the
  interactive back swipe and the navigation bar are UIKit's.
- **Sheets, popovers, alerts** are `UISheetPresentationController`,
  `UIPopoverPresentationController` and `UIAlertController`.
- **`TabView`** is a `UITabBarController`.

### Hit testing and gestures

The framework's gesture arena is authoritative for layout and content
nodes. A native node receives touches through UIKit's responder chain
inside its own bounds, and the framework never installs recognizers on it.
`ScrollView` is the one shared case and is handled by reading
`contentOffset`, not by arbitrating touches.

### Accessibility

Native nodes are accessible for free. Content and layout nodes expose an
accessibility tree through `UIAccessibilityContainer` on the host view,
generated from the render tree's semantics annotations. This is much
smaller than the earlier draft's plan because text entry and every control
are native.

## macOS

UIKit does not exist on macOS outside Catalyst, and AppKit's controls
differ in behaviour, not only in class name. The plan is iOS first, then a
second native-node mapping onto AppKit: `NSButton`, `NSSwitch`, `NSSlider`,
`NSTextField`, `NSScrollView`, `NSSplitViewController` for navigation,
`NSPanel` and sheets, `NSMenu`. Layout, content, rendering and animation are
shared, because `CALayer` is the same on both platforms. Budget it as its
own phase; do not assume it is free.

## Build

A new SwiftPM package, `native/` at the repo root, depending on nothing
from `sdk/`. Copied sources are copied, with a header naming the SDK file
they came from. `#if canImport(UIKit)` and `#if canImport(AppKit)` select
the native-node mapping in sources.

## Phases

Each phase ends with a measurement.

### Phase 0: calibration spike and benchmark (1 month)

- Two-week spike: render one existing app screen through content nodes
  and a `CALayer` tree with a CoreGraphics canvas and CoreText, no
  controls. Time it. If it takes four weeks, scale every estimate below by
  1.5.
- Benchmark feed, three versions: SwiftUI `List`, `UICollectionView`, and
  a placeholder for this framework. Variable-height cells, images,
  gradients, autoplaying animations, gestures. Measure hitch rate with a
  display-link timestamp logger and Xcode's hitch tracker, CPU at rest,
  memory. Record the numbers in this document.

### Phase 1: core tree and rendering (3 months)

- Element/rebuild model, retained render tree, layout nodes (stacks,
  grid, padding, overlay, alignment), copied from the SDK.
- Content nodes with the two resolution strategies, raster queue with
  snapshots, CoreText text, ImageIO images, `CGPath` shapes.
- Layer twins and the single-commit function.
- UIKit host: window, root layer, display link, touch and keyboard
  translation, resize.

Exit: the spike screen renders through the real pipeline; a golden suite
exists; layer count and commit time per frame are logged.

### Phase 2: animations (1.5 months)

- Compositor-owned class with additive submission and shadow springs.
- In-process class with display-link sampling and presentation-override
  writes.
- Tests: fade, scale, slide and an interrupted spring through a 2 s
  main-thread block; shadow prediction versus `presentationLayer` at
  retarget under one frame of travel on a 120 Hz device.

Exit: the four animations keep moving through the block; retargets show
no velocity discontinuity.

### Phase 3: native controls and containers (3 months)

- Control wrappers, about a week each, in the priority order above.
- `ScrollView` over `UIScrollView`; `NavigationStack` over
  `UINavigationController`; sheets, popovers, alerts; `TabView`.
- Hit-testing split between the arena and the responder chain.

Exit: a demo app with navigation, forms and sheets built only from the
public API, passing VoiceOver on its controls.

### Phase 4: lists and the go/no-go (1.5 months)

- Layer-level recycling `List`.
- Benchmark feed on this framework.

Exit: beats the SwiftUI `List` numbers and is within 20% of
`UICollectionView` on hitch rate, with CPU at rest at or under 15% and
memory at or under 1.5× the collection view. If it does not, this plan
stops here and the reasons go in this document.

### Phase 5: accessibility for content nodes, polish (1.5 months)

- `UIAccessibilityContainer` over the render tree for content and layout
  nodes; Dynamic Type propagation into `Text`; right-to-left layout.

Exit: VoiceOver reads the demo app end to end.

### Phase 6: macOS (4 months)

- AppKit host and the AppKit native-node mapping; menus, key equivalents,
  multiple windows, per-screen display links.

Exit: the demo app runs on macOS from the same source.

### Phase 7 (stretch): off-main in-process animation (2 to 3 months)

A snapshot-driven evaluator so custom animatable data continues through a
main-thread block, which is SwiftUI's differentiator. Only after Phase 4's
numbers, and only if in-process animations are what the measurements say
is hurting.

## Spike results (2026-09-16)

A ~300-line AppKit spike (`docs/plans/spikes/native-spike`) built the core of Phase
1 and Phase 2 on an M1 Pro at 2x: a retained node tree with layout nodes
(`Column`, `Row`), content nodes (`Box` resolved to layer properties,
`Label` resolved to a CoreText bitmap), one `CATransaction` per commit, a
compositor-owned `CASpringAnimation` with a shadow spring, an in-process
spring written through the `CABasicAnimation` presentation-override form,
and a 2 s `Thread.sleep` on the main thread mid-animation.

| Measurement | Result |
|---|---|
| First commit, 400 CoreText labels + 6 boxes (406 layers) | layout 7 ms, raster + commit 14 ms, synchronous on main |
| Steady commit, nothing dirty, 406 layers | 0.18 ms |
| Relayout of all 400 labels, no repaint | 6 ms (all in `CTLineCreateWithAttributedString`) |
| Per-frame override write for one in-process animation | 40 µs |
| Shadow spring vs `presentationLayer`, before retarget | ≤ 0.1 px |
| Shadow spring vs `presentationLayer`, at retarget | 0.01 px |
| Shadow spring vs `presentationLayer`, after retarget and after the block | ≤ 0.2 px |
| Compositor-owned ball during the 2 s main-thread block | kept moving (screenshot mid-block shows it displaced from its pre-block position) |
| In-process ball during the block | frozen at its overshoot position, then jumped to the settled value on wake |

What the spike settled, and what it changed in this plan:

- **The shadow spring works, with two implementation facts that were wrong
  in the first draft.** `CASpringAnimation.initialVelocity` is normalised
  to the animated distance, like `UIView`'s `initialSpringVelocity`, with
  positive meaning toward the target; in points per second it runs away
  (the ball reached x = 34,000). And the shadow's clock must be pinned by
  setting the animation's `beginTime` from `layer.convertTime(_:from:)`
  rather than reading the commit's time back; the first attempt at reading
  `beginTime` after commit was flaky between runs (1 px one run, 83 px the
  next).
- **Retargeting from the shadow is exact**, so the earlier plan to read
  `presentationLayer` at retarget is unnecessary and the plan's "under one
  frame of travel" test bar is met with margin.
- **Layer commit is cheap; text layout is the cost.** 0.18 ms to walk 406
  layers is noise. Six milliseconds to re-create 400 `CTLine`s is the
  number to design around: cache lines by (string, font, width) and treat
  a `Label` as a relayout boundary. Rasterization at 35 µs per label is
  fine on the raster queue and not fine on main, which confirms the
  raster-queue design.
- **Dynamic system colours resolve through the current appearance.** The
  first screenshots had invisible text because `NSColor.labelColor.cgColor`
  resolved for dark mode on a hard-coded light background. The framework's
  colour type must carry appearance resolution explicitly, at the point a
  colour becomes a `CGColor`, and the commit must know which appearance the
  host view is in.
- **Calibration.** This slice took about an hour, not two weeks, because it
  has no controls, no hit testing, no multi-line text and no diffing. It
  does not move the estimates; it confirms that the parts of Phases 1 and
  2 that the estimates treat as mechanical are mechanical.

## Effort

| Phase | Estimate |
|---|---|
| 0. Spike and benchmark | 1 month |
| 1. Core tree and rendering | 3 months |
| 2. Animations | 1.5 months |
| 3. Controls and containers | 3 months |
| 4. Lists, go/no-go | 1.5 months |
| **iOS core** | **10 months** |
| 5. Accessibility and polish | 1.5 months |
| 6. macOS | 4 months |
| **iOS and macOS** | **15.5 months** |
| 7. Off-main custom animation | 2 to 3 months |

One senior engineer, in order. Two engineers get the iOS core to about six
calendar months, since rendering and controls do not depend on each other
after Phase 1's host exists. Decision points: after Phase 1 there is a
Skia-free renderer regardless; after Phase 4 the performance claim is
settled by numbers.

## Risks and traps

- **Two update cycles.** Ours and Core Animation's. One commit function, a
  debug assertion on layer setters, no Auto Layout, no UIKit re-entry.
- **Native node sizing.** Controls that size themselves from content
  (`UILabel` in a `UIButton` configuration, `UITextView`) must be measured
  with `sizeThatFits` under our constraints and pinned with frames. A
  control that runs its own Auto Layout inside is fine; one that
  constrains against its superview is not, and must be wrapped in a
  container view we own.
- **Layer explosion.** Only boundaries, animated nodes and content nodes
  get layers. Watch the count in the benchmark.
- **Feature gaps versus Skia.** Blend modes, image filters, shader masks
  go through Core Image or are unsupported. Anything needing a custom
  shader on composited output is a `CAMetalLayer` node and out of v1.
- **Identity removal.** Keep the layer at identity values.
- **Lists that need UIKit features.** Swipe actions, reordering and
  selection are cheap on `UICollectionView` and expensive to rebuild. The
  fallback is a `UICollectionView`-backed `List` variant, which carries
  the bridge cost; make it opt-in per list, not the default.
- **macOS drift.** A control that exists on one platform and not the other
  needs an honest answer in the API, not an emulation.
- **Scope creep toward SwiftUI's surface.** The API should cover what
  apps need, not what SwiftUI has. Every added view is a week plus an
  AppKit twin.

## Open questions

- Whether `AnimatedContainer`-style layout animations should be
  compositor-owned by animating `bounds` on the boundary layer while layout
  runs once for the end state, which is how `UIView.animate` handles frame
  changes.
- Whether `NavigationStack` destinations should be one `UIViewController`
  each (UIKit's model, free transitions) or one hosting controller with
  framework-drawn transitions (one process, interruptible, but reimplements
  the back swipe). Default to UIKit's model.
- Whether the Starling shell's macOS build should eventually move to this
  framework. It depends on external textures and the DMA-BUF child model,
  neither of which exists on macOS today.

## Sources

- Kyle Macomber, How SwiftUI animation works (2026-09-16): https://openswiftuiproject.org/blog/how-swiftui-animation-works/
- Explore SwiftUI animation, WWDC23: https://developer.apple.com/videos/play/wwdc2023/10156
- What's new in SwiftUI, WWDC25: https://developer.apple.com/videos/play/wwdc2025/256/
- Is SwiftUI finally as fast as UIKit in iOS 26?: https://blog.jacobstechtavern.com/p/swiftui-vs-uikit
- Touch to Pixels, iOS UI pipeline internals: https://blog.jacobstechtavern.com/p/ui-pipeline-internals
- RenderBox `RBLayer` header: https://github.com/xybp888/iOS-Header/blob/master/13.0/PrivateFrameworks/RenderBox.framework/RBLayer.h
- Animate UIKit views with SwiftUI animations (iOS 18): https://nilcoalescing.com/blog/AnimateUIKitViewsWithSwiftUIAnimations/
- Square Blueprint: https://github.com/square/Blueprint
- Texture / AsyncDisplayKit: https://texturegroup.org
