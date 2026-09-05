# dist — prebuilt downloads carried in the tree

`StarlingSetup-0.2.0.exe` and `Starling-0.2.0-win-x64.zip` — the Starling
shell for Windows 11 and Windows 10, x86_64: dock, Start menu, desktop, file
manager and tray, the thing the site's Windows page films. 39.3 / 39.7 MB,
checksums in `SHA256SUMS`, both produced by `build/win/package-shell.ps1` —
the single definition of what a Windows install contains — from branch
`release-winshell-0.2.0` (commit in `BUILD-STAMP.txt` inside; engine pinned
by the same branch name in starling-engine). The exact `WinShellBar.exe` in
both passed the 28-check shell gate twice: installed from this very setup
exe on a clean Windows 11 VM that has never had a toolchain on it
(`test/win/run-gate-vm.sh --install`), and on a Windows 10 22H2 VM under
Hyper-V.

**0.2.0 over 0.1.0.** It runs on Windows 10 — same binary, same look; the
dock's icons start in the corner there, as Windows 10's own do. The four
issues from the first outside reporter are closed (#26–#29: the taskbar
alignment follows Windows' own setting, the bar has its own right-click
menu, an app launched from the dock comes up in front, a new dock seeds
from the taskbar pins you already had). Minimized windows are parked off
screen by the setting that actually decides it, on both Windows. A profile
that never set a wallpaper gets the theme's. The desktop stays painted when
an explorer starts beside the shell. And Windows 10's explorer no longer
crashes at logon: that was a message of ours reaching its taskbar before the
taskbar was built.

The setup exe is the zip plus a one-line bootstrap: double-click, and it
installs to `%LOCALAPPDATA%\Programs\Starling` and registers, effective at
the next sign-in. The zip is the same payload with the options:
`Install.ps1` (`-Now`, `-NoRegister`, `-Destination`), `Uninstall.ps1`
(`-KeepFiles`), and `WinShellBar.exe --restore-taskbar` as the recovery
path. Install, uninstall, and what-if-it-breaks in full:
`docs/WINDOWS-INSTALL.md`. The 0.1.0 artifacts are removed rather than kept
beside these; they remain `winshell-v0.1.0` release assets.

Unsigned, deliberately for now: SmartScreen will warn on first run, and a
machine with Smart App Control enforcing will refuse it. The
signing plan exists (`docs/WINDOWS-SIGNING.md`) and 0.2.0 ships before it.

`starling-terminal-0.2.0-windows-x86_64.zip` — Starling Terminal for Windows,
x86_64. 45.3 MB, 52 entries, checksum in `SHA256SUMS`. It replaces the 0.1.1
archive, which remains a `terminal-v0.1.1` release asset. Built from branch
`release-terminal-0.2.0`, engine pinned by the same branch name in
starling-engine, staged by `sdk/tools/stage-windows.ps1` (the single
definition of the Windows layout): the exe beside its 35 DLLs — the Swift
runtime, the two engine libraries, and conpty — with `OpenConsole.exe`, the
engine's `data\`, and the font and icon bundles.

**0.2.0 is a real release here, not a rebuild.** It carries the same features
as the other platforms — remote workspaces (splits that live on the server, a
switcher, reconnect), the C emulator core, tabs, the find bar, font zoom and
auto-answer — plus the two fixes that landed last: vim's search is no longer
underlined (a keyboard-protocol control the core was reading as a text
attribute), and a dropped connection no longer ends a remote session (the
daemon ignored the hangup and died with it). Verified rendering a PowerShell
prompt on Windows 11.

`starling-terminal-0.1.1-macos-arm64.zip` — Starling Terminal for macOS arm64.
16 MB, checksum in `SHA256SUMS`. Unlike the Windows archive it wraps a `.app`,
so it extracts to `Starling Terminal.app` rather than flat, and needs no
directory made for it.

**0.1.1 is 0.1.0 plus two fixes, both of which made the shipped macOS archive
work only on the machine that built it.** No feature changed. Linux and Windows
could not hit either bug and are rebuilt anyway, so all three archives now carry
one version and one SDK — there is no version skew left in this directory.

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

