# dist — prebuilt downloads carried in the tree

`starling-terminal-0.1.0-windows-x86_64.zip` — Starling Terminal for Windows,
x86_64, the 0.1.0 release candidate. 47.2 MB, 52 entries, checksum in
`SHA256SUMS`.

`starling-terminal-0.1.1-macos-arm64.zip` — Starling Terminal for macOS arm64.
16 MB, checksum in `SHA256SUMS`. Unlike the Windows archive it wraps a `.app`,
so it extracts to `Starling Terminal.app` rather than flat, and needs no
directory made for it.

**0.1.1 is 0.1.0 plus two fixes, both of which made the shipped macOS archive
work only on the machine that built it.** No feature changed; Linux and Windows
are unaffected and stay at 0.1.0, which is why the version here is one ahead of
the other two rather than all three moving together.

- **It crashed at startup on every other Mac.** SwiftPM generates
  `Bundle.module` with two candidates: the app bundle's own directory, and an
  absolute path into the build directory that produced the binary. Inside a
  `.app` the first misses — resource bundles are staged under
  `Contents/Resources/` — and the second hit only where it was built. Anywhere
  else, `resource_bundle_accessor.swift:12: could not load resource bundle`, on
  the first font load. The sources search for their bundles now, and
  `build/macos-app.sh` fails the build if a build-directory path survives into
  the executable.
- **Its signature did not survive a plain `unzip`.** `ditto -c -k` without
  `--sequesterRsrc` stores extended attributes as AppleDouble, which
  command-line `unzip` materializes as `._Foo` files *inside* the bundle,
  breaking the seal. The 0.1.0 install recipe said `ditto -xk`, which handles
  AppleDouble correctly — so the release notes' own instructions hid it. The
  build sequesters that metadata now and verifies the archive after a plain
  `unzip` rather than the bundle it just built.

The 0.1.0 macOS archive is **removed rather than kept beside this one**: it
carries both bugs, and an archive that crashes on arrival is not worth the
history it would cost.

Opening it needs no command and no arguments — verified by running the
unpacked app under `env -i` with the SDK bundle it was built against moved
away: the engine rides in `Contents/Frameworks`, every rpath resolves inside
the bundle, and a Finder launch picks up the login shell. The one first-launch
step is Gatekeeper's: the bundle is **ad-hoc signed, not notarized**
(`spctl` rejects it once a browser has set the quarantine flag), so a
downloaded copy wants right-click → Open, or Privacy & Security →
**Open Anyway**, or `xattr -dr com.apple.quarantine` once. Removing that step
means Developer ID signing plus notarization, not a build change.

`starling-terminal_0.1.0_amd64.deb` — Starling Terminal for Linux x86_64, the
same 0.1.0 release candidate. 52 MB, checksum in `SHA256SUMS`. A **.deb**
rather than an archive, because Linux has an install path the other two do not:
`sudo dpkg -i` (or `apt install ./…`) puts it on the applications menu with its
icon, and `dpkg-shlibdeps` computed the system dependencies so a missing GTK or
libinput is a package error rather than a crash on launch. It runs on any
desktop — GNOME, KDE, Wayland or X11 — and installs cleanly beside the desktop
package, sharing nothing with it.

Everything it loads lives in `/usr/lib/starling-terminal`: the engine libraries,
`libFlutterShared`, the Swift runtime closure, the font resource bundles and
`data/icudtl.dat`. No flutter_assets — the Swift runtime never reads them.

`starling-sdk-0.3.0-macos-arm64.tar.gz` — the Starling SDK for macOS arm64, the
0.3.0 release candidate: framework source plus the release engine binaries
(`FlutterMacOS.framework`, `libswift_bridge.dylib`) and flutter_assets, in
one tree a consumer depends on by path. 14 MB, checksum in `SHA256SUMS`.

`starling-sdk-0.3.0-linux-x86_64.tar.gz` — the same SDK for Linux x86_64, the same
0.3.0 release candidate and the same engine commit: framework source, the
three release engine libraries (`libflutter_engine.so`,
`libflutter_linux_gtk.so`, `libflutter_linux_drm.so`), `icudtl.dat` and
flutter_assets. 23 MB, checksum in `SHA256SUMS`.

