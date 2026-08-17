# Starling SDK

The Flutter framework, ported to Swift. No Dart VM: widgets, rendering, painting,
gestures and semantics are Swift, driven directly by the Flutter engine's C core
through a C++ bridge. (The SwiftPM package keeps the framework's original name,
`FlutterSwift`, which is why that name still appears in build output and in
`package:` references from path consumers.)

This SDK was extracted from the [Starling desktop][starling], which is its
largest consumer but not its only intended one. It carries the framework and the
thin platform bindings needed to host an engine — nothing desktop-specific.

[starling]: https://github.com/starling-build/starling

## What is here

| Target | |
|---|---|
| `Flutter` | the framework port — Widgets, Rendering, Painting, Gestures, Animation, Semantics, plus the FluentUI and MacosUI widget sets |
| `FlutterSwiftBridge` | Swift side of the C++ bridge to the engine's `dart:ui` implementation |
| `FlutterSwiftBridgeCxx` | the vendored bridge headers it compiles against |
| `SwiftRuntime` | the delegate the engine calls instead of a Dart isolate |
| `CupertinoIcons` | 1,322 SF-Symbols-style icons and their font |
| `FlutterEmbedderBridge` | clang module over the engine's `embedder.h` |
| `FlutterDRMBridge` | clang module over the DRM/KMS embedder (`fl_drm_view.h`) |
| `DmaBufBridge` | GBM + `SCM_RIGHTS` + EGL dma-buf import helpers |
| `FlutterGTK` | desktop-session host: the engine's GTK embedder (`FlView` in a `GtkWindow`) running in Swift mode, with `FlutterGTKBridge` (C glue + vendored `flutter_linux` headers) and `CGtk3` (system GTK 3 via pkg-config) underneath |
| `FlutterCocoa` | desktop host on macOS: the engine's Cocoa embedder (a `FlutterViewController` in an `NSWindow`) running in Swift mode, with `FlutterCocoaBridge` (ObjC glue + vendored `FlutterMacOS` headers) underneath |
| `FlutterWin32` | desktop host on Windows: the engine's Win32 embedder (`flutter_windows.dll`) running in Swift mode, with `FlutterWin32Bridge` (C glue + vendored `flutter_windows` headers) underneath |

`FlutterShared` is a dynamic product bundling the whole stack into one
`libFlutterShared.so`, so a fleet of apps ships one copy rather than a static
duplicate each.

`Sources/` carries only these SDK targets. Everything app-related lives under
`Examples/`: `FlutterDemoApp` (see *The demo app* below), the ported samples
`CounterApp`, `StartupNamerApp`, `TodosApp` and `CalendarApp`, their shared
`ExampleHost` plumbing, and `CalendarKit` — a port of the [kalender] calendar
package (day/week/month views driven by a single calendar BLoC, plus the
overlap and multi-day layout delegates) that backs `CalendarApp` and remains
a library product.
They are targets of this same package, so `swift run -c release <AppName>`
works from the repo root unchanged.

[kalender]: https://github.com/werner-scholtz/kalender

## Building

The engine is a **link-time dependency only** — its headers are vendored under
each target's `include/engine/`, so nothing here needs an engine checkout to
compile. Linking does. `Package.swift` looks for engine binaries in this order:

1. `$FLUTTER_SWIFT_ENGINE_OUT` — explicit, always wins
2. `engine/lib/` inside this package — a distribution bundle (see below)
3. a sibling engine checkout — an `engine` symlink beside this package, or a
   sibling clone of [starling-engine][engine]

[engine]: https://github.com/starling-build/starling-engine

```bash
swift build -c release
tools/run-tests.sh          # not `swift test` — see below
```

`tools/run-tests.sh` exists because a plain `swift test` cannot work on Ubuntu
26.04: swift-testing ships as a textual `.swiftinterface`, which gets recompiled
in the importing target's C++-interop context and hits the `<cmath>` clash
described below. The script prebuilds those modules outside interop and passes
the compat flags to every frontend invocation. On any other platform it is a
passthrough.

### Ubuntu 26.04

The 6.2.4 toolchain is an ubuntu24.04 build, and 26.04 pairs glibc 2.43 with
libstdc++ 15. Under C++ interop that makes Foundation's `_CStdlib.h` pull
`<cmath>` textually *and* from the prebuilt `std` module, so every target dies
with `cmath: redefinition of 'acos'`. `Package.swift` works around it with
`-D_GLIBCXX_MATH_H` plus a force-included glibc `math.h`, applied only where the
bad pairing is detected (libstdc++ 15 or newer). Override the probe with
`FLUTTER_SWIFT_GLIBC_MATH_COMPAT=0` or `=1`.

