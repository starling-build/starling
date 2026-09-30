# Rendering the SDK in WebAssembly — exploration

Status, 2026-09-29: **architecture A is chosen** (the one Dart and Flutter
use) and **CounterApp — the real SDK — runs in a browser** — see "Where it
stands". Branch `wasm` in both
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

**CounterApp runs in Chrome from the unmodified SDK**: `build/web-app.sh
--serve`, open http://localhost:8137/. The Material app bar, the text, the
floating action button and its icon draw, and clicks count. Verified by
headless-Chrome screenshots and by clicking through the DevTools protocol.
Milestones 0, 1 and 2 of the list above are done, on the same day.

How it is put together, top down:

- **`STARLING_WASM=1` selects a target list of its own in `sdk/Package.swift`**
  — no C++ interop anywhere, no engine link, `Terminal/` and the desktop
  app host excluded, no resources.
- **`FlutterSwiftBridgeCxx` is a Swift module on the web**
  (`sdk/Sources/FlutterSwiftBridgeWeb/`, ~5k lines): the 29 `flutter.swift_bridge.*`
  classes re-made with the same names and signatures as C++ interop gives
  them, over skwasm's exports. `FlutterSwiftBridge` — the 29k-line dart:ui
  layer — compiles **unchanged** against it. The layer tree that natively
  is the engine's `flow` lives in `Scene.swift` and is flattened into one
  picture per frame. Every gap is a `// WEB-TODO:` (26 of them).
- **skwasm's exports are declared in C** (`sdk/Sources/CSkwasm/include/skwasm_*.h`,
  one header per area) with `import_module`/`import_name` attributes, so
  the 220 functions the app uses bind straight to skwasm's exports and a
  draw call never enters JavaScript.
- **`FlutterWeb` is the host** (`sdk/Sources/FlutterWeb/WebHost.swift`), what
  `FlutterCocoa` is on macOS. There is no engine and no loop: the page calls
  the exported `starling_*` functions (resize, begin_frame, pointer, scroll,
  timer_fired, font_loaded) and each calls the same `SwiftRuntimeDelegate`
  the callback table calls natively. Pointer add/hover/down/up/remove
  sequencing is done here from the DOM's flat events.
- **Foundation's gaps are filled in three places.** `DispatchQueue`,
  `DispatchTime` and `DispatchWorkItem` are re-made in the bridge module
  over the page's `setTimeout` (`Dispatch.swift`); `Timer` and `RunLoop`,
  which Foundation ships for WASI but which do not link (they want a
  CoreFoundation run loop), are shadowed inside the `Flutter` module
  (`Foundation/WebSupport.swift`), which also `@_exported import`s libm and
  the bridge so every file sees them.
- **`Color(0xFF……)` compiles through a new `init(_ value: Int64)`**; the
  `Int` initializer is `@_disfavoredOverload`, so literals take the wide
  one and variables the narrow one, with no call site changed. `ColorSwatch`
  and `ShadedColor` take `Int64` likewise. Three other 64-bit literals were
  respelled.
- **The page** (`web/host/starling.js`) is the same file milestone 0 wrote,
  grown: fonts are `{url, families}` and the first is also registered under
  skwasm's fallback name (`Roboto`); a WASI shim with the dozen calls
  Foundation makes at start-up; pointer, wheel and timer plumbing.

### Numbers

- Release `app.wasm`: **11.9 MB**, 3.6 MB brotli (was 60 MB; 11.6 before
  the office rebase). The size
  work and what it found is docs/plans/wasm-size.md; `build/web-app.sh
  --check` is the gate that keeps it there.
- Debug `app.wasm`: ~107 MB, and it is what to run when something traps —
  the name section turns `unreachable` into a Swift stack trace.
- Debug build of the whole stack from clean: ~6 min. Release: ~2 min plus
  10 s of wasm-opt.

### Not done, in the order it will matter

1. **IME and touch keyboards.** Hardware keys work (`starling_key`, with
   the web engine's own key tables, generated into `web/host/keymap.js`);
   composed input — dead keys, CJK, a phone's keyboard — needs a hidden
   `<input>` the way Flutter web does it.
2. **Fonts by request**: today the page lists them up front. The framework
   could ask for a family it meets (`starling_host_load_font`) the way
   Flutter web's font manifest works.
3. **Text in Firefox and Safari**: the line-break fallback in `starling.js`
   is wrong for CJK; the heavy skwasm build (ICU inside) is the fix.
4. **Semantics**: a DOM/ARIA tree. `Semantics.swift` drops everything.
5. **Animated images** decode to their first frame; `ImageDecoder` (the
   browser API) would give the rest. Image readback (`toByteData`) needs
   `surface_rasterizeImage` and the render callback.
6. **An `Image` widget.** The framework has `RenderImage` and the
   providers but no widget over them; `Examples/WebImages` goes the long
   way round.

**Office runs in the browser** (`build/web-app.sh OfficeApp --package
apps/OfficeApp --serve`): the ribbon, ruler, page, status bar; typing,
bold, tooltips, word count. What it took, and what a second app will
take: a web branch in the app's manifest (no C++ interop, `FlutterWeb`,
zlib compiled in from `build/tools/fetch-zlib.sh` because the WASI sysroot
has none); `WebWindowedHost.install()` where the other hosts install; the
app's fonts staged and listed by name in `fonts/manifest.json`; NSString
path arithmetic as plain Swift (`Paths.swift`); a small XML reader
(`MiniXML.swift`) where FoundationXML would have been; `String(printf:)`
for the app's three formats; and file dialogs, recent files, PDF export
and the `--convert` command line fenced off — a tab has no files (and
`FileManager.createDirectory(withIntermediateDirectories:)` recurses
forever on WASI, so it must not be reached). Release: 12.2 MB, 0.6 MB
over CounterApp.