`starling-terminal-0.2.0-dev-macos-arm64.zip` — Starling Terminal for macOS
arm64, a **preview of mainline**, not a release. 17 MB, checksum in
`SHA256SUMS`. It carries what 0.1.0 does not: splits, remote workspaces with a
stored arrangement, the switcher, pane status from OSC 133, tab keybindings,
the floating-pane look, and **⌘/ for the keyboard reference** — which is the
fastest way to see the rest of that list without reading this file. Same `.app`
shape as the 0.1.0 archive below, and the same Gatekeeper caveat, but **its
signature survives a plain `unzip`** where 0.1.0's does not (see that entry).

Rebuilt 2026-09-02 from `main` (d44ef9b), against the release engine
(`host_release_arm64`). Everything on mainline since the previous refresh
rides along — most visibly the terminal's **auto-answer** rules, which watch
for a prompt and can type the reply for you, after giving you ten seconds to
do it yourself.

The list below was written for the 2026-08-19 refresh and has not been
extended; it still describes what that build added over 0.1.0, all of which
this one also carries. Rebuilt 2026-08-19 from `main` (the
`remote-workspace` branch it previewed has since merged), three things were
new then, and one of them is why that build existed:

- **⌘+ / ⌘− change the type size**, ⌘0 returns to 13 pt, and the size is
  remembered in `~/.local/state/starling-terminal-font` — one line you can
  edit or delete. `Ctrl+Shift+=` / `Ctrl+Shift+-` / `Ctrl+Shift+0` do the same
  on every platform. The grid re-fits around the new cell, so the window keeps
  its size and the column count moves.

- **⌘⇧R writes a rendering report** — two files at the top of your home
  folder, a `.txt` of what the terminal believed was on screen (plus fonts,
  cell metrics and which glyph path drew them) and a `.png` of that same frame
  as it was painted, recorded inside the app rather than captured from the
  display. Send both when the terminal draws the wrong thing: between them
  they say *which half* is wrong, which a photograph cannot. See the User
  Guide's "When the terminal draws the wrong thing".
- ⌘V and ⌘C now work in the two fields that had no clipboard at all: the ⌘O
  workspace switcher, where a destination usually arrives from one (a hostname
  or a whole `ssh` line), and the ⌘F find bar, where the search term does. In
  the find bar ⌘C copies the **match** you are standing on rather than the
  query — find it, then copy it, is what a person is usually doing.

The app identifies itself as `0.2.0-dev` in that report, and the report also
carries the executable's build time, so a report can always be tied back to a
particular archive.

### Gatekeeper, and what "known developers only" actually blocks

This bundle is **ad-hoc signed**: valid, self-consistent, and from nobody.
`codesign --verify --deep --strict` passes; `spctl -a -t exec` says `rejected`,
and will keep saying it however the archive is built. Under *App Store and
identified developers* that matters only where macOS applies it — **on the
quarantine flag**, which a browser sets on a download and nothing else does:

- **Cloned, `scp`'d, or unzipped in a terminal** — no quarantine, launches with
  no prompt. Checked here.
- **Downloaded in a browser** — quarantined, and refused on first launch. Use
  right-click → **Open**, or Privacy & Security → **Open Anyway**, or clear it
  once, which is the whole of the workaround:

      xattr -dr com.apple.quarantine "Starling Terminal.app"

None of that requires weakening the machine's setting, and none of it is a
build change. **Making it launch like any other app means a "Developer ID
Application" certificate and notarization** — a paid Apple Developer
membership; an "Apple Development" certificate is for running on your own
devices and cannot be notarized. `build/macos-app.sh` already takes the signing
half through `STARLING_MACOS_IDENTITY`; the `notarytool submit` / `stapler
staple` half is not written, because there is no certificate here to test it
against.

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

