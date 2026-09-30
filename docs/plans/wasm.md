# Rendering the SDK in WebAssembly — exploration

Status, 2026-09-29: **architecture A is chosen** (the one Dart and Flutter
use) and **milestone 0 runs** — see "Where it stands". Branch `wasm` in both
repos (this one from `main` 97f3c72, the engine from `starling` 10710380e11).

The question: can an app written against `sdk/` run in a browser tab, and
what is the shortest honest path to a first frame.

## What was measured, not assumed

Probes live outside the tree; each is a 20-line SwiftPM package built with
the swift.org wasm SDK and run under `wasmkit`.

| Probe | 6.2.1 | 6.4.0 |
|---|---|---|
| Swift + Foundation → wasm32-wasip1 | builds, runs | builds |
| Swift importing a **C header** whose implementation is C++ using libc++ (`std::vector`, `std::string`), Foundation on | builds, runs, prints `42 4 true` | — |
| Swift importing **any C++ module** (`.interoperabilityMode(.Cxx)`), even one whose header includes no standard header | **fails** | **fails** |
| `swift build --target Flutter` on the real package | **fails**, same error, at `FlutterSwiftBridge` | — |

The failure is the toolchain's, in its own sysroot:

    cyclic dependency in module 'SwiftWASILibc':
        SwiftWASILibc -> std_inttypes_h -> SwiftWASILibc

wasi-libc's `netinet/in.h` includes `<inttypes.h>`, which under C++ resolves
to libc++'s wrapper, which includes the libc one again. It reproduces with no
code of ours involved, and is unfixed in the current release.

`MemoryLayout<Int>.size` is **4**. There is no wasm64 Swift target.

## The four constraints

1. **The engine boundary cannot be imported.** Swift reaches the engine
   through 29 C++ classes marked `SWIFT_SHARED_REFERENCE`
   (`Sources/FlutterSwiftBridgeCxx/include/engine/*.h`, roughly 290 methods).
   C++ interop does not compile for WASI, so on wasm the boundary has to be a
   **C ABI**, whichever architecture is chosen. The reverse direction
   (`SwiftRuntimeCallbacks`, 19 function pointers) is already plain C.
2. **WASI Swift cannot link Emscripten objects** — different libc, different
   libc++ ABI. Everything in the engine that already builds for wasm
   (`skia`, `display_list`, and skwasm on top of them) builds with
   Emscripten 3.1.70. A Swift `wasm32-unknown-emscripten` target exists only
   as an unmerged pitch with no installable SDK.
3. **The engine shell does not exist on wasm.** A frame today goes
   SceneBuilder → `flow` LayerTree → Animator → Rasterizer across platform,
   UI, raster and IO task runners, synchronised with futures and latches.
   `fml::MessageLoopImpl::Create()` returns null on wasm, `flow`, `shell` and
   `lib/ui/swift` have no wasm branch, and Impeller has no WebGL or WebGPU
   backend.
4. **The framework assumes a 64-bit `Int`.** `Color.init(_ value: Int)`
   (`FlutterSwiftBridge/Painting.swift:81`) takes 353 literals in `Sources`
   with the high bit set — every opaque colour — and each is a compile error
   at 32 bits. `UInt32(color.toARGB32())` then traps at runtime for the ones
   that are not literals.

## Three architectures

**A. Two modules.** Swift built for WASI; skwasm as its own Emscripten module,
unmodified; JavaScript instantiates both and hands skwasm's exports to Swift
as imports. This is exactly how Dart-on-wasm uses skwasm, so the renderer
side is proven: ~263 `extern "C"` exports (canvas 37, path 31, paragraph 23,
text style 23, filters 15, shaders 13, surface 13 …), Ganesh on WebGL2, and a
single-threaded mode chosen at load time (`Module.skwasmSingleThreaded`), so
no COOP/COEP headers are needed to start.
Cost: the two modules have separate memories, so buffers are copied into
skwasm's through its own allocator exports; and skwasm has no SceneBuilder —
upstream's layer tree for the web is Dart (`lib/web_ui/lib/src/engine`), so
ours becomes Swift.

**B. One module, WASI.** Compile Skia, DisplayList, txt, flow and the bridge
`.cc` files against the Swift SDK's WASI sysroot, put a C shim over the
bridge classes, link statically. Keeps `flow` and the bridge's behaviour
bit-identical to the desktop. Cost: a GN toolchain for WASI that does not
exist, Skia's WebGL interface is Emscripten's (so CPU raster first, or
hand-written GL imports), and the threading in constraint 3.

**C. One module, Emscripten Swift.** The clean answer, and blocked on a
toolchain that must be built from an unmerged branch.

## Decision

**A, behind a seam that does not foreclose B or C.**

The seam is the point: `FlutterSwiftBridge`'s Swift types (`Canvas`, `Path`,
`Paragraph`, `SceneBuilder` …) stay the framework's only view of the engine,
and gain a second backend selected by `#if os(WASI)`. `Flutter` (174k lines)
does not learn that the web exists.

Milestones, each one visible in a browser:

0. **Pixels.** A Swift wasm module draws a rectangle and a paragraph through
   skwasm into a `<canvas>`, driven by `requestAnimationFrame`. No SDK code.
   Take `skwasm.wasm`/`skwasm.js` from a Flutter SDK's
   `flutter_web_sdk` rather than building the engine; build our own only once
   the version needs pinning (`download_emsdk` in `.gclient`, then
   `tools/gn --web`).