Done since the list was first written: keyboard (`starling_key`), Swift
concurrency on the page's event loop (`FlutterWeb/WebExecutor.swift`),
image decoding by the browser (`starling_host_decode_image` →
`image_createFromTextureSource`), the `UInt32(toARGB32())` traps.

**Office opens and saves files in the browser.** Open goes through the
page's hidden `<input type=file>` (`starling_host_open_file` →
`starling_file_opened`, `FlutterWeb/WebFiles.swift`), save and export
through a Blob download (`starling_host_download`); Ctrl+O and Ctrl+S
are the same keys as native. Verified on the 26-page Word fixture: open,
type, save, and the download carries the edit and the document's own
font names. (Reopening the saved file lays out as 30 pages, natively
too: the docx writer loses paragraph-style fonts. A writer bug, not a
web one.) Do not listen for the picker's `cancel` event: headless
Chrome fires it at once, and it would consume the completion the
`change` event owes.

**The browser lays a document out line for line as the desktop does**,
and `test/office-layout.sh` proves it on every run (docs/plans/office.md
"One layout everywhere": the dump, the gates, the two differences found
and fixed). `build/tools/web-drive.mjs` is the browser's
`shell-drive.py` — click, type, chord, setfile, downloads, eval, dump,
shot — and `starling.debug(kind)` on the page is the app's debugging
door (`hostDebugQuery`).

**Document fonts are Google Docs' model**, on every platform: the file
keeps the name it came with (Times New Roman, Calibri, Consolas), and
`OfficeFonts.substitute` draws it with a metric clone the app ships —
Liberation, Carlito, Caladea — through the theme's `fontFamilyResolver`.
The UI face is Selawik, the Fluent theme's default now, with the Fluent
icon font and Selawik as glyph-fallback families on every web style
(`!` entries in `fonts/manifest.json`).

**The branch tracks `office`.** Rebased onto office f2b64a9 on
2026-09-30, because the runtime callback table changed shape (bool
`dispatch_key_data`, the outbound platform-message pair) and the native
app crashed in `createRuntimeCallbacks` against the newer engine. The
web stand-in header `CSkwasm/include/swift_runtime_callbacks.h` must
mirror the engine's `flutter/lib/ui/swift/include/swift_runtime_callbacks.h`
entry for entry — diff the two whenever the rebase touches it. What the
rebase brought that the web could not take as written: the
`STARLING_IME` text-input connection (JSON codec over legacy Foundation
— off and fenced on WASI; the browser has no `flutter/textinput` plugin
yet, see item 1 above), AutoSave/recovery copies and print (fenced: no
files of ours in a tab), HTML paste (portable string spellings).

Native verification without touching the sibling session's tree: point
the manifests at the other checkout's engine —
`E=~/dev/starling/starling-engine/engine/src/out/host_debug_arm64
FLUTTER_SWIFT_ENGINE_OUT=$E STARLING_ENGINE_OUT=$E swift test
--package-path apps/OfficeApp --scratch-path $PWD/.build-macos-office`,
and `OfficeApp --convert in.docx out.pdf` for a rendering to compare
with the browser's (`screencapture` needs a permission this shell lacks).

## Traps paid for

- **The default shadow stack is small, and overflowing it corrupts the
  heap instead of trapping.** A debug build of the Todos app died with an
  allocation failure on its very first widget: the stack had walked down
  into the heap during the deep, uninlined build. The linker now gets
  `-z stack-size=16MB`; `--stack-first` (which would make an overflow trap
  at the right frame) is refused alongside the driver's `--global-base`.
- **The Swift runtime's last words are lost on a trap.** `fatalError`'s
  message is written without a newline and the process aborts before any
  buffered stdio flushes, so the page's `fd_write` no longer waits for a
  newline on stderr — and still nothing arrived, so read the stack, not
  the message.

- **Adding a header to `CSkwasm/include` does not invalidate the clang
  module cache.** New declarations come back as `cannot find X in scope`
  while the header plainly declares them; `rm -rf .build-web/wasm32-unknown-wasip1/debug/ModuleCache`
  before believing it.
- **Stale objects after changing a type's module.** After `Timer` moved from
  Foundation to the module-local stand-in, `Tap.swift.o` still referenced
  `Foundation.Timer` and the link failed; the fix was deleting
  `Flutter.build`, not code.
- **Chrome headless will not lay out narrower than 500 px**, so a
  `--window-size=480,…` page reports width 500 and the right edge is cut
  off in the PNG. It is not the app.
- **Foundation on WASI traps in `__CFInitialize`** unless the WASI shim
  answers `clock_res_get`; and `Bundle.main` traps outright. Nothing may
  reach either.
- Headless Chrome never exits on this page: the animation keeps it from
  going idle, so `--virtual-time-budget` has nothing to wait out. The
  screenshot is written regardless; kill the process afterwards.
- The macOS toolchain `.pkg` repoints `~/Library/Developer/Toolchains/
  swift-latest.xctoolchain` at whatever it installed.
- `swiftly` on this machine cannot install 6.4 — it builds the URL from
  `6.4`, the file is under `6.4.0`.