**Its signature does not survive a plain `unzip`, and 0.2.0-dev's does.**
`ditto -c -k` without `--sequesterRsrc` stores each file's extended attributes
(everything here picks up `com.apple.provenance`) as AppleDouble, and command
-line `unzip` materializes those as real `._Foo` files *inside* the bundle —
63 of them, including `Contents/_CodeSignature/._CodeResources`. codesign then
says `a sealed resource is missing or invalid`. Finder's Archive Utility
understands AppleDouble and unpacks it correctly, so this is invisible to
anyone who double-clicks and fatal to anyone who does not. `build/macos-app.sh`
now strips xattrs before sealing, sequesters what is left into `__MACOSX/`, and
**verifies the archive after a plain unzip rather than the bundle it built** —
which is why this went unnoticed: the old check ran on the staged tree, on the
near side of the round trip that does the damage. This archive predates that
fix and still has it; unpack it with `ditto -x -k` (or Finder) if the signature
matters, and it is fixed in whatever replaces it.

Opening it needs no command and no arguments — verified by running the
unpacked app under `env -i` with the SDK bundle it was built against moved
away: the engine rides in `Contents/Frameworks`, every rpath resolves inside
the bundle, and a Finder launch picks up the login shell. The one first-launch
step is Gatekeeper's: the bundle is **ad-hoc signed, not notarized**
(`spctl` rejects it once a browser has set the quarantine flag), so a
downloaded copy wants right-click → Open, or Privacy & Security →
**Open Anyway**, or `xattr -dr com.apple.quarantine` once. Removing that step
means Developer ID signing plus notarization, not a build change.

`starling-terminal_0.2.0_amd64.deb` — Starling Terminal for Linux x86_64.
54 MB, checksum in `SHA256SUMS`. It replaces the 0.1.1 .deb, which remains a
`terminal-v0.1.1` release asset. Built from branch `release-terminal-0.2.0`
(engine pinned by the same branch name in starling-engine) in the windowed
GTK configuration, packaged by `build/package-terminal-gtk.sh` — which links
the engine's two GTK libraries, computes the system dependencies with
`dpkg-shlibdeps`, and installs onto the applications menu with its icon.

**0.2.0 is a feature release**: remote workspaces (server-side splits, a
switcher, reconnect), the C emulator core and its read path, tabs, the find
bar, ⌘±  font zoom, auto-answer rules, and the two disconnect fixes — vim's
search no longer underlined, and a dropped connection no longer ending a
remote session. Installs with `sudo dpkg -i` (or `apt install ./…`) on any
desktop — GNOME, KDE, Wayland or X11 — and `dpkg -i` treats it as the upgrade
it is.

**Rebuilt on the respun SDK bundle**, and this is not paperwork. The first cut
of this .deb was built on the 0.3.1 bundle that searched for `<name>.bundle`,
so it shipped with none of its own fonts — Roboto Mono and DejaVu Sans Mono
never loaded, which is the box-drawing and braille every TUI frame is made of,
on top of cell metrics measured from a face that was not there. It started and
drew text, so nothing failed. What found it was `strace`: 2611 opens and not
one of them a bundled font. The rebuild opens all five, checked the same way
and again after installing with the SDK bundle moved off the machine. A **.deb**
rather than an archive, because Linux has an install path the other two do not:
`sudo dpkg -i` (or `apt install ./…`) puts it on the applications menu with its
icon, and `dpkg-shlibdeps` computed the system dependencies so a missing GTK or
libinput is a package error rather than a crash on launch. It runs on any
desktop — GNOME, KDE, Wayland or X11 — and installs cleanly beside the desktop
package, sharing nothing with it.

Everything it loads lives in `/usr/lib/starling-terminal`: the engine libraries,
`libFlutterShared`, the Swift runtime closure, the font resource bundles and
`data/icudtl.dat`. No flutter_assets — the Swift runtime never reads them.

`starling-sdk-0.3.1-macos-arm64.tar.gz` — the Starling SDK for macOS arm64:
framework source plus the release engine binaries (`FlutterMacOS.framework`,
`libswift_bridge.dylib`) and flutter_assets, in one tree a consumer depends on
by path. 14 MB, checksum in `SHA256SUMS`.