`starling-sdk-0.3.0-windows-x86_64.zip` — the same SDK for Windows x86_64, the same
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
Windows zip). These six are in the tree by explicit request, each so that a
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

Built on the real Windows box (not the win11 VM this time), release
configuration — and **built against the SDK bundle beside it**, not against
this repo's `sdk/` or an engine checkout. That is the point: the shipped
terminal is now produced exactly the way an external consumer produces one, so
every release exercises the bundle it ships with.

    # unpack the SDK release artifact; nothing else is on PATH or in the env
    Expand-Archive dist\starling-sdk-0.3.0-windows-x86_64.zip -DestinationPath C:\dist\sdk-only
    $env:STARLING_SDK_BUNDLE = "C:\dist\sdk-only\starling-sdk-windows-x86_64"

    sdk\tools\build-windows.ps1 -PackagePath apps\TerminalApp `
        -Product TerminalApp -Configuration release
    sdk\tools\stage-windows.ps1 -PackagePath apps\TerminalApp `
        -Product TerminalApp -Configuration release -Zip `
        -Out C:\dist\sdkbuilt\starling-terminal-windows-x86_64 `
        -EngineOut $env:STARLING_SDK_BUNDLE\engine\lib

`FLUTTER_SWIFT_ENGINE_OUT` and `STARLING_ENGINE_OUT` must be unset for this to
mean anything. With either set — or with `STARLING_SDK_BUNDLE` unset on a box
that has an engine checkout — the manifest's own `-L` finds the checkout and
the build passes while proving nothing. The check is the build plan: it carried
58 references to the unpacked bundle and zero to `starling-engine` or to
`sdk/`. The engine, `icudtl.dat`, flutter_assets and `conpty.dll` +
`OpenConsole.exe` in this archive all came out of that bundle
(`7658b95e`, engine `ea78543`).

Toolchain: Swift 6.2.3, MSVC 14.44.35207, Windows SDK 10.0.22621 — the same
pairing the VM used, chosen deliberately over the newer Swift and SDK on offer
so the binary is comparable to the one it replaces. What a Windows build host
needs from nothing is in `docs/BUILDING.md`.

The executable is stamped 2026-08-16 23:56:47 and carries the tab work from
`393d089` (several shells in one window), which the previous archive predated by
a day and a half. That gap is what `Ctrl+T` doing nothing looks like from the
outside, and it is checkable without running anything: this binary has 8
`TerminalTabs` matches in it, the one it replaces has none.

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

**0.1.1 breaks with the consumer path, deliberately, and this is the one thing
to know before cutting the next one.** 0.1.0 was built from the released SDK
bundle alone — the recipe below — and that is still the right way. It cannot be
used here: the fix is in the FRAMEWORK's own sources, and
`starling-sdk-0.3.0-macos-arm64.tar.gz` carries a copy of `TerminalView.swift`
that predates it. Building 0.1.1 the consumer way would have faithfully
reproduced the crash it exists to fix, and said nothing while doing it.

So 0.1.1 was built against this repo's `sdk/`:

    STARLING_APP_VERSION=0.1.1 build/macos-app.sh TerminalApp --zip

which proves the terminal works and does NOT prove the bundle can build it.
**The 0.3.0 SDK bundle ships the bug**, so anything built from it has the
crash; restoring the consumer path means cutting an SDK release with the fix
in it, and the next terminal release should be built from that.

The recipe 0.1.0 used, for when there is a fixed bundle to use it with:

    tar xzf dist/starling-sdk-0.3.0-macos-arm64.tar.gz -C /tmp/sdk
    STARLING_SDK_BUNDLE=/tmp/sdk/starling-sdk-macos-arm64 \
        build/macos-app.sh TerminalApp --zip

