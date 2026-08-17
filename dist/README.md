# dist — prebuilt downloads carried in the tree

`starling-terminal-windows-x86_64.zip` — Starling Terminal for Windows,
x86_64, the 0.1.0 release candidate. 47.2 MB, 52 entries, checksum in
`SHA256SUMS`.

`starling-sdk-macos-arm64.tar.gz` — the Starling SDK for macOS arm64, the
0.3.0 release candidate: framework source plus the release engine binaries
(`FlutterMacOS.framework`, `libswift_bridge.dylib`) and flutter_assets, in
one tree a consumer depends on by path. 14 MB, checksum in `SHA256SUMS`.

Every other binary is a GitHub Release asset rather than repo contents
(`v0.3.0` carries the .deb, `sdk-v0.2.0` the SDK's Linux tarball and
Windows zip). These two are in the tree by explicit request, each so that a
build is downloadable from a checkout before its release is cut.
Do not take it as licence to add more: a binary committed here is in every
clone forever, and removing it later means rewriting history.

## What is in it, and what it needs

The staged tree `sdk/tools/stage-windows.ps1` defines — the executable, the
35 Swift-runtime and engine DLLs beside it, `data/icudtl.dat` and
`data/flutter_assets/`, the font and icon resource bundles, and the bundled
`conpty.dll` + `OpenConsole.exe` console host. Everything must stay in one
directory: Windows resolves imports from the executable's own directory, and
an app missing them dies with `STATUS_DLL_NOT_FOUND` before `main`.

**It extracts flat** — 52 files into the current directory, with no wrapper
folder. Unzip it into a directory you made for it. (The SDK bundle wraps its
contents in a named directory; `stage-windows.ps1 -Zip` does not, because it
archives a staged tree rather than a package.)

## Provenance

Built on the win11 VM from `release-terminal-0.1.0`, release configuration,
against `engine/src/out/host_release`:

    sdk\tools\build-windows.ps1 -PackagePath ..\apps\TerminalApp `
        -Product TerminalApp -Configuration release
    sdk\tools\stage-windows.ps1 -PackagePath ..\apps\TerminalApp `
        -Product TerminalApp -Configuration release -Zip `
        -Out C:\dist\starling-terminal-windows-x86_64 `
        -EngineOut C:\src\starling-engine\engine\src\out\host_release

The executable is stamped 2026-08-15 08:56:26 — the shipping configuration
(ConPTY pipe buffer at the system default, reader/parser thread boost off),
which is the binary every number in
`docs/perf/terminal-windows-race-regime-2026-08-15/` was measured on.

`-Zip` is the only supported way to build this archive. `Compress-Archive`
writes entry names with backslashes, which the ZIP spec forbids; Windows'
own tools tolerate it, so the mistake is invisible until someone unzips on
Linux or macOS and gets one long flat filename. The staging script asserts
against it — 0 backslash entries, `data/icudtl.dat` present — and refuses to
write an archive that fails either check.

## The SDK bundle's provenance

Built on the Mac from `release-sdk-0.3.0` (engine `ea78543`,
`host_release_arm64`), verified by unpacking to a clean directory, building
the whole package as a path-dependency consumer, and launching an example —
the engine starts from the bundle's own `engine/lib`:

    sdk/tools/make-bundle.sh --release "$PWD/.stage-sdk"

It unpacks into a named `starling-sdk-macos-arm64/` directory (unlike the
terminal zip, which extracts flat).

## Refreshing them

Rebuild as above, copy the artifact here, and regenerate the checksums —
one file, both lines:

    shasum -a 256 starling-terminal-windows-x86_64.zip \
                  starling-sdk-macos-arm64.tar.gz > SHA256SUMS

Replace files rather than adding versions; each version committed costs its
full size in permanent history.