**0.3.1 is one source fix on top of `terminal-v0.1.0`** — the commit the
shipped terminal was built from, which is the tree this has to fix — and the
**same engine as 0.3.0, byte for byte**: both binaries were compared against
the ones inside the 0.3.0 tarball and are identical.

0.3.0 shipped a `TerminalView.swift` and `CupertinoIcons.swift` that reached
the framework's fonts through SwiftPM's `Bundle.module`, whose fallback
candidate is **an absolute path into whatever build directory compiled it**.
Inside a `.app` that is the only candidate that resolves, so an app built on
0.3.0 runs on the machine that built it and dies at startup everywhere else
with `resource_bundle_accessor.swift:12: could not load resource bundle`.
Because this bundle ships source rather than a compiled library, every consumer
recompiled the bug into their own binary with their own path baked in.

Demonstrated rather than asserted: `CounterApp` built as a path-dependency
consumer from an unpacked 0.3.0 carries **two** such paths; from this bundle it
carries **none**. Compiling is not the test — a 0.3.0 consumer compiles
perfectly and crashes on somebody else's machine.

The bug cannot bite on Linux or Windows: `Bundle.module`'s first candidate is
correct in their layouts, where a bare executable's `bundleURL` is the directory
holding the resource bundle, so the fallback is never reached. **Both are
reissued at 0.3.1 anyway**, and neither reissue is a fix for its own platform.
The reason is that these bundles ship *source*: leaving a platform at 0.3.0
publishes the same framework in two different states, and "which SDK version am
I on" then needs a per-platform answer every time it is asked. All three now
carry one version, which is worth more than the re-download it cost.

`starling-sdk-0.3.1-linux-x86_64.tar.gz` — the same SDK for Linux x86_64, the
same branch and the same engine commit: framework source, the three release
engine libraries (`libflutter_engine.so`, `libflutter_linux_gtk.so`,
`libflutter_linux_drm.so`), `icudtl.dat` and flutter_assets. 23 MB, checksum in
`SHA256SUMS`. It **replaces** the 0.3.0 Linux tarball, which was in this
directory until now and remains a `sdk-v0.3.0` release asset.

It reissues a fix that changes nothing on this platform, on purpose: the search
runs here too, it simply never had to. Shipping it means "which SDK version am I
on" has one answer instead of one per platform. The Windows zip below was cut on
the Windows box for the same reason and in the same window, so this directory
carries no version skew at all.

`starling-sdk-0.3.1-windows-x86_64.zip` — the same SDK for Windows x86_64, the
same 0.3.1 source and the same engine commit: framework source, both
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
    Expand-Archive dist\starling-sdk-0.3.1-windows-x86_64.zip -DestinationPath C:\sdk031f
    $env:STARLING_SDK_BUNDLE = "C:\sdk031f\starling-sdk-windows-x86_64"

    sdk\tools\build-windows.ps1 -PackagePath apps\TerminalApp `
        -Product TerminalApp -Configuration release
    sdk\tools\stage-windows.ps1 -PackagePath apps\TerminalApp `
        -Product TerminalApp -Configuration release -Zip `
        -Out C:\dist\rel\starling-terminal-windows-x86_64 `
        -EngineOut $env:STARLING_SDK_BUNDLE\engine\lib

That is the zip in this directory, checked rather than assumed: its sha256 was
compared against the `SHA256SUMS` line beside it (`bffea87b`) before unpacking,
so what the terminal links is provably the artifact the SDK release ships and
not a local bundle that happens to be lying around.

`FLUTTER_SWIFT_ENGINE_OUT` and `STARLING_ENGINE_OUT` must be unset for this to
mean anything. With either set — or with `STARLING_SDK_BUNDLE` unset on a box
that has an engine checkout — the manifest's own `-L` finds the checkout and
the build passes while proving nothing. The check is the build plan
(`apps/TerminalApp/.build/release.yaml`): **830 references to the unpacked
bundle, zero to `starling-engine`, zero to this repo's `sdk/`**. Both engine
DLLs and `data/icudtl.dat` in the staged tree were then compared byte for byte
with the bundle's copies: identical. `conpty.dll` and `OpenConsole.exe` came out
of its `Vendor/conpty` the same way (engine `ea78543`, unchanged since 0.3.0).