Both halves matter. `STARLING_SDK_BUNDLE` redirects the app's path dependency
*and* the `-L`/rpath into the bundle's own `engine/lib`; the script then takes
flutter_assets from `engine/share` instead of this repo's `sdk/Resources`, so
staging never reaches back into a tree a consumer does not have. The build plan
was checked for it: 46 references to the unpacked bundle, zero to
`starling-engine` or to `sdk/`. The archive is renamed on the way in —
`macos-app.sh` emits `Starling-Terminal-<ver>-macos-arm64.zip`, this directory
keeps every artifact at `<product>-<platform>-<arch>` so a version bump
replaces a file instead of accumulating one.

Like the Windows archive, **this is not the binary the macOS numbers were
measured on**: it carries the tab work from `393d089`, where
`docs/perf/terminal-vs-ghostty-macos-2026-08-14-postupgrade/` predates it.
Re-measure before quoting those figures against this archive.

## The Linux terminal's provenance

Built on the dev box from `release-terminal-0.1.0`, **from the released SDK
bundle alone** — the same consumer path the macOS archive takes:

    tar xzf dist/starling-sdk-0.3.0-linux-x86_64.tar.gz -C /tmp/sdk
    B=/tmp/sdk/starling-sdk-linux-x86_64
    env -u STARLING_ENGINE_OUT STARLING_APP_GTK=1 STARLING_SDK_BUNDLE=$B \
        swift build -c release --package-path apps/TerminalApp \
        --scratch-path $PWD/.build-gtk
    STARLING_SDK_BUNDLE=$B build/package-terminal-gtk.sh

`STARLING_SDK_BUNDLE` reaches further here than on the other two platforms,
because a .deb ships licensing as well as code. In bundle mode the packager
takes the engine libraries, `icudtl.dat`, the framework's BSD-3-Clause licence
and the engine's own `NOTICES.Z` from the bundle — the notices especially, since
they must describe the engine actually being shipped, and this repo's copy would
be a different engine's on any machine but ours. All five were compared
byte-for-byte against the bundle after packaging.

**The binary keeps the build machine's bundle path in its RUNPATH, so the test
that matters is the installed package with that bundle gone.** Moved aside, the
installed terminal came up and drew a shell prompt, and `/proc/<pid>/maps`
showed 157 mapped libraries: 17 from `/usr/lib/starling-terminal`, the rest
system, **zero from the bundle and zero from the swiftly toolchain**. The
launcher is what makes that hold — it exports
`LD_LIBRARY_PATH=/usr/lib/starling-terminal`, which outranks the baked RUNPATH.
A package that skipped this check would work on the build machine and nowhere
else.

The throughput suite (`test/bench`) was then run against the installed package
through `STARLING_DEV_SHELL`, so it needed no synthetic input: 418 MB across the
ten workloads in **2.6 s wall / 3.4 s CPU** at a 40x135 grid, ~220 MB RSS
afterwards. One run on a windowed GNOME session — a health check, not a
comparable round; the archived rounds fix the grid and run three times against a
rival terminal.

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

The names carry versions, so a file downloaded from a release says what it is
without being renamed. The DIRECTORY inside each SDK archive does not
(`starling-sdk-macos-arm64/`) — that is what `starling-create` keys its cache
by, so a cache entry is "the SDK for this platform" rather than one directory
per version.

Rebuild as above, copy the artifact here, and regenerate the checksums —
one file, every line at once, because writing it with one filename is how
the Windows zip's line got dropped once already:

    sha256sum starling-sdk-0.3.0-linux-x86_64.tar.gz \
              starling-sdk-0.3.0-macos-arm64.tar.gz \
              starling-sdk-0.3.0-windows-x86_64.zip \
              starling-terminal_0.1.0_amd64.deb \
              starling-terminal-0.1.0-windows-x86_64.zip \
              starling-terminal-0.1.1-macos-arm64.zip > SHA256SUMS

(`shasum -a 256` on the Mac — same format, same file. On Windows,
`Get-FileHash -Algorithm SHA256` and lower-case the hash; write the file with
`[IO.File]::WriteAllText` and LF, since `Out-File` will give it CRLF.)

Replace files rather than adding versions; each version committed costs its
full size in permanent history.