1. **The framework compiles.** `Flutter` and `FlutterSwiftBridge` for
   wasm32 with the backend stubbed: fix `Color`, fence off `Terminal/`
   (9.6k lines) and `Platform/` (3.2k) which are compiled in unconditionally
   and guarded by `#if !os(Windows)` tests that WASI passes, and give
   `Timer`/`RunLoop`/`DispatchQueue.main` a single-threaded shim the page's
   event loop drains.
2. **CounterApp renders.** Backend for canvas, paint, path, picture,
   paragraph and fonts; a Swift SceneBuilder that flattens to skwasm pictures;
   pointer and key events from DOM listeners into the existing callback
   table.
3. Images, shaders, semantics, text input.

## Open questions

- `Color`: `UInt32` parameter, or keep `Int` and wrap 353 literals? The first
  is an API change every app sees; decide before milestone 1.
- Binary size. A debug Swift+Foundation module is 7.4 MB before any
  framework code; skwasm adds its own. Embedded Swift is not an option while
  the framework uses Foundation.
- Whether `Foundation` stays. 89 files import it, mostly for
  `String(format:)`.
- Fonts: skwasm has no system font access, so the page must fetch and
  register every face, including fallbacks.

## Where it stands

Milestone 0 is done. `build/web-app.sh --serve` builds `web/Sources/Pixels`,
stages `.stage-web/` and serves it; the page draws a rounded card, an
animated path, circles, a pointer ring and two wrapped paragraphs, at the
display's refresh rate. Checked in headless Chrome 154 (SwiftShader); not yet
eyeballed in Safari or Firefox.

    web/Package.swift                     its own package — sdk/'s manifest
                                          cannot be built for wasm
    web/Sources/CSkwasm/include/skwasm.h  skwasm's exports as wasm imports
    web/Sources/Pixels/main.swift         the demo
    web/host/starling.js, index.html      loader, WASI shim, glue
    build/web-app.sh                      build + stage + serve

How the pieces meet, which is the part the backend inherits:

- **Imports are declared in C**, with `import_module`/`import_name`
  attributes, and reach Swift through ordinary C interop. No experimental
  Swift feature is involved. The 50 skwasm functions the demo uses bind
  straight to skwasm's exports, so a draw call never enters JavaScript.
- **A skwasm pointer is a `UInt32`, never a Swift pointer.** It is an address
  in the other module's memory. Arguments passed by pointer are built on
  skwasm's own stack (`_emscripten_stack_alloc`) and filled by one host call,
  `starling_host_write`.
- **The render callback belongs to the page.** skwasm reports a finished
  frame through a function in its own table that takes an `externref`; Swift
  cannot declare that type. `starling.js` adds the function
  (`addFunction(fn, 'viie')`), puts the `ImageBitmap` on a `bitmaprenderer`
  canvas, and calls Swift's exported `starling_frame_presented`.
- **Text breaks come from the browser.** The light skwasm build has no ICU;
  the page feeds grapheme, word and line breaks from `Intl.Segmenter` and
  `Intl.v8BreakIterator` before `paragraphBuilder_build`. Without them text
  does not wrap. Firefox and Safari lack the line iterator — the fallback in
  `starling.js` is only right for space-separated scripts, and
  `skwasm_heavy` (ICU inside) is the real answer there.
- **The module is a WASI reactor**: `_initialize`, then `__main_argc_argv`
  once, then exported functions for the life of the tab.
- **skwasm is fetched, not built**: gstatic publishes it per engine commit
  and `df87ee3db00` — the upstream commit our engine forked from — is there,
  so the binary matches the `.cpp` files the header was written from.

## Traps paid for

- Headless Chrome never exits on this page: the animation keeps it from
  going idle, so `--virtual-time-budget` has nothing to wait out. The
  screenshot is written regardless; kill the process afterwards.
- The macOS toolchain `.pkg` repoints `~/Library/Developer/Toolchains/
  swift-latest.xctoolchain` at whatever it installed.
- `swiftly` on this machine cannot install 6.4 — it builds the URL from
  `6.4`, the file is under `6.4.0`.
- The release `app.wasm` is 7.0 MB with no Foundation and 300 lines of
  Swift: 4.4 MB of code, 1.0 MB of data, 1.6 MB of names. The standard
  library is not being dead-stripped. Not yet investigated (`wasm-opt`,
  `--strip-debug`, `-Osize`).

## Next: milestone 1

Make `Flutter` and `FlutterSwiftBridge` compile for wasm32 with the engine
stubbed out. The work, in the order it will bite:

1. A manifest that can describe the framework without C++ interop — either
   `sdk/Package.swift` learns a `STARLING_WASM` environment switch (as it did
   `STARLING_IOS`), or `web/Package.swift` reaches into `../sdk/Sources` by
   path.
2. `FlutterSwiftBridge` split at the engine: the pure-Swift half (`Offset`,
   `Rect`, `Color`, enums — most of its 29k lines) and the half that names a
   `flutter.swift_bridge.*` class, which gets a `#if os(WASI)` twin over
   `CSkwasm`.
3. `Color` and the other 64-bit `Int` assumptions.
4. `Terminal/` and `Platform/` fenced out; timers and the main queue shimmed.
