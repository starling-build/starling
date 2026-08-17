# dist — prebuilt downloads carried in the tree

`starling-terminal-windows-x86_64.zip` — Starling Terminal for Windows,
x86_64, the 0.1.0 release candidate. 47.2 MB, 52 entries, checksum in
`SHA256SUMS`.

`starling-terminal-macos-arm64.zip` — Starling Terminal for macOS arm64, the
same 0.1.0 release candidate. 17.2 MB, checksum in `SHA256SUMS`. Unlike the
Windows archive it wraps a `.app`, so it extracts to
`Starling Terminal.app` rather than flat, and needs no directory made for it.

Opening it needs no command and no arguments — verified by running the
unpacked app under `env -i` with the SDK bundle it was built against moved
away: the engine rides in `Contents/Frameworks`, every rpath resolves inside
the bundle, and a Finder launch picks up the login shell. The one first-launch
step is Gatekeeper's: the bundle is **ad-hoc signed, not notarized**
(`spctl` rejects it once a browser has set the quarantine flag), so a
downloaded copy wants right-click → Open, or Privacy & Security →
**Open Anyway**, or `xattr -dr com.apple.quarantine` once. Removing that step
means Developer ID signing plus notarization, not a build change.

`starling-sdk-macos-arm64.tar.gz` — the Starling SDK for macOS arm64, the
0.3.0 release candidate: framework source plus the release engine binaries
(`FlutterMacOS.framework`, `libswift_bridge.dylib`) and flutter_assets, in
one tree a consumer depends on by path. 14 MB, checksum in `SHA256SUMS`.

`starling-sdk-linux-x86_64.tar.gz` — the same SDK for Linux x86_64, the same
0.3.0 release candidate and the same engine commit: framework source, the
three release engine libraries (`libflutter_engine.so`,
`libflutter_linux_gtk.so`, `libflutter_linux_drm.so`), `icudtl.dat` and
flutter_assets. 23 MB, checksum in `SHA256SUMS`.

`starling-sdk-windows-x86_64.zip` — the same SDK for Windows x86_64, the same
0.3.0 release candidate and the same engine commit: framework source, both
release engine DLLs **and both import libraries** (`flutter_engine.dll`,
`flutter_engine.dll.lib`, `flutter_windows.dll`, `flutter_windows.dll.lib`),
`icudtl.dat` and flutter_assets. 17.1 MB, checksum in `SHA256SUMS`. The import
libraries are why this bundle can replace an engine checkout and the staged
terminal zip cannot: on Windows the link needs the `.dll.lib`, and that archive
ships only the DLLs.

It also carries `Vendor/conpty/` — `conpty.dll` and `OpenConsole.exe` — which
the macOS and Linux bundles have no equivalent of, because a pty there is
`forkpty` from libc. Windows has no such call, and the terminal widget loads
that DLL from beside the executable; with no copy to load it falls back to the
inbox `conhost.exe`, correctly and silently, at roughly three times the CPU on
the read path. An SDK that omitted them would build terminals that work and are
slow, with nothing to point at.

Every other binary is a GitHub Release asset rather than repo contents
(`v0.3.0` carries the .deb, `sdk-v0.2.0` the SDK's Linux tarball and
Windows zip). These five are in the tree by explicit request, each so that a
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

Built on the real Windows box (not the win11 VM this time) from
`release-terminal-0.1.0` at `382298a`, release configuration, against a
`host_release` engine built from `starling` at `ea78543d95e`:

    sdk\tools\build-windows.ps1 -PackagePath apps\TerminalApp `
        -Product TerminalApp -Configuration release
    sdk\tools\stage-windows.ps1 -PackagePath apps\TerminalApp `
        -Product TerminalApp -Configuration release -Zip `
        -Out C:\dist\starling-terminal-windows-x86_64 `
        -EngineOut C:\Users\starling\dev\starling-engine\engine\src\out\host_release

Toolchain: Swift 6.2.3, MSVC 14.44.35207, Windows SDK 10.0.22621 — the same
pairing the VM used, chosen deliberately over the newer Swift and SDK on offer
so the binary is comparable to the one it replaces. What a Windows build host
needs from nothing is in `docs/BUILDING.md`.

The executable is stamped 2026-08-16 22:21:24 and carries the tab work from
`393d089` (several shells in one window), which the previous archive predated.

**It is not the binary the Windows numbers were measured on.** Everything in
`docs/perf/terminal-windows-race-regime-2026-08-15/` and
`docs/perf/terminal-windows-realgpu-2026-08-16/` was measured on the
2026-08-15 08:56:26 executable, one commit range and one engine older than
this. Re-measure before quoting those figures against this archive.

`-Zip` is the only supported way to build this archive. `Compress-Archive`
writes entry names with backslashes, which the ZIP spec forbids; Windows'
own tools tolerate it, so the mistake is invisible until someone unzips on
Linux or macOS and gets one long flat filename. The staging script asserts
against it — 0 backslash entries, `data/icudtl.dat` present — and refuses to
write an archive that fails either check.

## The macOS terminal's provenance

Built on the Mac from `release-terminal-0.1.0`, **from the released SDK
bundle alone** — the consumer path, not a privileged in-repo one:

    tar xzf dist/starling-sdk-macos-arm64.tar.gz -C /tmp/sdk
    STARLING_SDK_BUNDLE=/tmp/sdk/starling-sdk-macos-arm64 \
        build/macos-app.sh TerminalApp --zip