**And it was run, which is the check that mattered.** The first 0.3.1 bundle
produced a terminal that started, drew, and spawned a shell while rendering
every glyph in the system's proportional font on monospace cells — the
framework's font search looked for `<name>.bundle` when this platform stages
`<name>.resources`, and that search returns nil rather than trapping. No error,
no log line, nothing in the archive to inspect: it is visible only in a
screenshot, beside a correct one. Compare against the 0.1.0 archive if this is
ever in doubt — the tell is whether `Copyright (C) Microsoft Corporation` has
even advances, and whether the line wraps mid-word at the cell boundary.

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

**0.1.1 is built the consumer way, from the SDK bundle beside it in this
directory** — `starling-sdk-0.3.1-macos-arm64.tar.gz`, which is why that
bundle and this archive are on the same branch. It was briefly not: the fix
lives in the FRAMEWORK's sources, and the 0.3.0 bundle carried a
`TerminalView.swift` that predated it, so building 0.1.1 from 0.3.0 would have
faithfully reproduced the crash it exists to fix and said nothing while doing
it. The first 0.1.1 archive was therefore built against this repo's own `sdk/`
and shipped with that stated as a weakness. SDK 0.3.1 removed the reason, and
this archive is the rebuild.

The check that the build really was a consumer's is the build plan, not the
command line: it carried **45 references to the unpacked bundle and zero to
`starling-engine` or to this repo's `sdk/`**. With `STARLING_ENGINE_OUT` or
`FLUTTER_SWIFT_ENGINE_OUT` set, the manifest's own `-L` finds an engine
checkout and the build passes while proving nothing, so both were cleared.

The engine inside the `.app` is the bundle's, compared by **Mach-O UUID**
rather than by hash — the app re-signs `FlutterMacOS.framework` and
`libswift_bridge.dylib` on the way in, so their bytes differ from the bundle's
copies while the code is identical. Comparing hashes there reports a false
mismatch, which is exactly what it did the first time.

The recipe:

    tar xzf dist/starling-sdk-0.3.1-macos-arm64.tar.gz -C /tmp/sdk
    env -u STARLING_ENGINE_OUT -u FLUTTER_SWIFT_ENGINE_OUT \
        STARLING_SDK_BUNDLE=/tmp/sdk/starling-sdk-macos-arm64 \
        STARLING_APP_VERSION=0.1.1 build/macos-app.sh TerminalApp --zip

Both halves matter. `STARLING_SDK_BUNDLE` redirects the app's path dependency
*and* the `-L`/rpath into the bundle's own `engine/lib`; the script then takes
flutter_assets from `engine/share` instead of this repo's `sdk/Resources`, so
staging never reaches back into a tree a consumer does not have. The build plan
was checked for it, as recorded above: 45 references to the unpacked bundle,
zero to `starling-engine` or to `sdk/`. The archive is renamed on the way in —
`macos-app.sh` emits `Starling-Terminal-<ver>-macos-arm64.zip`, this directory
keeps every artifact at `<product>-<platform>-<arch>` so a version bump
replaces a file instead of accumulating one.

Like the Windows archive, **this is not the binary the macOS numbers were
measured on**: it carries the tab work from `393d089`, where
`docs/perf/terminal-vs-ghostty-macos-2026-08-14-postupgrade/` predates it.
Re-measure before quoting those figures against this archive.

## The Linux terminal's provenance

Built on the dev box from `release-terminal-0.1.1`, **from the released SDK
bundle alone** — the same consumer path the macOS archive takes:

    tar xzf starling-sdk-0.3.1-linux-x86_64.tar.gz -C /tmp/sdk
    B=/tmp/sdk/starling-sdk-linux-x86_64
    env -u STARLING_ENGINE_OUT STARLING_APP_GTK=1 STARLING_SDK_BUNDLE=$B \
        swift build -c release --package-path apps/TerminalApp \
        --scratch-path $PWD/.build-gtk
    STARLING_SDK_BUNDLE=$B build/package-terminal-gtk.sh