These are the package's only remaining unsafe flags outside `-L`/`-rpath`, and
they disappear on their own once swift.org ships a native 26.04 toolchain.

**Consumers on 26.04 need the same two flags on their own C++-interop targets.**
SwiftPM does not propagate `swiftSettings` from a dependency, so this package
applying them internally does nothing for a dependent: your target pulls
Foundation's C shim in *your* compilation context and hits the clash there. This
is easy to miss, because a machine with a locally patched
`/usr/include/c++/15/math.h` never sees it — that artifact produced one wrong
conclusion here already.

### macOS

The engine is `FlutterMacOS.framework` plus a separate `libswift_bridge.dylib`
— unlike Linux and Windows, where the bridge is merged into the engine
library, because a framework is a Mach-O of its own with nothing to merge it
into. Build both from an engine checkout with:

```bash
cd engine/src
flutter/tools/gn --runtime-mode=debug --no-lto --no-backtrace --no-rbe --mac-cpu arm64
ninja -C out/host_debug_arm64 \
    flutter/shell/platform/darwin/macos:flutter_framework \
    flutter/lib/ui/swift:swift_bridge
```

`--mac-cpu arm64` is not optional on Apple Silicon: it defaults to `x64`.
It also decides the output directory, because `flutter/tools/gn` appends the
CPU only when it is not the default — so an Apple Silicon build lands in
`out/host_debug_arm64` and an Intel one in `out/host_debug`. `Package.swift`
probes for both.

Two macOS-only notes on the tooling. `tools/sync-vendored-headers.sh` needs
bash, and the `/usr/bin/env bash` on a Mac is 3.2 — it avoids bash 4 builtins
for that reason. It also will not overwrite the vendored `<swift/bridging>`,
which is the only header here that describes the *toolchain* rather than the
engine's ABI: Xcode's bundled Swift is typically older than the swiftly
toolchain Linux builds with, and letting a Mac downgrade that copy made
`--check` fail on every Mac. `FLUTTER_SWIFT_SYNC_TOOLCHAIN=1` forces it when
deliberately moving to a newer toolchain.

## The demo app

```bash
swift run -c release FlutterDemo
```

opens the framework's demo — rotating boxes plus a frame-time graph — in a
window on an ordinary desktop session (GNOME Wayland, KDE, X11). The host is
`FlutterGTK`: the engine's **own GTK embedder** (`FlView` inside a
`GtkWindow`), started in Swift mode via `fl_engine_set_swift_runtime`, so
window management, pointer/keyboard/touch input, IME and accessibility come
from the exact code path a real Flutter Linux app uses — the Swift framework
replaces only the Dart isolate. Clicking drops a marker square at the pointer,
a one-glance check that input reaches the framework's gesture layer; the tap
is also logged to stdout for scripted verification.

Requirements beyond the engine: `libgtk-3-dev` to build (found via
pkg-config), GTK 3 at runtime, and `libflutter_linux_gtk.so` next to
`libflutter_engine.so` — this fork builds it with the embedder linked
*dynamically* against `libflutter_engine.so` (upstream compiles a private
copy in, which would put two engines in a Swift app's process; see
`shell/platform/linux/BUILD.gn` in the engine).

Engine data resolves the standard Flutter bundle way:
`<executable dir>/data/{icudtl.dat,flutter_assets}`. Running from a build
tree, the demo links that up on first run from the sibling engine checkout
(override with `$FLUTTER_SWIFT_ENGINE_OUT`). To run on a machine without a
toolchain, ship the binary with `data/`, both engine libraries and the Swift
runtime libraries, and set `LD_LIBRARY_PATH` (or link with a matching rpath).

Known gaps, both harmless to the demo: the framework port does not yet answer
`System.requestAppExit` (the host closes the window directly instead of
letting the framework veto), and its `flutter/keyevent` channel replies are
not the JSON the GTK keyboard handler expects, so focus changes log a
`Unable to retrieve framework response` warning.

## The terminal widget

```bash
swift run -c release TerminalDemo
```

opens a complete terminal — the user's shell on a PTY — built from the two
public pieces in `Sources/Flutter/Terminal/`:

```swift
let session = TerminalSession()   // owns the emulator and, optionally, a PTY
session.startShell()
runExampleApp(title: "Terminal", width: 940, height: 620) {
    TerminalView(session: session)
}
```

