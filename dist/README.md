# dist — prebuilt downloads carried in the tree

`starling-terminal-0.1.0-windows-x86_64.zip` — Starling Terminal for Windows,
x86_64, the 0.1.0 release candidate. 47.2 MB, 52 entries, checksum in
`SHA256SUMS`.

`starling-terminal-0.2.0-dev-macos-arm64.zip` — Starling Terminal for macOS
arm64, a **preview of the `remote-workspace` branch**, not a release. 17 MB,
checksum in `SHA256SUMS`. It carries what 0.1.0 does not: splits, remote
workspaces with a stored arrangement, the switcher, pane status from OSC 133,
tab keybindings, the floating-pane look, and **⌘/ for the keyboard reference**
— which is the fastest way to see the rest of that list without reading this
file. Same `.app` shape and the same Gatekeeper caveat as the 0.1.0 archive
below.

It sits BESIDE the 0.1.0 release candidate rather than replacing it, which is
a deliberate exception to the "replace, don't accumulate" rule at the bottom of
this file. The rule assumes the new artifact supersedes the old one; this one
does not — 0.1.0 is a cut release that the Windows and Linux archives here are
also part of, and overwriting the macOS third of it would leave two thirds of a
release beside a branch build with nothing to say so. Delete this file when
0.2.0 is actually cut, and the rule resumes.

**Its provenance is weaker than everything else here, on purpose.** The three
0.1.0 terminals were built from the released SDK bundle — the consumer path.
This one is built against the repo's own `sdk/`, because the branch changes the
framework (the OSC 133 accessors in `CTerminalCore`, `TermdDialPacer`, the
palette) and the 0.3.0 bundle predates all of it. Building it the consumer way
would have produced an archive missing the very features it exists to preview,
and it would have done so silently. So this archive proves the branch works; it
does NOT prove the bundle can build the branch. That check comes back when
0.2.0 cuts a matching SDK.

`starling-termd-0.1.0-linux-x86_64` — the session daemon for Linux x86_64.
895 KB, checksum in `SHA256SUMS`. **A bare executable, not an archive**: it is
statically linked against nothing but libc, so `scp` it to a server and run it.
That is the whole point of `make static` in `termd/Makefile` — the far end of a
remote workspace is frequently a machine with no toolchain, and this is the one
file it needs.

    scp dist/starling-termd-0.1.0-linux-x86_64 server:/usr/local/bin/starling-termd
    ssh server starling-termd --list

Versioned 0.1.0 to match the terminal it serves, though the number that governs
compatibility is the wire version in `termd/protocol.h` (currently **2**) —
a client and daemon disagreeing on that fail the `HELLO` with a clear error
rather than misbehaving.

`starling-terminal-0.1.0-macos-arm64.zip` — Starling Terminal for macOS arm64, the
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
Windows zip). These eight are in the tree by explicit request, each so that a
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

Built on the Mac from `release-terminal-0.1.0`, **from the released SDK
bundle alone** — the consumer path, not a privileged in-repo one:

    tar xzf dist/starling-sdk-0.3.0-macos-arm64.tar.gz -C /tmp/sdk
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

## The 0.2.0-dev preview's provenance

Built on the Mac from `remote-workspace` at `17b9bd4`, against this repo's
`sdk/` rather than a released bundle — see the entry at the top for why, and
for what that costs in assurance:

    STARLING_APP_VERSION=0.2.0-dev build/macos-app.sh TerminalApp --zip

Checked the way the release archives are: unpacked to an empty directory and
launched from there under `env -i` with only `HOME`, `SHELL` and a minimal
`PATH` — it came up, split into panes, and drew shells. The engine rides in
`Contents/Frameworks` and every rpath resolves inside the bundle, unchanged
from the 0.1.0 archive. Ad-hoc signed and not notarized, so the same
right-click → Open applies.

It was also checked for staleness before shipping, which is worth stating
because a `.app` gives no clue: the executable carries six `_helpOverlay` /
`_isHelpChord` symbols and the OSC 133 accessors from `CTerminalCore`, and
`strings` finds the help text itself (`split left | right`, `esc closes`). A
build against a stale SDK scratch would have none of it and would have looked
identical. Opening ⌘/ in the unpacked copy was the last check.

**No numbers were measured on this binary**, and it is a branch preview rather
than a release candidate — do not quote it against the archived perf rounds.

## The Linux termd's provenance

Built on a Ubuntu x86_64 box (`starling@lenovo`, kernel 7.0, gcc) from the
same `56f2089`, and it is the binary that was tested there rather than a
rebuild of it — `dist/starling-termd-0.1.0-linux-x86_64` and the tested file
share the checksum `c07b8167…`:

    make -C termd clean && make -C termd static && strip termd/starling-termd
    python3 termd/test-termd.py        # the full protocol suite, on that host

The suite passes on the target platform, which is the check that matters for
this artifact: it exercises sessions outliving their client, `KILL` and the
lifecycle, workspace membership, ring eviction and the version gate, all
against this exact executable. `file` reports it statically linked, so the
server it lands on needs no libc version, no toolchain and no Swift.

It is the only artifact here built on the machine it targets. The other Linux
binary in this directory (the .deb) was built on the dev box, which is also
Ubuntu; termd is built wherever a Linux host is available because it depends
on nothing that could differ.

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
one file, all eight lines, because writing it with one filename is how the
Windows zip's line got dropped once already:

    sha256sum starling-sdk-0.3.0-linux-x86_64.tar.gz \
              starling-sdk-0.3.0-macos-arm64.tar.gz \
              starling-sdk-0.3.0-windows-x86_64.zip \
              starling-termd-0.1.0-linux-x86_64 \
              starling-terminal_0.1.0_amd64.deb \
              starling-terminal-0.1.0-macos-arm64.zip \
              starling-terminal-0.1.0-windows-x86_64.zip \
              starling-terminal-0.2.0-dev-macos-arm64.zip > SHA256SUMS

`shasum -a 256 -c SHA256SUMS` re-checks every line afterwards, which is worth
doing: a wrong hash here is indistinguishable from a corrupted download.

(`shasum -a 256` on the Mac — same format, same file. On Windows,
`Get-FileHash -Algorithm SHA256` and lower-case the hash; write the file with
`[IO.File]::WriteAllText` and LF, since `Out-File` will give it CRLF.)

Replace files rather than adding versions; each version committed costs its
full size in permanent history.