Both halves matter. `STARLING_SDK_BUNDLE` redirects the app's path dependency
*and* the `-L`/rpath into the bundle's own `engine/lib`; the script then takes
flutter_assets from `engine/share` instead of this repo's `sdk/Resources`, so
staging never reaches back into a tree a consumer does not have. The build plan
was checked for it: 46 references to the unpacked bundle, zero to
`starling-engine` or to `sdk/`. The archive is renamed on the way in —
`macos-app.sh` emits `Starling-Terminal-0.1.0-macos-arm64.zip`, this directory
keeps every artifact at `<product>-<platform>-<arch>` so a version bump
replaces a file instead of accumulating one.

Like the Windows archive, **this is not the binary the macOS numbers were
measured on**: it carries the tab work from `393d089`, where
`docs/perf/terminal-vs-ghostty-macos-2026-08-14-postupgrade/` predates it.
Re-measure before quoting those figures against this archive.

## The SDK bundles' provenance

The macOS one was built on the Mac from `release-sdk-0.3.0` (engine
`ea78543`, `host_release_arm64`), verified by unpacking to a clean directory,
building the whole package as a path-dependency consumer, and launching an
example — the engine starts from the bundle's own `engine/lib`:

    sdk/tools/make-bundle.sh --release "$PWD/.stage-sdk"

The Linux one is the same branch and the same engine commit, built on the dev
box against `host_release`, and verified the same way — a path-dependency
consumer compiled the whole framework, `readelf -d` showed both engine
libraries resolving out of the bundle's `engine/lib` with nothing set in the
environment, and a `CounterApp` built inside the unpacked bundle came up on
the desktop session and drew text:

    FLUTTER_SWIFT_ENGINE_OUT=<a private copy of the release binaries> \
        sdk/tools/make-bundle.sh --release "$PWD/.stage-sdk"

**Build the engine at the release commit into a directory nobody else writes,
and check the tarball rather than the out directory.** The engine checkout is
shared — one clone, several worktrees, and whoever else is working on the box
— so an out directory verified at 21:45 is someone else's branch at 21:48:
that is not a hypothetical, it is what happened here, and the bundle built
afterwards carried an unreleased `fl_drm_view_inject_pointer_abs` with
nothing in it to say so. Two things make the check hold:

    # take the sources back without moving HEAD under anyone
    git checkout <release-commit> -- engine/src/flutter/shell/platform/linux_drm/
    ninja -C engine/src/out/host_release libflutter_engine.so \
        libflutter_linux_drm.so libflutter_linux_gtk.so
    cp -p engine/src/out/host_release/{libflutter_engine.so,libflutter_linux_drm.so,\
libflutter_linux_gtk.so,icudtl.dat} <private dir>      # snapshot, then restore
    git checkout HEAD -- engine/src/flutter/shell/platform/linux_drm/ && ninja -C …

and then `nm -D` on the copies **inside the finished tarball**, not on the
shared out directory. Check `libflutter_engine.so` too, not just the DRM
embedder: our `libflutter_engine.so` links the linux_drm sources as well
(41 `fl_drm` symbols in it), so a drm-only diff shows up in both libraries and
looking at one of them understates what shipped.

The Windows one was built on the Windows box from `release-sdk-0.3.0` against a
`host_release` engine built from the paired engine branch — which is the same
`ea78543` the other two carry, so all three bundles ship one engine commit. The
engine checkout on that box is not shared with anyone, and its tree was clean at
`ea78543` when the DLLs were linked, so the snapshot dance above was not needed
here. `sync-vendored-headers.sh --check` passed against that engine, which is
the header-ABI half of the same guarantee:

    sdk\tools\make-bundle.ps1 -Configuration release `
        -EngineOut <engine>\engine\src\out\host_release `
        -OutDir <repo>\.stage-sdk

Verified the way the other two were: unpacked to a clean directory and built
with nothing in the environment pointing at an engine checkout
(`FLUTTER_SWIFT_ENGINE_OUT` and `STARLING_ENGINE_OUT` both cleared), so the
link had only the bundle's own `engine/lib` to resolve against.
`tools\build-windows.ps1 -PackagePath . -Configuration release` compiled the
whole framework and both example executables — `CounterApp.exe` and
`TerminalTiling.exe` — in 515 s with no errors. A bundle missing an import
library fails that at link time, which is the failure this catches.

Getting the drift check to run on Windows at all took three fixes (`3147f5d`) —
it had been silently skipped on the VM, which has no bash. Note the toolchain that
built these DLLs is Swift 6.2.3 / MSVC 14.44 / Windows SDK 10.0.22621, and that
a consumer needs its own Swift toolchain: the runtime DLLs deliberately do not
travel in the bundle.

All three unpack into a named directory (`starling-sdk-linux-x86_64/`,
`starling-sdk-macos-arm64/`, `starling-sdk-windows-x86_64/`), unlike the
terminal zip, which extracts flat.

## Refreshing them

Rebuild as above, copy the artifact here, and regenerate the checksums —
one file, all five lines, because writing it with one filename is how the
Windows zip's line got dropped once already:

    sha256sum starling-terminal-windows-x86_64.zip \
              starling-terminal-macos-arm64.zip \
              starling-sdk-macos-arm64.tar.gz \
              starling-sdk-linux-x86_64.tar.gz \
              starling-sdk-windows-x86_64.zip > SHA256SUMS

(`shasum -a 256` on the Mac — same format, same file. On Windows,
`Get-FileHash -Algorithm SHA256` and lower-case the hash; write the file with
`[IO.File]::WriteAllText` and LF, since `Out-File` will give it CRLF.)

Replace files rather than adding versions; each version committed costs its
full size in permanent history.