**Its engine came out of the bundle, and the bundle's came out of the published
0.3.0 tarball** — not from the shared `host_release`, which by then had been
relinked three commits past the release commit and carries
`fl_drm_view_inject_pointer_abs`. `libflutter_engine.so`,
`libflutter_linux_gtk.so` and `data/icudtl.dat` in the .deb are byte identical
to the bundle's, and neither has a single match for that symbol.

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

Built on the Mac from `remote-workspace` at `3543acc`, against this repo's
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

The macOS one (0.3.1) was built on the Mac from `release-sdk-0.3.1`, which is
**`terminal-v0.1.0` plus the one source fix** — based there rather than on
`main` or on the `sdk-v0.3.0` tag because the terminal 0.1.0 people actually
have was built from that commit, so that is the tree an SDK patch has to
correct. Basing it on main would have swept in every unrelated change since and
made "0.3.0 plus one fix" untrue.

    sdk/tools/make-bundle.sh --release "$PWD/.stage-sdk"

**The engine claim is checked, not assumed.** Both engine binaries in the new
tarball were compared byte for byte against the ones inside
`starling-sdk-0.3.0-macos-arm64.tar.gz` and are identical — a stronger
statement than naming a commit, because the out-directory is shared and can be
rebuilt by somebody else's branch underneath you (the failure warned about
below).

Verified the way the bug it fixes demanded: unpacked to a clean directory, then
`CounterApp` built as a path-dependency consumer with `STARLING_ENGINE_OUT`,
`FLUTTER_SWIFT_ENGINE_OUT` and `STARLING_SDK_BUNDLE` all cleared, so the link
had only the bundle's own `engine/lib` to resolve against. The check on the
result is one `strings` call: built from **0.3.0** the binary carries two
absolute build-directory paths, built from this bundle it carries none.

The Linux one (0.3.1) is the same branch and the same engine commit, built on
the dev box and verified the same way — a path-dependency consumer compiled the
whole framework, `readelf -d` showed both engine libraries resolving out of the
bundle's `engine/lib` with nothing set in the environment, and it carries zero
build-directory paths where a 0.3.0 consumer carries two:

    FLUTTER_SWIFT_ENGINE_OUT=<a private copy of the release binaries> \
        sdk/tools/make-bundle.sh --release "$PWD/.stage-sdk"

**Its engine did not come from `host_release`, and could not have.** All four
files were taken out of the published `starling-sdk-0.3.0-linux-x86_64.tar.gz`
and compared byte for byte with what shipped: identical. Read straight from the
shared out directory they would not have been — that copy of
`libflutter_engine.so` had been relinked from `starling`, three commits past the
release, and carries `fl_drm_view_inject_pointer_abs`. The reissued tarball has
zero matches for it. This is the same failure the paragraph below warns about,
caught the second time by taking the binaries from the artifact instead.

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

**All three 0.3.1 bundles are respun for the font-search fix (`b400add`), and
the version number does not move.** 0.3.1 shipped a resource-bundle search that
looked for `<name>.bundle`, the Darwin spelling, where SwiftPM stages
`<name>.resources` on Linux and Windows — so a terminal built on those two
bundles came up with no bundled fonts, drawing the system's proportional face on
monospace cells. Keeping the number is deliberate and only defensible because
the release was minutes old with nobody on it: the published `SHA256SUMS` is
replaced in the same pass, so no checksum anyone recorded can disagree with what
the release carries. The macOS bundle is respun for source consistency alone —
`.bundle` is correct there and its behaviour never changed.

The Windows one (0.3.1) was rebuilt on the Windows box from `release-sdk-0.3.1`
against a `host_release` engine at `ea78543` — the same commit the other two
carry, and the same commit `release-sdk-0.3.1` in starling-engine points at, so
all three bundles still ship one engine. The engine checkout on that box is not
shared with anyone and its tree was clean at `ea78543`, so the snapshot dance
above was not needed here. `sync-vendored-headers.sh --check` passed against
that engine, which is the header-ABI half of the same guarantee:

    sdk\tools\make-bundle.ps1 -Configuration release `
        -EngineOut <engine>\engine\src\out\host_release `
        -OutDir <repo>\.stage-sdk

