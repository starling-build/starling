# Writer

Writer's native and browser builds share the Swift UI in `Sources/OfficeApp`.
`OfficeAppearance.swift` defines the chrome palette and typography. Document
styles and file formats are independent of those UI settings.

Run these commands from the repository root.

## Browser

Use a swift.org toolchain with its matching WebAssembly SDK installed. The local
preview was built with Swift 6.4 and the `swift-6.4.0-RELEASE_wasm` SDK:

```sh
STARLING_WASM_SDK=swift-6.4.0-RELEASE_wasm \
  build/web-app.sh OfficeApp --package apps/OfficeApp
python3 build/tools/web-serve.py .stage-web-OfficeApp 8137
```

Ensure that toolchain's `usr/bin` is first on `PATH`. `STARLING_WASM_SDK` can be
omitted when the script's compiler-derived name matches the installed SDK name.
The build fetches zlib and the prebuilt skwasm renderer, stages fonts, and produces
`.stage-web-OfficeApp`. No native engine build is needed for the browser.

## macOS

The native build needs `FlutterMacOS.framework` and `libswift_bridge.dylib` from
the engine's `host_release_arm64` output. To reuse an existing engine build from
another checkout, set both variables to that same output directory:

```sh
export STARLING_ENGINE_OUT=/absolute/path/to/engine/src/out/host_release_arm64
export FLUTTER_SWIFT_ENGINE_OUT="$STARLING_ENGINE_OUT"
STARLING_APP_DISPLAY_NAME="Writer Codex Preview" build/macos-app.sh OfficeApp
```

The separate display name produces `.stage-macos/Writer Codex Preview.app`.
This preview was built with the installed Swift 6.2.1 toolchain. Append `--run`
to launch the assembled app.

## Verify

With the same native toolchain and engine variables:

```sh
swift test -c release --package-path apps/OfficeApp
```

`RibbonCompositingTests` covers the local painting bounds of ribbon dropdowns
inside a scrolling toolbar. Browser controls can be exercised using
`build/tools/web-drive.mjs`; see its header for screenshot, typing, file, and
layout-dump commands.
