# dist — prebuilt downloads carried in the tree

`starling-terminal-windows-x86_64.zip` — Starling Terminal for Windows,
x86_64, the 0.1.0 release candidate. 47.2 MB, 52 entries, checksum in
`SHA256SUMS`.

Every other platform's binaries are GitHub Release assets rather than repo
contents (`v0.3.0` carries the .deb, `sdk-v0.2.0` the SDK's Linux tarball and
Windows zip). This one is in the tree by explicit request, so that a Windows
build is downloadable from a checkout before the terminal release is cut.
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

## Refreshing it

Rebuild and re-stage as above, copy the zip here, and regenerate the
checksum:

    sha256sum starling-terminal-windows-x86_64.zip > SHA256SUMS

Replace the file rather than adding a second one; each version committed
costs another 47 MB of permanent history.