`TerminalView(session:theme:font:padding:autofocus:restartOnEnter:)` renders
the grid and routes keys, mouse (SGR reporting and xterm's alternateScroll),
clipboard, scrollback and selection; `TerminalSession` can also run headless
— skip `startShell()` and drive `feed(_:)`/`onOutput` yourself for an SSH
channel, a replay, or a remote agent's pty. The emulator underneath is the
desktop Terminal's own C core: wide characters and grapheme clusters done
properly (a clean sweep of ucs-detect's battery — wide, narrow, ZWJ
families, 118 languages of conjuncts — where ghostty's nightly scores 40
errors), measured at 0.49x of ghostty nightly's wall on the ten-workload
suite in `docs/perf/terminal-vs-ghostty-2026-08-11/` (desktop repo), and
pinned by 26 conformance checks in the desktop's fast test tier. Roboto Mono
and DejaVu Sans Mono ship in the framework; the system Noto CJK and Color
Emoji faces are picked up as fallbacks where installed.

```bash
swift run -c release TerminalTiling            # shells
swift run -c release TerminalTiling "top -d 1" # …or one command per pane
```

is the same widget in a workspace: **tiling or floating**, from a toolbar
toggle, over one split tree of terminals, each its own session. Tiled, they
have **draggable seams** — tiling that resizes freely, the boundary moving
under the pointer while the child processes are resized live behind it
(`TerminalView(size:)` tells each pane's grid its box, so the shell gets its
SIGWINCH). Splits are ratios rather than pixel counts, so resizing the
window redistributes every pane at once. Floating, the Windows button opens a cover flow — the panes as covers, the
chosen one square to the viewer and its neighbours turned away, each showing
what is on that terminal's screen right now. A new pane asks what to run — the `Host` entries from
`~/.ssh/config` and previously run commands, filtered as you type — so the
pane knows its command and ↻ *reconnects* rather than dropping you at a
local shell. Click a pane's title to name it. `TerminalSession.startCommand(_:)` runs one program in place of the
login shell, and `restart()` (what the view offers after a child exits)
repeats whichever it was.

## Consuming it

Two ways, by how the engine arrives.

### As a versioned dependency (static engine)

```swift
dependencies: [
    .package(url: "https://github.com/starling-build/starling-sdk.git", from: "0.1.0"),
],
targets: [
    .executableTarget(
        name: "App",
        dependencies: [
            .product(name: "Flutter", package: "starling-sdk"),
            .product(name: "FlutterSwiftBridge", package: "starling-sdk"),
            .product(name: "FlutterGTK", package: "starling-sdk"),  // desktop window host
        ],
        swiftSettings: [.interoperabilityMode(.Cxx)]
    ),
]
```

When no engine checkout or bundle is present (the consumer case), the manifest
switches to **static mode**: the engine — embedder core, Swift bridge, DRM
view and GTK embedder in one symbol-localized archive — arrives as a SwiftPM
`binaryTarget` (an SE-0482 staticLibrary artifactbundle, ~50 MB, built by
`tools/make-static-engine.sh`), and the manifest carries no unsafe flags. The
executable comes out self-contained: no `libflutter_engine.so` to ship. Build
with `--gc-sections` in your own target to drop the unused half of the archive.

The prerequisites are ordinary system libraries the engine expects
(`-dev` packages at build time): `libdrm libgbm libegl libgles libxkbcommon
libinput libudev` and, for `FlutterGTK`, `libgtk-3 libepoxy`. At run time it
needs `<executable dir>/data/{icudtl.dat,flutter_assets}` — copy them from
this repo's release assets or `Resources/`.

Caveats: Linux x86_64 only so far (the artifact is per-triple; more can be
added to the bundle), and **not Ubuntu 26.04 yet** — the glibc math compat
flags below are genuinely required there and have no safe expression, so
26.04 consumers use the bundle route until a native swift.org toolchain
lands. `FLUTTER_SWIFT_LINK=static|dynamic` overrides the mode choice.

### As a download-and-point SDK (dynamic engine)

`tools/make-bundle.sh` (Linux/macOS) and `tools/make-bundle.ps1` (Windows)
produce a self-contained tree carrying the framework and the engine binaries
together. Same layout on all three, so a consumer's manifest differs only in
which host product it imports — `FlutterGTK`, `FlutterCocoa` or
`FlutterWin32`. The Windows bundle carries each DLL beside its `.lib` import
library, because the link step needs the import library and the run needs the
DLL; it does **not** carry the Swift runtime DLLs, which belong to the
consumer's toolchain exactly as `libswiftCore` does on Linux.

    starling-sdk-linux-aarch64/
      Package.swift Sources/ Examples/ Tests/ tools/ LICENSE
      engine/lib/     libflutter_engine.so, libflutter_linux_gtk.so,
                      libflutter_linux_drm.so
      engine/share/   icudtl.dat, flutter_assets/

    starling-sdk-macos-arm64/
      Package.swift Sources/ Examples/ Tests/ tools/ LICENSE
      engine/lib/     FlutterMacOS.framework, libswift_bridge.dylib
      engine/share/   flutter_assets/

`engine/share/icudtl.dat` is missing from the macOS bundle on purpose. A mac
out directory has **two different** files by that name, and only one is
Flutter's: the framework build puts the trimmed ~780 KB build (from
`//flutter/third_party/icu/flutter`) inside
`FlutterMacOS.framework/Versions/A/Resources`, while the top-level
`icudtl.dat` beside the engine is full ICU (~10 MB, `third_party/icu/common`)
for the engine's own tests. Taking the top-level one the way the Linux branch
does would put 10 MB of the wrong flavour in `engine/share` for a consumer to
point at out of habit, so the framework's copy is the only one that ships —
which is also why the hosts look inside the framework first.