**The engine claim is checked here too, and it is the stronger check**: all five
engine artifacts in this zip — both DLLs, both import libraries and
`icudtl.dat` — were compared byte for byte against the ones inside
`starling-sdk-0.3.0-windows-x86_64.zip` and are identical. `diff -rq` between
the two unpacked zips then names the whole difference, which is **four files**:
`TerminalView.swift` and `CupertinoIcons.swift` (the fix) plus
`tools/starling-create` and `tools/stage-windows.ps1`, which the 0.3.0 zip
predates — the scaffolder's Windows support and versioned asset names, and
`stage-windows.ps1` accepting a bundle's split `engine\lib` / `engine\share`
layout. That is a property of the artifacts rather than a claim about a branch.

Verified the way the other two were: unpacked to a clean directory and built
with nothing in the environment pointing at an engine checkout
(`FLUTTER_SWIFT_ENGINE_OUT`, `STARLING_ENGINE_OUT` and `STARLING_SDK_BUNDLE`
all cleared), so the link had only the bundle's own `engine/lib` to resolve
against. `tools\build-windows.ps1 -PackagePath . -Configuration release`
compiled the whole framework and all three example executables —
`CounterApp.exe`, `TerminalDemo.exe` and `TerminalTiling.exe` — in 360 s with
no errors. A bundle missing an import library fails that at link time, which is
the failure this catches. The 0.3.1-specific check ran on the results as well:
none of the three carries a `.build`-directory resource-bundle path, which is
what the macOS fix is about and is now true of the Windows binaries by
construction rather than by luck.

The zip was then re-cut once, to pick up `starling-create`'s per-platform
release table (a split release — macOS and Windows at 0.3.1, Linux at 0.3.0 —
is not something one `SDK_VERSION` can address). `diff -rq` between the two
cuts names one file, `tools/starling-create`, so every Swift source the
verification above compiled is byte for byte the same in the artifact that
shipped. The macOS and Linux tarballs still carry the older copy of that
script and are not re-cut for it: the copy in a bundle's `tools/` is a
convenience snapshot, and the canonical one is the release asset.

**Unpack it somewhere with a short path.** The first attempt at that clean
build was made under a deep scratch directory and died in SwiftPM with
`Error Domain=NSCocoaErrorDomain Code=514 "The file name is invalid"` and
`Win32Error(code: 206)` — `ERROR_FILENAME_EXCED_RANGE`, i.e. MAX_PATH, hit
while creating `…/FlutterSwiftPackageDiscoveredTests.build/include`. It reads
as a corrupt-bundle error and is nothing of the kind; the same zip built
cleanly from `C:\sv`. Relatedly, the build ends with a `Win32Error(code: 1314)`
warning about the `.build\release` symlink — that is Windows refusing symlink
creation without Developer Mode, not a build failure, and the executables are
under `.build\x86_64-unknown-windows-msvc\release\`.

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

    sha256sum starling-sdk-0.3.1-linux-x86_64.tar.gz \
              starling-sdk-0.3.1-macos-arm64.tar.gz \
              starling-sdk-0.3.1-windows-x86_64.zip \
              starling-termd-0.1.0-linux-x86_64 \
              starling-terminal_0.1.1_amd64.deb \
              starling-terminal-0.1.1-macos-arm64.zip \
              starling-terminal-0.1.1-windows-x86_64.zip \
              starling-terminal-0.2.0-dev-macos-arm64.zip > SHA256SUMS

`shasum -a 256 -c SHA256SUMS` re-checks every line afterwards, which is worth
doing: a wrong hash here is indistinguishable from a corrupted download.

(`shasum -a 256` on the Mac — same format, same file. On Windows,
`Get-FileHash -Algorithm SHA256` and lower-case the hash; write the file with
`[IO.File]::WriteAllText` and LF, since `Out-File` will give it CRLF.)

Replace files rather than adding versions; each version committed costs its
full size in permanent history.
