# Starling SDK guide

How to write an app with the framework: the app skeleton, the widget model,
and a catalogue of every widget, control and service the SDK ships, with the
constructor shapes as they are in the tree today.

The [README](README.md) covers the other half — building the package,
linking an engine, consuming it as a dependency, the bundles and the
platform notes — and is not repeated here. If you have never built the SDK,
start there, or run `tools/starling-create` and come back with a project
that compiles.

This is a port of Flutter's framework to Swift, so everything below has a
Dart original, and the [Flutter widget docs](https://docs.flutter.dev/ui/widgets)
remain the reference for *why* a widget behaves as it does. What this guide
adds is *what is here*, spelled the Swift way, and where the port differs.

Contents

1. [Start here](#1-start-here)
2. [Widgets, state and the build](#2-widgets-state-and-the-build)
3. [Layout](#3-layout)
4. [Painting and decoration](#4-painting-and-decoration)
5. [Text and icons](#5-text-and-icons)
6. [Scrolling](#6-scrolling)
7. [Pointer, keyboard and focus](#7-pointer-keyboard-and-focus)
8. [State beyond setState](#8-state-beyond-setstate)
9. [Animation](#9-animation)
10. [Navigation, dialogs and overlays](#10-navigation-dialogs-and-overlays)
11. [The macOS control set (MacosUI)](#11-the-macos-control-set-macosui)
12. [The Fluent control set (FluentUI)](#12-the-fluent-control-set-fluentui)
13. [The terminal widget](#13-the-terminal-widget)
14. [Platform services](#14-platform-services)
15. [What is not here yet](#15-what-is-not-here-yet)
16. [Testing](#16-testing)
17. [Traps](#17-traps)

---

## 1. Start here

### The smallest app

```swift
import ExampleHost          // runExampleApp — a window on GTK, Cocoa or Win32
import Flutter              // the framework
import FlutterSwiftBridge   // Offset, Size, Rect, Color, Paint, Canvas (dart:ui)

class Hello: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        // A tree with no MacosApp/FluentApp above it MUST start with
        // Directionality — the first Text without one brings the process down.
        return Directionality(
            textDirection: .ltr,
            child: Center(child: Text("It runs."))
        )
    }
}

runExampleApp(title: "Hello", width: 480, height: 320) { Hello() }
```

That is the whole program: no Dart, no code generation, no `main.dart`.
`swift run -c release` from a project made by `tools/starling-create`, or
`swift run -c release CounterApp` in this repo for the same thing with a
counter in it.

### Three entry points

Which one you call decides where the tree is shown.

| Call | Module | Where the tree runs |
|---|---|---|
| `runExampleApp(title:width:height:root:)` | `ExampleHost` | A window on the desktop session — the engine's own GTK embedder on Linux, Cocoa on macOS, Win32 on Windows. What the samples use. |
| `runApp(_:)` | `Flutter` | As a **Starling desktop app**: if the shell spawned the process (`FLUTTER_DMABUF_SOCKET` is set) the tree renders into the shell's compositor over a DMA-BUF socket and gets the shell's clipboard; otherwise it sets up the bare binding. This is what the apps under the desktop's `apps/` call. |
| `runStarlingApp(title:width:height:root:)` | `Flutter` | Whichever applies: the shell's socket when set, else an installed windowed host. For the standalone case link `FlutterGTK` and call `GTKWindowedHost.install()` first, or it fails with a message saying so. |

`ExampleHost` also exposes `activeGTKHost` (Linux) for window control after
mounting — `setFullscreen(_:)`, `makeDmaBufTexture()` — and
`ensureEngineData()` which links `data/{icudtl.dat,flutter_assets}` beside
the binary on first run.

### The manifest and the imports

`tools/starling-create` writes the manifest; the README's *Consuming it*
explains it. The two things that are not optional on any target that uses
the framework: `.interoperabilityMode(.Cxx)` (not inherited from the
dependency) and, on Ubuntu 26.04, the two glibc math flags (same reason).

Products you will import:

| Import | For |
|---|---|
| `Flutter` | Everything in this guide — widgets, rendering, gestures, animation, MacosUI, FluentUI, the terminal, the platform services. |
| `FlutterSwiftBridge` | The `dart:ui` types: `Offset`, `Size`, `Rect`, `RRect`, `Radius`, `Color`, `Paint`, `Path`, `Canvas`, `Image`, `KeyData`. `Flutter` does **not** re-export them, so any file that names one imports this too. |
| `CupertinoIcons` | 1,322 SF-Symbols-style glyphs as `IconData`. |
| `FluentSystemIcons` | 89 Fluent glyphs, plus the Selawik font. |
| `ExampleHost` | `runExampleApp` and the Material-look chrome the samples use (`MaterialScaffold`, `MaterialAppBar`, `MaterialFloatingActionButton`, `MaterialDivider`, `MaterialPageRoute`, `MaterialColors`, `Icon`). Sample scaffolding, not framework — it lives under `Examples/`. |
| `FlutterGTK` | `GTKWindowedHost.install()` for `runStarlingApp`, `GTKHost` for a window you drive yourself. |
| `FlutterShared` | The dynamic product (`libFlutterShared.so`) the desktop's apps link instead of `Flutter`, so a fleet shares one copy. Same API. |

Both `Flutter` and `FlutterSwiftBridge` define a `TextStyle` (the
framework's and `dart:ui`'s). With both imported, an explicitly typed
declaration needs `Flutter.TextStyle`; a `style:` argument infers fine.

### The samples

All under `Examples/`, all targets of this package, all `swift run -c
release <Name>`:

| Sample | Shows | Platforms |
|---|---|---|
| `CounterApp` | `StatefulWidget` + `setState`, the ExampleHost chrome | Linux, macOS, Windows |
| `TodosApp` | MacosUI: `MacosApp`, scaffold, toolbar, text field, checkbox, list tile | Linux |
| `StartupNamerApp` | `Navigator` push/pop, `ListView(itemBuilder:)`, `GestureDetector` | Linux |
| `FlutterDemo` | `AnimationController` + `TickerProvider`, `CustomPaint`, frame timing | Linux |
| `TerminalDemo`, `TerminalTiling` | `TerminalView`; a split/float workspace of them | Linux, Windows |
| `CalendarApp` (+ `CalendarKit`) | The BLoC pattern with `@Observable`, custom multi-child layouts, a real library target | Linux |
| `YouTubeApp` | External textures, an async bloc, fullscreen through `activeGTKHost` | Linux |
| `WinShellBar` | A Windows taskbar replacement with its own theme | Windows |

There is no Fluent sample; the Fluent set is exercised by the Starling
desktop's Windows style rather than by an app here.

---

## 2. Widgets, state and the build

The model is Flutter's, one to one. A `Widget` is an immutable description;
the framework inflates it into an `Element` that owns the state and the
`RenderObject`. You subclass two of them.

### StatelessWidget

```swift
class Greeting: StatelessWidget {
    let name: String
    init(name: String, key: (any Key)? = nil) {
        self.name = name
        super.init(key: key)
    }
    override func build(_ context: any BuildContext) -> Widget {
        Text("Hello, \(name)")
    }
}
```

`Widget.init(key:)` is the only base initializer; `key:` is by convention
the first parameter of every widget and defaults to `nil`.

### StatefulWidget and State

```swift
class Counter: StatefulWidget {
    let step: Int
    init(step: Int = 1) { self.step = step; super.init() }
    override func createState() -> State<StatefulWidget> { _CounterState() }
}

class _CounterState: State<StatefulWidget> {
    private var count = 0

    override func initState() {
        super.initState()                 // one-time setup; the tree is not laid out yet
    }

    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)  // the parent rebuilt with a new Counter
    }

    override func dispose() {
        super.dispose()                   // controllers, timers, subscriptions
    }

    override func build(_ context: any BuildContext) -> Widget {
        let step = (widget as! Counter).step
        return PushButton(
            child: Text("\(count)"),
            onPressed: { [weak self] in
                guard let self else { return }
                self.setState { self.count += step }
            }
        )
    }
}
```

Two port-specific spellings. `createState()` returns `State<StatefulWidget>`
and the `State` subclass is declared on `State<StatefulWidget>`, not
`State<Counter>` — so the configuration is reached through `widget as!
Counter`. And `setState` takes a closure: mutate inside it, and the element
is marked dirty for the next frame.

The lifecycle hooks are Flutter's: `initState`, `didChangeDependencies`,
`build`, `didUpdateWidget(_:)`, `deactivate`/`activate`, `dispose`,
`reassemble`. `mounted` is true between `initState` and `dispose`;
`context` is the element (weak).

### BuildContext

What a context can do for you: `dependOnInheritedWidgetOfExactType(T.self)`
(subscribe to an inherited widget — how every `X.of(context)` works),
`findAncestorStateOfType(T.self)`, `findRenderObject()`, and `size` once
laid out. `Builder(builder:)` gives you a fresh context below a widget you
just created, for the `of(context)` calls that must see it.

### Keys

`ValueKey(v)`, `ObjectKey(o)`, `UniqueKey()`, `GlobalKey<SomeState>()`,
`LabeledGlobalKey`, `GlobalObjectKey`, and `PageStorageKey` for scroll
positions that survive a rebuild. Keys mean what they mean in Flutter:
identity across rebuilds. They matter more here than you may be used to —
see the lazy-list trap in §17.

### The two spellings

Every ported widget takes `children: [Widget]` or `child: Widget`, exactly
as in Dart. The common containers also take a trailing closure, which is a
result builder: `if`, `if let`, `switch` and `for` work inside it, and an
expression of type `Widget?` splices in as zero-or-one children.

```swift
Column(crossAxisAlignment: .stretch) {
    HeaderRow()
    if state.showLane { laneWidget() }          // laneWidget() -> Widget? is fine
    for date in dates { Expanded { DayCell(date) } }
}
```

Both compile to the identical tree. The containers with the closure form:

> `AbsorbPointer` `Align` `AspectRatio` `Center` `ClipOval` `ClipRect`
> `ClipRRect` `ColoredBox` `Column` `ConstrainedBox` `DecoratedBox`
> `Expanded` `FittedBox` `Flex` `Flexible` `FractionallySizedBox`
> `GridView` `IgnorePointer` `IndexedStack` `IntrinsicHeight`
> `IntrinsicWidth` `LimitedBox` `ListBody` `ListView` `MacosScaffold`
> `Offstage` `Opacity` `Padding` `Positioned` `RotatedBox` `Row`
> `ScaffoldPage` `SingleChildScrollView` `SizedBox` `SliverFixedExtentList`
> `SliverGrid` `SliverList` `Stack` `Wrap`

Keep the array form for data-driven `.map` lists and for widgets that have
no overload (`GestureDetector`, inherited widgets). If you add a parameter
to a ported widget's initializer, add it to the overload too — the block
spelling cannot express what the overload lacks, and nothing warns
(`test/lint.py` in the desktop repo catches the drift).

---

## 3. Layout

Flutter's box protocol: constraints go down, sizes come up, the parent
positions. The widgets are the same names with the same parameters.

### Multi-child

| Widget | Constructor | Notes |
|---|---|---|
| `Row`, `Column` | `(mainAxisAlignment: .start, mainAxisSize: .max, crossAxisAlignment: .center, spacing: 0, children:)` | `Flex(direction:)` is the general form. `spacing:` is the upstream gap parameter. |
| `Expanded` | `(flex: 1, child:)` | Fills the main axis. |
| `Flexible` | `(flex: 1, fit: .loose, child:)` | May fill it. |
| `Stack` | `(alignment: AlignmentDirectional.topStart, fit: .loose, clipBehavior: .hardEdge, children:)` | |
| `Positioned` | `(left:top:right:bottom:width:height:child:)`, `(fill: (), child:)`, `(fromRect:child:)`, `(fromRelativeRect:child:)` | See §17 for the `right:`-with-no-width trap. |
| `IndexedStack` | `(index:children:)` | Shows one child, keeps the rest alive. |
| `Wrap` | `(direction: .horizontal, alignment: .start, spacing:, runAlignment:, runSpacing:, crossAxisAlignment:, children:)` | |
| `Flow` | `(delegate:children:)` | With a `FlowDelegate`. |
| `ListBody` | `(children:)` | Non-scrolling stacked list. |
| `CustomMultiChildLayout` | `(delegate:children:)` with `LayoutId(id:child:)` on each child | `MultiChildLayoutDelegate`; the calendar library's day grid is one. |

### Single-child

| Widget | Constructor | Notes |
|---|---|---|
| `Padding` | `(padding: EdgeInsets, child:)` | |
| `Align` | `(alignment: .center, widthFactor:, heightFactor:, child:)` | `Center` is `Align` at `.center`. |
| `SizedBox` | `(width:height:child:)`, `(expand: (), child:)`, `(shrink: (), child:)`, `(size:child:)`, `(square:child:)` | `SizedBox(shrink: ())` is the idiom for "no widget here" in an array — or use a `Widget?` in the block form. |
| `ConstrainedBox` | `(constraints: BoxConstraints, child:)` | |
| `FractionallySizedBox` | `(alignment:widthFactor:heightFactor:child:)` | |
| `LimitedBox` | `(maxWidth:maxHeight:child:)` | |
| `OverflowBox`, `SizedOverflowBox` | `(min/max…:child:)`, `(size:child:)` | |
| `AspectRatio` | `(aspectRatio:child:)` | |
| `IntrinsicWidth`, `IntrinsicHeight` | `(child:)` | Expensive; the usual advice applies. |
| `Baseline` | `(baseline:baselineType:child:)` | |
| `FittedBox` | `(fit: BoxFit, alignment:, child:)` | |
| `Offstage` | `(offstage: Bool, child:)` | Laid out, not painted, not hit. |
| `RotatedBox` | `(quarterTurns:child:)` | Rotates the *layout*. |
| `Transform` | `(transform: Matrix4, …)`, `(rotate:child:)`, `(translate:child:)`, `(scale:child:)` | Paint-time only; layout is unaffected. |
| `FractionalTranslation` | `(translation: Offset, child:)` | |
| `MeasureSize` | `(onSize: (Size) -> Void, child:)` | Port-specific: reports the child's laid-out size. |
| `CompositedTransformTarget` / `Follower` | `(link:child:)` | `LayerLink` for overlays that track a widget. |

There is no `Container` and no `Spacer`. `Container` is a convenience
Flutter builds from the above; write the composition you mean
(`Padding` → `DecoratedBox` → `SizedBox`). A spacer is
`Expanded(child: SizedBox(shrink: ()))`.

`EdgeInsets` comes as `EdgeInsets(all:)`, `EdgeInsets(horizontal:vertical:)`
and `EdgeInsets(left:top:right:bottom:)`, plus `EdgeInsetsDirectional`
with `start`/`end`. `Alignment` has the nine named corners and centres
(`.topLeft`, `.center`, …); `AlignmentDirectional` the start/end versions.

### A toolbar row, both spellings

```swift
// array form
Row(children: [
    Expanded(child: MacosTextField(placeholder: "Search")),
    SizedBox(width: 8, height: 1),
    PushButton(child: Text("Go"), onPressed: run),
])

// block form
Row {
    Expanded { MacosTextField(placeholder: "Search") }
    SizedBox(width: 8, height: 1)
    PushButton(child: Text("Go"), onPressed: run)     // no overload: keep child:
}
```

---

## 4. Painting and decoration

### Decoration widgets

| Widget | Constructor |
|---|---|
| `DecoratedBox` | `(decoration: BoxDecoration, position: .background, child:)` |
| `ColoredBox` | `(color:child:)` — hit-tests **opaque even at alpha 0**, see §17 |
| `Opacity` | `(opacity:child:)` |
| `ClipRect`, `ClipOval` | `(clipper:clipBehavior:child:)` |
| `ClipRRect` | `(borderRadius: BorderRadius.zero, clipper:, clipBehavior: .antiAlias, child:)` |
| `PhysicalModel` | `(shape:borderRadius:elevation:color:shadowColor:child:)` |
| `BackdropFilter` | `(filter: ImageFilter, child:)` — blur what is behind |
| `ImageFiltered` | `(imageFilter:child:)` — filter the child itself |
| `ColorFiltered` | `(colorFilter:child:)` |
| `RepaintBoundary` | `(child:)` — isolates a subtree's layer |
| `PerformanceOverlay` | `()` — the engine's frame graph |

`BoxDecoration(color:border:borderRadius:boxShadow:gradient:backgroundBlendMode:shape:)`
with `Border.all(color:width:style:)`, `BorderRadius.circular(r)` /
`.all(Radius)` / `.only(topLeft:…)` / `.vertical(top:bottom:)` /
`.horizontal(left:right:)`, `BoxShadow(color:offset:blurRadius:spreadRadius:)`,
and `LinearGradient(begin:end:colors:stops:)`, `RadialGradient`,
`SweepGradient`. `ShapeDecoration` takes a `ShapeBorder`:
`RoundedRectangleBorder`, `CircleBorder`, `StadiumBorder`,
`BeveledRectangleBorder`, `ContinuousRectangleBorder`, `OvalBorder`,
`StarBorder`, `LinearBorder`.

```swift
DecoratedBox(
    decoration: BoxDecoration(
        color: theme.canvasColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: Color(0x33000000), offset: Offset(0, 2), blurRadius: 6)]
    ),
    child: Padding(padding: EdgeInsets(all: 12), child: content)
)
```

### Colour

`Color` is the `dart:ui` struct: `Color(0xAARRGGBB)`, `Color(argb: a, r, g, b)`,
`Color(rgbo: r, g, b, opacity)`; `withOpacity(_:)`, `withAlpha(_:)`,
`withValues(alpha:red:green:blue:)`, `withRed`/`Green`/`Blue`;
`Color.lerp(a, b, t)` and `Color.alphaBlend(foreground:background:)`.
In a themed app take colours from `MacosTheme.of(context)` (or
`StarlingPalette` under the desktop) rather than literals — the desktop
runs a light and a dark palette and switches at runtime.

### CustomPaint

Subclass `CustomPainter` (it is a class here, not a protocol), override
`paint(_:_:)` and `shouldRepaint(_:)`, and hand it to `CustomPaint(painter:size:child:)`:

```swift
class BarsPainter: CustomPainter {
    let values: [Double]
    init(values: [Double]) { self.values = values }

    override func paint(_ canvas: Canvas, _ size: Size) {
        let paint = Paint()
        let w = size.width / Double(max(values.count, 1))
        for (i, v) in values.enumerated() {
            paint.color = v > 0.8 ? Color(0xFFE05050) : Color(0xFF50A0E0)
            let h = v * size.height
            canvas.drawRect(Rect.fromLTRB(Double(i) * w, size.height - h,
                                          Double(i) * w + w - 1, size.height), paint)
        }
    }

    override func shouldRepaint(_ old: CustomPainter) -> Bool {
        (old as? BarsPainter)?.values != values
    }
}

CustomPaint(painter: BarsPainter(values: samples), size: Size(320, 80))
```

The `Canvas` is `dart:ui`'s: `drawLine`, `drawRect`, `drawRRect`,
`drawDRRect`, `drawRSuperellipse`, `drawOval`, `drawCircle`, `drawArc`,
`drawPath`, `drawPoints`, `drawVertices`, `drawImage`, `drawImageRect`,
`drawImageNine`, `drawAtlas`, `drawPicture`, `drawParagraph`, `drawShadow`,
`drawColor`, `drawPaint`; `save`/`saveLayer`/`restore`,
`translate`/`scale`/`rotate`/`transform`, `clipRect`/`clipRRect`/`clipPath`.
`Paint` carries `color`, `style` (`.fill`/`.stroke`), `strokeWidth`,
`strokeCap`, `strokeJoin`, `shader`, `maskFilter`, `colorFilter`,
`blendMode`, `isAntiAlias`. `Path` is the full API including
`PathMetrics`.

To paint text inside a painter use a `TextPainter`:

```swift
let tp = TextPainter(text: TextSpan(text: label, style: style), textDirection: .ltr)
tp.layout(maxWidth: size.width)
tp.paint(canvas, Offset(0, size.height - tp.height))
```

### Images

There is **no `Image` widget** yet. The pieces beneath it exist —
`ImageProvider` with `FileImage`, `MemoryImage`, `ExactAssetImage`,
`ResizeImage`, the `ImageCache`, `DecorationImage`, and `RenderImage` —
and the widget that ties them together has not been ported. What the apps
do instead:

```swift
// decode once (off the frame), keep the ui.Image
let image: Image = try await decodeImageFromList([UInt8](data))
// or: let codec = try await FlutterSwiftBridge.instantiateImageCodec(bytes)

// draw it in a CustomPainter
canvas.drawImageRect(image,
    Rect.fromLTWH(0, 0, Double(image.width), Double(image.height)),   // src
    Rect.fromLTWH(0, 0, size.width, size.height),                    // dst
    paint)
```

`decodeImageFromPixels(_:width:height:…)` builds an image from raw RGBA.
For frames produced elsewhere (a video decoder, a GPU) register an
**external texture** and show it with `TextureWidget(textureId:)` — see
`GpuDmaBufRenderer` in §14 and the YouTube sample.

---

## 5. Text and icons

### Text

```swift
Text("Hello", style: TextStyle(color: c, fontSize: 13, fontWeight: .w600),
     textAlign: .center, maxLines: 1, overflow: .ellipsis, softWrap: false)

Text(rich: TextSpan(children: [
    TextSpan(text: "bold ", style: TextStyle(fontWeight: .bold)),
    TextSpan(text: "and not"),
]))
```

`TextStyle(inherit:color:backgroundColor:fontSize:fontWeight:fontStyle:letterSpacing:wordSpacing:height:foreground:background:shadows:fontFeatures:fontVariations:decoration:decorationColor:decorationStyle:decorationThickness:fontFamily:fontFamilyFallback:overflow:)`
— merge with `.merge(_:)` / `.copyWith(…)` as in Dart.

`DefaultTextStyle(style:child:)` sets the inherited default (`MacosApp`
installs one from its typography); `DefaultTextHeightBehavior` likewise.
`RichText` is the render-level widget `Text` builds on. `InlineSpan`
subclasses: `TextSpan(text:children:style:recognizer:)` and
`PlaceholderSpan`. `StrutStyle` and `TextScaler` are ported.

Fonts: `fontFamily:` names a family the engine's font manager can find
(system fonts by name on Linux through fontconfig, plus whatever the app
registered). Bundled in the SDK: the two icon fonts, Selawik
(`SelawikFont.registerFont()`), and for the terminal Roboto Mono and
DejaVu Sans Mono (`TerminalFontLoader`). As the terminal's loader
documents, the engine does no per-glyph system fallback of its own — a
glyph missing from every listed family paints nothing — so give
`fontFamilyFallback:` when you mix scripts or symbols.

### Icons

An icon is an `IconData(codePoint, fontFamily:)` drawn as one glyph of an
icon font. Two fonts ship:

- `CupertinoIcons` — 1,322 names (`CupertinoIcons.add`, `.folder`,
  `.heart_fill`, `.chevron_right` …). Call `CupertinoIcons.registerFont()`
  once before the first icon builds — the root widget's `initState` is the
  usual place. It is idempotent.
- `FluentSystemIcons` — 89 names, the Windows style's set.

The framework's icon widget is `MacosIcon(icon:color:size:)` (theme
colour and size when nil). `ExampleHost` has a plain `Icon(_:size:color:)`
for the samples that registers the font itself. Fluent's `IconButton`
takes any widget as its icon.

---

## 6. Scrolling

| Widget | Constructor |
|---|---|
| `ListView` | `(scrollDirection: .vertical, reverse:, controller:, physics:, shrinkWrap:, padding:, itemExtent:, children:)` |
| `ListView` (builder) | same, with `itemCount:` and `itemBuilder: (BuildContext, Int) -> Widget?` — return `nil` to end the list |
| `GridView` | `(…, crossAxisCount:, mainAxisSpacing:, crossAxisSpacing:, childAspectRatio:, children:)` or `(…, gridDelegate:, children:)` / `(…, gridDelegate:, itemCount:, itemBuilder:)` |
| `SingleChildScrollView` | `(scrollDirection:, reverse:, controller:, physics:, padding:, child:)` |
| `MacosScrollbar` | `(controller:, scrollDirection:, isAlwaysShown:, child:)` — wraps a scrollable, shares its controller |

```swift
ListView(padding: EdgeInsets(all: 16), itemCount: rows.count) { _, i in
    RowTile(rows[i])
}
```

`ScrollController(initialScrollOffset:keepScrollOffset:)`: `offset`,
`position`, `hasClients`, `jumpTo(_:)`, `animateTo(_:duration:curve:)`,
and it is a `ChangeNotifier` — `addListener` for scroll-driven UI.
Physics: `ClampingScrollPhysics`, `BouncingScrollPhysics`,
`AlwaysScrollableScrollPhysics`, `NeverScrollableScrollPhysics`,
`RangeMaintainingScrollPhysics`. Scroll events reach ancestors as
notifications: `NotificationListener<ScrollNotification>(child:onNotification:)`
with `ScrollStart`/`Update`/`End`, `Overscroll` and `UserScroll`
subclasses; `SizeChangedLayoutNotifier` reports layout changes the same way.

The sliver layer is ported — `SliverList`, `SliverGrid`,
`SliverFixedExtentList`, `SliverPadding`, `SliverToBoxAdapter`,
`PinnedHeaderSliver`, `SliverChildListDelegate` /
`SliverChildBuilderDelegate` — and is what `ListView` and `GridView` are
built from. There is no `CustomScrollView` yet, so composing slivers of
your own means building on `Scrollable` directly.

The MacosUI layout widgets that scroll (`ContentArea`, `MacosSidebar`)
hand your builder a `ScrollController` to attach; see §11.

---

## 7. Pointer, keyboard and focus

### Gestures

`GestureDetector(…, behavior: HitTestBehavior?, child:)` takes the full
Flutter set: `onTap`/`onTapDown`/`onTapUp`/`onTapCancel`, the secondary
and tertiary variants, `onDoubleTap`, `onLongPress` (+ start/move/end/up),
`onVerticalDrag*`, `onHorizontalDrag*`, `onPan*`, `onScale*`,
`onForcePress*`, plus `dragStartBehavior` and `supportedDevices`.

```swift
GestureDetector(
    onTap: { select(item) },
    onSecondaryTapUp: { details in showMenu(at: details.globalPosition) },
    behavior: .opaque,                  // hit the whole box, not just painted pixels
    child: row
)
```

`behavior: .opaque` matters whenever the child has transparent areas;
the default `.deferToChild` hits only what the child paints. The gesture
arena, recognizers (`TapGestureRecognizer`, `PanGestureRecognizer`, …)
and `RawGestureDetector` are all ported for custom recognizers.

Two lower-level widgets: `Listener(onPointerDown:onPointerMove:onPointerUp:onPointerHover:onPointerCancel:onPointerSignal:onPointerPanZoom*:behavior:child:)`
sees raw pointer events (scroll wheels arrive as `PointerScrollEvent` on
`onPointerSignal`), and `MouseRegion(onEnter:onHover:onExit:cursor:opaque:child:)`
tracks hover. `AbsorbPointer` and `IgnorePointer` do what they say.

`MouseRegion`'s `cursor:` is a stub: only `SystemMouseCursors.basic`
exists and the shape does not change. Under the Starling shell the cursor
image is the shell's business.

### Keyboard

Keys arrive through focus. A widget that wants them owns a `FocusNode`,
asks for focus, and reads `KeyData`:

```swift
private let focus = FocusNode(debugLabel: "Editor")

override func initState() {
    super.initState()
    focus.onKeyData = { [weak self] key in
        guard let self, key.type == .down || key.type == .repeat else { return false }
        if let ch = key.character, !ch.isEmpty { self.insert(ch); return true }
        switch key.logical {
        case 0xFF08, 0x1_0000_0008: self.backspace(); return true   // keysym, Flutter id
        default: return false
        }
    }
    focus.requestFocus()
}
override func dispose() { focus.dispose(); super.dispose() }
```

`KeyData` has `type` (`.down`/`.up`/`.repeat`), `physical`, `logical`,
`character`, `synthesized`, `timeStamp`, `deviceType`. **`logical` holds
two different things depending on the host**: X11 keysyms under the
Starling shell and the DRM embedder, Flutter logical key ids (values above
2³²) under the engine's own GTK, Cocoa, Win32 and UIKit embedders. The
ranges cannot collide, so one `switch` with both constants handles every
host — `FluentTextBox` and `TerminalInput` each carry the table. Printable
keys are unaffected either way: use `character`.

`FocusNode` also has `onFocusChange`, `hasFocus`, `unfocus()`.
`FocusManager` and `FocusScopeNode` exist as the traversal skeleton; there
is no `Focus` widget, no `Shortcuts`/`Actions`, and no tab traversal.

### Text editing

`MacosTextField(controller:placeholder:prefix:suffix:enabled:maxLines:minLines:onChanged:onSubmitted:style:padding:decoration:showFocusRing:obscureText:obscuringCharacter:autofocus:onFocusChanged:)`
is the editable field; `MacosSearchField` is its search-shaped wrapper.
The Fluent equivalents are `FluentTextBox`, `PasswordBox`, `NumberBox`,
`AutoSuggestBox`. All share `TextEditingController` — `text`, `selection`,
`value`, `clear()`, `hasText`, and `addListener` since it is a
`ChangeNotifier` — and the editing core (`insertText`, `deleteBackward`,
caret moves) lives on the controller too.

### Clipboard and the soft keyboard

`Clipboard.setData(ClipboardData(text:))` and `await Clipboard.getData(Clipboard.kTextPlain)`
(or the completion form). Where the text goes depends on the host: GTK's
clipboard under `FlutterGTK`, the shell's Wayland clipboard when spawned
by the shell, process-local otherwise. `SoftKeyboard.show()/hide()/isVisible`
drive an on-screen keyboard where a host installs one (iOS).

---

## 8. State beyond setState

### Listenables

`ChangeNotifier` (`addListener`, `removeListener`, `notifyListeners`) and
`ValueNotifier<T>` are ported. There is no `ValueListenableBuilder`; the
widget that rebuilds from any `Listenable` is `AnimatedBuilder`:

```swift
AnimatedBuilder(animation: model) { context, _ in
    Text("\(model.value)")
}
```

`ChangeNotifier.removeListener` is documented as best-effort in this port;
prefer designs where the listener's lifetime is the widget's.

### Inherited widgets

Subclass `InheritedWidget`, override `updateShouldNotify(_:)`, and give it
a static `of`:

```swift
class Settings: InheritedWidget {
    let compact: Bool
    init(compact: Bool, child: Widget) { self.compact = compact; super.init(child: child) }
    override func updateShouldNotify(_ old: InheritedWidget) -> Bool {
        (old as! Settings).compact != compact
    }
    static func of(_ context: any BuildContext) -> Settings {
        context.dependOnInheritedWidgetOfExactType(Settings.self)!
    }
}
```

`InheritedNotifier<T: Listenable>` rebuilds dependents when its notifier
fires; `InheritedModel` supports aspect-keyed dependencies;
`InheritedTheme` is the base for theme widgets.

### The BLoC pattern

The house pattern for app state, used by the calendar library and by every
desktop app: one value-type `State`, one `Event` enum, and an
`@Observable` bloc whose `add(_:)` is the only way the UI mutates
anything. Widgets read `bloc.state` and rebuild through
`withObservationTracking`.

```swift
import Observation

struct TodoState { var items: [Todo] = []; var filter = Filter.all }

@Observable
final class TodoBloc {
    private(set) var state = TodoState()

    enum Event { case add(String), toggle(Todo.ID), setFilter(Filter) }

    func add(_ event: Event) {
        switch event {
        case .add(let title):   state.items.append(Todo(title: title))
        case .toggle(let id):   state.items[id: id]?.done.toggle()
        case .setFilter(let f): state.filter = f
        }
    }
}

/// A State that re-renders on any bloc mutation it read during build.
class ObservingState: State<StatefulWidget> {
    func buildTracked(_ context: any BuildContext) -> Widget { fatalError("override") }
    override func build(_ context: any BuildContext) -> Widget {
        withObservationTracking {
            buildTracked(context)
        } onChange: { [weak self] in
            guard let self, self.mounted else { return }
            self.setState {}
        }
    }
}

class _TodoListState: ObservingState {
    let bloc: TodoBloc
    init(bloc: TodoBloc) { self.bloc = bloc }
    override func buildTracked(_ context: any BuildContext) -> Widget {
        ListView(children: bloc.state.items.map { TodoRow($0) { bloc.add(.toggle($0.id)) } })
    }
}
```

Observation tracks whatever `buildTracked` *read*, so a widget that only
looks at `state.filter` does not rebuild when an item toggles. Live UI
objects that are not values — a `ScrollController`, a `TextEditingController`
— sit on the bloc as `@ObservationIgnored` properties, outside `state`.

### Async work

There is no `FutureBuilder` or `StreamBuilder` (the `AsyncSnapshot` and
`ConnectionState` types exist for when they land). Do the await in a
`Task`, and touch state on the framework's thread when it completes —
usually through the bloc:

```swift
Task {
    let items = try await service.fetch()
    await MainActor.run { bloc.add(.loaded(items)) }
}
```

Under every SDK host the framework runs on the main thread — the GTK,
Cocoa and Win32 loops and the DMA-BUF child host all drive it from there —
so `MainActor.run` / `DispatchQueue.main.async` is the correct hop. The
Starling **shell** is the one exception (its tree runs on the engine's
platform thread; its own CLAUDE.md covers `onPlatformThread`).

### Timers

`Foundation.Timer` never fires under the DRM embedder. The portable
ticker is `startPeriodicTimer(seconds:_:)`, which returns a token to keep
(and to hand to `stopPeriodicTimer(_:)` when the surface goes off screen —
a tick that calls `setState` on a parked tree is a full build nobody
sees). For one-shots, `DispatchQueue.main.asyncAfter` with a generation
token to cancel.

---

## 9. Animation

### Explicit

An `AnimationController` needs a `TickerProvider`; a `State` conforms by
implementing one method:

```swift
class _PulseState: State<StatefulWidget>, TickerProvider {
    private var controller: AnimationController!

    func createTicker(_ onTick: @escaping (Duration) -> Void) -> Ticker { Ticker(onTick) }

    override func initState() {
        super.initState()
        controller = AnimationController(duration: .seconds(1), vsync: self)
        controller.addListener { [weak self] in self?.setState {} }
        controller.repeat(reverse: true)
    }

    override func dispose() { controller.dispose(); super.dispose() }

    override func build(_ context: any BuildContext) -> Widget {
        let scale = controller.drive(Tween(begin: 0.9, end: 1.1)).value
        return Transform(scale: scale, child: dot)
    }
}
```

`Duration` is Swift's own (`.seconds`, `.milliseconds`).
`AnimationController(value:duration:reverseDuration:lowerBound:upperBound:animationBehavior:vsync:)`
— `forward(from:)`, `reverse(from:)`, `repeat(min:max:reverse:period:)`,
`animateTo(_:duration:curve:)`, `animateBack`, `stop()`, `reset()`,
`dispose()`; `value`, `status`, `isCompleted`, `isDismissed`;
`addListener`, `addStatusListener`. Rather than calling `setState` from
the listener, hand the animation to `AnimatedBuilder(animation:builder:child:)`
or one of the transitions below and let it rebuild only that subtree.

Shaping: `Tween(begin:end:)` (plus `ColorTween`, `SizeTween`, `RectTween`,
`IntTween`, `StepTween`, `BoxConstraintsTween`, `DecorationTween`,
`EdgeInsetsGeometryTween`), `CurveTween(curve:)`, `TweenSequence`;
`CurvedAnimation(parent:curve:reverseCurve:)`, `ReverseAnimation`,
`ProxyAnimation`; and `animation.drive(tween)`. `Curves` has the full
set: `linear`, `ease`, `easeIn`/`Out`/`InOut` in every flavour
(`Sine`, `Quad`, `Cubic`, `Quart`, `Quint`, `Expo`, `Circ`, `Back`),
`fastOutSlowIn`, `decelerate`, `bounceIn`/`Out`/`InOut`,
`elasticIn`/`Out`/`InOut`, `slowMiddle`, `easeInOutCubicEmphasized`.
The physics simulations (`SpringSimulation`, `FrictionSimulation`,
`GravitySimulation`, `ClampedSimulation`) drive `animateWith`.

Transitions that take an `Animation`: `FadeTransition(opacity:)`,
`SlideTransition(position:)`, `ScaleTransition(scale:)`,
`RotationTransition(turns:)`, `SizeTransition(axis:sizeFactor:)`,
`AlignTransition(alignment:)`, `DecoratedBoxTransition(decoration:)`.

### Implicit

Give a target and a `duration:`, and the widget animates itself there:
`AnimatedContainer(alignment:padding:color:decoration:width:height:constraints:margin:curve:duration:onEnd:child:)`,
`AnimatedOpacity(opacity:duration:)`, `AnimatedScale(scale:duration:)`,
`AnimatedRotation(turns:duration:)`, `AnimatedSlide(offset:duration:)`,
and `AnimatedSwitcher(child:duration:reverseDuration:switchInCurve:switchOutCurve:)`
which cross-fades when the child's type or key changes.
`ImplicitlyAnimatedWidget` is the base if you need one of your own.

---

## 10. Navigation, dialogs and overlays

### Routes

`MacosApp` installs a `Navigator` (with its own `Overlay`) around `home:`,
so `showDialog` and pushes work anywhere below it. Outside `MacosApp`,
put `Navigator(home:onGenerateRoute:)` in yourself.

```swift
Navigator.of(context).push(DetailRoute(item: item))
Navigator.pop(context)                     // static forms exist for both
```

`NavigatorState`: `push(_:)`, `pop(_:)`, `popUntil(_:)`, `maybePop`,
`canPop`, `overlay`. A page route is a `ModalRoute` subclass:

```swift
class DetailRoute: ModalRoute {
    let item: Item
    init(item: Item) { self.item = item; super.init() }
    override var barrierColor: Color? { nil }          // no dimming
    override func buildContent(_ context: any BuildContext) -> Widget { DetailPage(item) }
}
```

`ExampleHost.MaterialPageRoute(builder:)` is exactly that, for the
samples. `barrierDismissible` and `barrierLabel` are the other hooks.
There are no page transitions on `ModalRoute` itself; Fluent ships
`EntrancePageTransition`, `DrillInPageTransition` and
`HorizontalSlidePageTransition` as widgets to wrap content in.

### Dialogs

```swift
showDialog(context: context, barrierDismissible: true) { ctx in
    MacosAlertDialog(
        appIcon: MacosIcon(icon: CupertinoIcons.trash, size: 40),
        title: Text("Delete “\(name)”?"),
        message: Text("This cannot be undone."),
        primaryButton: PushButton(child: Text("Delete"), onPressed: {
            Navigator.pop(ctx); delete()
        }),
        secondaryButton: PushButton(child: Text("Cancel"), secondary: true,
                                    onPressed: { Navigator.pop(ctx) })
    )
}
```

`showDialog(context:barrierDismissible:barrierColor:barrierLabel:builder:)`
pushes a `DialogRoute`; close it with `Navigator.pop` on the **dialog's**
context. `MacosSheet(child:)` is the sheet-shaped surface; Fluent's is
`ContentDialog` via `showContentDialog`. `ModalBarrier` is the dimming
layer on its own. Files: `MacosFilePanel(options:onComplete:)` /
`MacosFilePanelOverlay(options:panelWidth:panelHeight:onComplete:)` with
`MacosFilePanelOptions` (`mode: .open/.save/.directory`, `title`,
`allowsMultiple`, `allowedExtensions`, `initialDirectory`,
`suggestedName`, `confirmLabel`, `appearanceDark`), completing with the
chosen paths.

### Overlays and menus

`Overlay.of(context).insert(OverlayEntry(builder:opaque:maintainState:))`
puts a widget above everything in the navigator; `entry.remove()` and
`entry.markNeedsBuild()` manage it. Popups that must track a widget use
`CompositedTransformTarget`/`Follower` with a `LayerLink`.

`MacosMenu(items:brightness:accentColor:backgroundColor:minWidth:)` is a
widget, not a popup function — you place it. The desktop apps do it with
a `Stack`: the content, a full-window `Listener` barrier that clears the
menu on any click, then the menu `Positioned` at the tap:

```swift
var layers: [Widget] = [content]
if let at = menuAt {
    layers.append(Positioned(fill: (), child: Listener(
        onPointerDown: { _ in setState { menuAt = nil } },
        behavior: .opaque,
        child: SizedBox(expand: ()))))
    layers.append(Positioned(left: at.dx, top: at.dy,
        child: SizedBox(width: 200, child: MacosMenu(items: [
            MacosMenuItem(text: "Rename…", onPressed: rename),
            MacosMenuSeparator(),
            MacosMenuItem(text: "Delete", onPressed: delete, isDestructive: true),
        ]))))
}
return Stack(children: layers)
```

`MacosMenuItem(text:leading:trailing:onPressed:isDestructive:isSelected:)`;
subclass `MacosMenuEntry` for a custom row. Fluent's menus are
`MenuFlyout` with `MenuFlyoutItem`, `MenuFlyoutSubItem`,
`ToggleMenuFlyoutItem`, `RadioMenuFlyoutItem`, shown through a
`FlyoutController` / `FlyoutTarget`.

---

## 11. The macOS control set (MacosUI)

The default look of the Starling desktop and the set every desktop app is
written in. It is a port of the `macos_ui` package.

### The app shell and theme

`MacosApp(theme:darkTheme:themeMode: .system, home:title:)` installs, in
order: `Directionality`, a `FluentTheme` (so a Fluent control resolves its
theme if one slips in), `MacosTheme`, `DefaultTextStyle` from the
typography, and a `Navigator` with its `Overlay`.

`MacosThemeData(brightness:primaryColor:canvasColor:typography:dividerColor:pushButtonTheme:iconButtonTheme:iconTheme:accentColor:isMainWindow:)`
— or `.light(accentColor:)` / `.dark(accentColor:)`. Read it with
`MacosTheme.of(context)` (`maybeOf` outside one). `typography` has the
Apple text styles: `largeTitle`, `title1`–`title3`, `headline`,
`subheadline`, `body`, `callout`, `footnote`, `caption1`, `caption2`.
`MacosAccentColor` lists the system accents; `ControlSize` is
`.large/.regular/.small/.mini`. `AnimatedMacosTheme` cross-fades a theme
change; `MacosTheme(data:child:)` re-themes a subtree.

Under the Starling desktop, take the theme from the palette the shell
pushed rather than hardcoding one, so the app follows the shell's style
(macOS or Windows) and its light/dark switch:

```swift
MacosApp(theme: StarlingPalette.current(dark: isDark).macosTheme(), home: root)
// isDark from GpuDmaBufRenderer.lastPushedThemeIsDark, updated by
// GpuDmaBufRenderer.onThemeChanged — see the CalculatorApp root.
```

### Layout

| Control | Constructor | Notes |
|---|---|---|
| `MacosScaffold` | `(children:toolBar:backgroundColor:)` | The window body; also has the block form. |
| `MacosToolBar` | `(height: 52, title:, leading:, actions:, titleAlignment:, decoration:, padding:, dividerColor:)` | |
| `TitleBar` | `(height: 28, title:, padding:, decoration:)` | |
| `MacosSidebar` | `(minWidth: 200, maxWidth: 300, top:, bottom:, decoration:, builder: (context, scrollController) -> Widget)` | |
| `SidebarItem` | `(leading:label:trailing:selected:onTap:)` | |
| `ContentArea` | `(minWidth: 400, builder: (context, scrollController) -> Widget)` | |
| `MacosListTile` | `(leading:title:subtitle:trailing:onTap:padding:)` | |

### Buttons and toggles

| Control | Constructor |
|---|---|
| `PushButton` | `(child:controlSize:padding:color:disabledColor:onPressed:borderRadius:alignment:secondary:semanticLabel:)` — `onPressed: nil` disables |
| `MacosIconButton` | `(icon: Widget, onPressed:, backgroundColor:, disabledColor:, hoverColor:, shape: .circle, borderRadius:, padding:, boxConstraints:, semanticLabel:)` |
| `HelpButton` | `(onPressed:color:disabledColor:semanticLabel:)` |
| `MacosBackButton` | `(onPressed:semanticLabel:)` |
| `MacosCheckbox` | `(value: Bool?, onChanged:, size: 14, activeColor:, semanticLabel:)` — `nil` is mixed |
| `MacosRadioButton<T>` | `(value:groupValue:onChanged:size:semanticLabel:)` |
| `MacosSwitch` | `(value:onChanged:size: ControlSize, semanticLabel:)` |
| `MacosSegmentedControl` | `(labels: [String], selectedIndex:, onChanged:)` |

### Fields, indicators, labels

| Control | Constructor |
|---|---|
| `MacosTextField` | see §7 |
| `MacosSearchField` | `(controller:placeholder: "Search", onChanged:, onSubmitted:, enabled:)` |
| `MacosSlider` | `(value:onChanged:onChangeStart:onChangeEnd:min: 0, max: 1, divisions:, color:)` |
| `MacosProgressIndicator` | `(value: Double?, height: 4, color:, trackColor:)` — `nil` is indeterminate |
| `CapacityIndicator` | `(value:color:backgroundColor:)` |
| `MacosLabel` | `(text:style:)` |
| `MacosIcon` | `(icon: IconData, color:, size:)` |
| `MacosTooltip` | `(message:child:style:padding:)` |
| `MacosScrollbar` | see §6 |

### Menus and dialogs

`MacosMenu`, `MacosMenuItem`, `MacosMenuSeparator`, `MacosMenuEntry`;
`MacosAlertDialog`, `MacosSheet`, `MacosFilePanel`,
`MacosFilePanelOverlay` — all in §10.

If a control you need is missing or a stub, add it here (under
`Sources/Flutter/MacosUI/`) rather than reaching for the Fluent one that
autocompletes. `MacosMenu` and `MacosScrollbar` both arrived that way.

---

## 12. The Fluent control set (FluentUI)

A port of `fluent_ui`: the Windows look, used by the Starling desktop's
Windows style. It is the larger set. `FluentApp` is its root;
`FluentTheme(data:child:)` / `FluentThemeData.light()` / `.dark()` its
theme, read with `FluentTheme.of(context)`; `AnimatedFluentTheme` animates
a change; `FluentTypography` and the `AccentColor` resources back it.

| Group | Controls |
|---|---|
| Buttons | `Button`, `FilledButton`, `HyperlinkButton`, `IconButton`, `ToggleButton`, `SplitButton`, `DropDownButton`, `HoverButton` (base), `FocusBorder`, `ButtonStyle`/`ButtonTheme` |
| Inputs | `Checkbox`, `RadioButton<T>`, `ToggleSwitch`, `Slider`, `RatingBar` |
| Form | `FluentTextBox`, `PasswordBox`, `NumberBox`, `AutoSuggestBox`, `ComboBox<T>`, `InfoLabel` |
| Navigation | `NavigationView` with `NavigationPane`, `PaneItem`, `PaneItemHeader`, `PaneItemSeparator`, `PaneItemExpander`, `PaneItemAction`; `TabView`/`Tab`; `TreeView`/`TreeViewItem`; `BreadcrumbBar<T>` |
| Surfaces | `ScaffoldPage`, `PageHeader`, `Card`, `Expander`, `InfoBar`, `ListTile`, `CommandBar` with `CommandBarButton`/`CommandBarSeparator`, `Acrylic`, `ProgressBar`, `ProgressRing` |
| Flyouts | `Flyout` (`FlyoutController`, `FlyoutTarget`, `FlyoutContent`, `FlyoutListTile`), `MenuFlyout` family, `MenuBar_`/`MenuBarItem`, `ContentDialog` (+ `showContentDialog`), `TeachingTip`, `Tooltip` |
| Pickers | `DatePicker`, `TimePicker`, `CalendarView`, `CalendarDatePicker`, `ColorPicker` |
| Utilities | `Divider`, `InfoBadge`, `FluentScrollbar`, `DecoratedBox`, `CustomSingleChildLayout` (both generic, they just live in this directory) |
| Transitions | `EntrancePageTransition`, `DrillInPageTransition`, `HorizontalSlidePageTransition` |

Each control has a `…Theme`/`…ThemeData` pair for per-subtree styling.

**Writing a Starling desktop app? Do not use these.** Apps under the
desktop are macOS-only by rule: `FluentApp`'s scaffold traps on mount as a
DMA-BUF child, and the desktop's style switching is the shell's job, with
`StarlingPalette` carrying the Fluent colours into `MacosApp`. Because
`MacosApp` installs a `FluentTheme`, a stray Fluent widget renders
instead of failing — the check is by directory, not by compiler. For a
standalone SDK app the choice is yours.

---

## 13. The terminal widget

A complete terminal in two objects, from `Sources/Flutter/Terminal/`:

```swift
let session = TerminalSession(cols: 80, rows: 24)
session.startShell()                       // or startCommand("ssh host")
runExampleApp(title: "Terminal", width: 940, height: 620) {
    TerminalView(session: session)
}
```

`TerminalSession` owns the emulator (the desktop Terminal's C core) and
optionally a PTY: `startShell()`, `startCommand(_:)`, `restart()`,
`resizeProcess(cols:rows:)`, `terminate()`; `write(_:)` sends keystrokes,
`feed(_:)` injects output. Headless use — an SSH channel, a replay, a
remote agent — skips `startShell` and drives `feed`/`onOutput` yourself.
Callbacks: `onOutput`, `onExit`, `onResize`, `onActivity`, and an
`autoAnswer` hook for prompts.

`TerminalView(session:theme: .starlingDark, font: TerminalFont(), padding: 8, size:, autofocus: true, restartOnEnter: true, fitColumns:, onFitColumnsChanged:, pinchToZoom:, keyFilter:)`
renders the grid and routes keys, mouse (SGR reporting, alternate
scroll), clipboard, scrollback and selection. `size:` tells the grid its
box for a pane that is not the whole window — the child process gets its
SIGWINCH. `TerminalFont(family: TerminalFontLoader.family, size: 13, fallback:)`;
Roboto Mono and DejaVu Sans Mono ship, and the system CJK and emoji faces
are appended as fallbacks where installed.

`TerminalTiling` (Examples) is the widget in a workspace — split tree,
draggable seams, floating mode with a cover flow — and reads as the
reference for composing several.

---

## 14. Platform services

All in `Sources/Flutter/Platform/` and `Starling/`, all inert when the
host does not provide them.

| API | What it does |
|---|---|
| `Clipboard.setData(_:)`, `Clipboard.getData(_:)` (async or completion), `Clipboard.provider` | System clipboard through whichever `ClipboardProvider` the host installed: GTK, the shell's Wayland clipboard, or process-local. |
| `SoftKeyboard.show()`/`hide()`/`isVisible`/`isAvailable` | On-screen keyboard where a host installs a handler. |
| `realUserHomeDirectory()` | `$HOME` of the real user, even when the process runs as root under the dev shell. |
| `startPeriodicTimer(seconds:_:)`, `stopPeriodicTimer(_:)` | A repeating tick on the UI thread, host-appropriate (§8). |
| `runStarlingApp`, `GTKWindowedHost.install()` | §1. |
| `GpuDmaBufRenderer` | The DMA-BUF child host. `current`, `lastPushedThemeIsDark`, `onThemeChanged`; `registerExternalTexture()` / `updateExternalTexture(_:fd:width:height:…)` / `updateExternalTextureNV12` / `updateExternalTexturePixels` / `unregisterExternalTexture` for frames rendered elsewhere, shown with `TextureWidget`; `DisplayInfo` for the outputs; `drmCandidates()`. Also carries the app-to-shell messages (`sendThemeChange`, `sendDpiChange`, `sendLayoutChange`, …) the Settings app uses. |
| `StarlingPalette` | The active desktop style's colours: `.current(dark:)`, `.macos(dark:)`, `.fluent(dark:)`, fields `textPrimary`…`accentInk`, `fontFamily`, and `macosTheme()` to feed `MacosApp`. `StarlingStyleId.current` says which style the shell is in. `accentInk` is the ink colour *on* the accent — not white; Fluent's dark accent takes black glyphs. |
| `AgentSemanticsEndpoint.startIfConfigured()` | Exposes the semantics tree over the socket named by `STARLING_AGENT_ENDPOINT`, for the desktop's computer-use agent. |

The `Services` and `Semantics` directories carry the asset bundle
(`AssetBundle`, `AssetManifest`) and the semantics tree
(`SemanticsNode`, `SemanticsConfiguration`, `SemanticsOwner`, …) that
the render layer maintains; there is no `Semantics` widget to annotate
with yet, but controls set `semanticLabel:` where they take one.

---

## 15. What is not here yet

Named so you do not go looking. Each has its Dart equivalent's behaviour
reachable by composition or by the noted alternative.

| Missing | Use instead |
|---|---|
| `Container` | `Padding` / `DecoratedBox` / `SizedBox` / `ConstrainedBox` composed |
| `Spacer` | `Expanded(child: SizedBox(shrink: ()))` |
| `Image` widget, `Image.network/file/memory` | decode to a `ui.Image`, draw in `CustomPaint` (§4); `TextureWidget` for streams |
| `Icon` (framework-level) | `MacosIcon`; `ExampleHost.Icon` in samples |
| `Table` widget | `RenderTable` exists; wrap it, or `Column` of `Row`s |
| `CustomScrollView`, `PageView`, `ListWheelScrollView`, `ReorderableListView`, `AnimatedList` | `ListView`/`GridView`; `Scrollable` + the slivers by hand (`RenderListWheelViewport` is ported) |
| `LayoutBuilder` | `MeasureSize`, or a `RenderObjectWidget` of your own |
| `FutureBuilder`, `StreamBuilder`, `ValueListenableBuilder` | `Task` + bloc (§8); `AnimatedBuilder` for any `Listenable` |
| `Focus`, `FocusScope`, `Shortcuts`, `Actions`, `KeyboardListener` | `FocusNode.onKeyData` (§7) |
| `Draggable`, `DragTarget`, `Dismissible`, `InteractiveViewer` | `GestureDetector` drags + `Positioned`/`Transform`; `DragBoundary` is ported |
| `Hero`, page transitions on `ModalRoute` | Fluent's transition widgets, or a `FadeTransition` in `buildContent` |
| `SafeArea`, `MediaQuery` padding | the UIKit host insets the whole view; nothing needed on desktop |
| `Semantics`, `MergeSemantics`, `ExcludeSemantics` | `semanticLabel:` on controls |
| `Tooltip` (generic), `Card`, `Divider` | `MacosTooltip`; Fluent's `Card`/`Divider` are generic enough to use anywhere |
| Mouse cursor shapes | stub — `basic` only |
| `System.requestAppExit` handling | the host closes the window |

---

## 16. Testing

```bash
tools/run-tests.sh        # not `swift test` — see the README for why
```

Tests are XCTest under `Tests/FlutterTests`, one directory per subsystem,
and they test the framework the way its Dart originals do: construct
widgets and render objects, lay them out with explicit constraints, and
assert on geometry, tree shape and painted commands — there is no
`pumpWidget`/`WidgetTester` harness and no screenshot comparison.
`Tests/FlutterTests/Widgets/ResultBuildersTests.swift` is a compact
example (it asserts the two spellings build the same tree). The bridge's
own tests (`FlutterSwiftBridgeTests`) cover geometry, colour and
compositing.

For an app, put its logic in the bloc and test the bloc: it is a plain
`@Observable` class with value-type state, so `bloc.add(.x)` then
`XCTAssertEqual(bloc.state…)` needs no engine at all. Driving a live
desktop is the Starling repo's `build/shell-drive.py` and `test/run.sh
--functional`.

---

## 17. Traps

The framework-level ones, collected from the desktop's CLAUDE.md where
each was paid for.

- **A `Positioned` with `right:` and no width lays out correctly and
  hit-tests as nothing.** The child sizes itself and paints where you
  expect, but has no box for the pointer. Span the full width
  (`left: 0, right: 0`) and align inside it.
- **`ColoredBox` hit-tests opaque even at alpha 0.** For an invisible
  barrier use a bare `SizedBox(expand: ())` under a `Listener(behavior:
  .translucent)` — or `.opaque` when it should swallow the click.
- **Registering `onDoubleTap` kills both tap and double-tap on the DRM
  embedder** (`Foundation.Timer` never fires there). Detect double-clicks
  by timestamp inside `onTap`.
- **A tree with no `MacosApp`/`FluentApp` above it must start with
  `Directionality`.**
- **Lazy list children do not rebuild on an ancestor rebuild.** A theme
  or state change that must reach every row needs a poke (the bloc's
  `.refresh`, or a changed key).
- **Changing a lazy list's cell shape needs a `key` on the `ListView`.**
  A child whose root widget *type* changed remounts through a path the
  sliver element does not implement, so the fresh render objects go
  nowhere and the old cells keep painting inside the new extents. Key the
  list by mode.
- **Element remount is the dominant update path** (no
  `updateRenderObject`): if fresh content never composites, suspect paint
  marking.
- **`print()` is block-buffered through pipes.** Debug with
  `write(2, …)` or `setbuf(stdout, nil)` (the sample host does the latter).
- **`KeyData.logical` is a keysym on one host and a Flutter id on the
  others.** Handle both, or special keys silently stop working on
  whichever host you did not test (§7).
- **Adding a parameter to a ported widget's initializer means adding it
  to its builder overload too**, or the block spelling cannot express it
  and nothing warns.
- **A plain `swift build` can hand you a stale framework.** Each package
  compiles its own copy of `Flutter`, and incremental state does not
  always notice `sdk/` moved underneath it; editing an *existing* file
  fails silently with a binary built from the old code. When a change
  appears to have no effect, clear the scratch's `build.db` and
  `Flutter.build` and build twice. The desktop's CLAUDE.md has the exact
  recipe.
- **`Bundle.module` bakes in the build path.** An app that reads its own
  resources that way runs only on the machine that built it; resolve
  beside the executable instead, as `ensureEngineData` does.