The bundle's generated README carries the per-platform deployment recipe,
which is not the same shape: on macOS both engine binaries have `@rpath`
install names and are copied beside the executable, with nothing to set in
the environment.

Unpack it and depend on it by path:

```swift
dependencies: [.package(path: "/opt/starling-sdk-linux-aarch64")],
targets: [
    .executableTarget(
        name: "App",
        dependencies: [
            .product(name: "Flutter", package: "starling-sdk-linux-aarch64"),
            // The dart:ui types — Offset, Size, Rect, Paint, Canvas. A separate
            // product; Flutter does not re-export them.
            .product(name: "FlutterSwiftBridge", package: "starling-sdk-linux-aarch64"),
        ],
        swiftSettings: [
            // Required — C++ interop is not inherited from the dependency.
            .interoperabilityMode(.Cxx),
            // Required on Ubuntu 26.04, harmless elsewhere; see below.
            .unsafeFlags(["-Xcc", "-D_GLIBCXX_MATH_H",
                          "-Xcc", "-include", "-Xcc", "/usr/include/math.h"]),
        ]
    ),
]
```

**This route is a path dependency, not `.package(url:from:)`.** Pointing at
the bundled engine needs `-L`/`-rpath`, which SwiftPM classes as unsafe and
rejects for version-resolved dependencies while permitting for path
dependencies. It exists alongside the static route because it is what in-tree
development and the Starling desktop use, it works on Ubuntu 26.04 today, and
it ships the engine as a shared library — a fleet of apps loads one copy.
This is a download-and-point SDK, the same shape as the Flutter SDK itself.

Two consequences: there is no `swift package update`, and the engine path is
baked into your binary's RUNPATH, so moving an unpacked bundle means rebuilding.
The original design notes live in the Starling repo at
`docs/plans/standalone-sdk.md`.

## Vendored headers

`tools/sync-vendored-headers.sh` copies the engine's public headers (36 of them)
and `<swift/bridging>` into the package. They describe the ABI of the
`libflutter_engine` being linked, so they and the engine binary must ship
together — `make-bundle.sh` refuses to build if `--check` reports drift.

```bash
tools/sync-vendored-headers.sh --check     # report drift
tools/sync-vendored-headers.sh             # re-sync
```

## Status

Linux is the primary platform and the one the Starling desktop ships on. macOS
and Windows both run: the framework, a windowed host, and the ported
`CounterApp` build and work on all three.

macOS is verified on Apple Silicon (macOS 26, Xcode 26's Swift 6.2.1) against a
locally built engine: the window opens, the widget tree builds off engine
frames, and clicking the floating action button increments the counter — so
compositing, pointer input and `setState` are all live. `swift build -c release`
builds every macOS product, and `tools/make-bundle.sh` produces a bundle that
builds `CounterApp` on its own. The whole of `Sources/Flutter` needed no
changes for the port.

What macOS has not been through: an Intel Mac, a `.app` bundle (the host is
built for a bare SwiftPM executable and points the engine at explicit asset
paths for that reason), text input and IME, accessibility, multi-window, and
anything beyond the smallest sample. There is no CI on any platform.

Two environment knobs read by `Sources/Flutter/Platform/` still carry Starling
names (`STARLING_AGENT_ENDPOINT`, `STARLING_APP_DRM_DEVICE`); both are inert
when unset.

## License

BSD-3-Clause, inherited from Flutter. See `LICENSE`.
