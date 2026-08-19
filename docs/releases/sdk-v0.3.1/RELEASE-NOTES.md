# Starling SDK 0.3.1 — apps built on it now run on other people's machines

One source fix, cut on top of **`terminal-v0.1.0`** — the commit the shipped
terminal was built from. The engine is unchanged, byte for byte the same
binaries 0.3.0 carries, and no API moved. macOS and Windows ship at 0.3.1;
Linux is not reissued and stays at 0.3.0, for a reason below.

If you have shipped a macOS `.app` built on 0.3.0, it very likely crashes for
everyone except you, and this is the release that fixes it.

## What was wrong

An app built on 0.3.0 dies at startup on any machine but the one that compiled
it:

    Flutter/resource_bundle_accessor.swift:12: Fatal error:
    could not load resource bundle

The framework reached its bundled fonts through SwiftPM's generated
`Bundle.module`, which has exactly two candidates: the app bundle's own
directory, and **an absolute path into the build directory that produced the
binary**. Inside a `.app` the first misses — `Bundle.main.bundleURL` is the
`.app` itself, while resource bundles are staged under `Contents/Resources/`
where app resources belong. The second resolves only where it was built.
Everywhere else both miss, and the accessor is a `static let` ending in
`fatalError`, so it does not degrade: it traps, on the first font load, which
is startup.

**Because this SDK ships source rather than a compiled library, every consumer
recompiled the bug into their own binary with their own path baked in.** That
is what makes it an SDK release rather than an app fix: nothing written on top
of 0.3.0 could have avoided it.

It also survives the obvious test. Unpacking your app and running it on the
machine that built it exercises the one path that exists there. The giveaway is
`strings` on the executable finding a home directory that should not be in a
binary at all.

## What changed

`TerminalFontLoader` and `CupertinoIcons` now **search** for their resource
bundles — `Contents/Resources` for a macOS app, `Bundle.main.bundleURL` and the
executable's own directory for the Linux and Windows layouts — and return
nothing rather than trapping when none is found. A terminal drawing with the
system's fonts is degraded; one that refuses to start is not usable at all.

`CupertinoIcons` had the same bug one target over, and would have surfaced the
moment the first was fixed. Its hand-written "fallback: search relative to
executable" could never run: reaching `Bundle.module` to discover it had failed
is itself the trap.

## Why macOS and Windows, and not Linux

The bug is a macOS one. `Bundle.module`'s first candidate is *correct* on Linux
and Windows, where a bare executable's `Bundle.main.bundleURL` is the directory
the executable sits in — which is exactly where the resource bundle is staged.
The fallback is never reached there, so nothing on those two platforms was ever
broken by it.

The Windows bundle is still reissued at 0.3.1, because the two files this
release changes are files a Windows consumer compiles as well: the bundles ship
source, so leaving Windows at 0.3.0 would mean two published bundles with the
same framework in two different states. That is a bookkeeping cost paid by
everyone who reads them and bought nothing.

Diffing the two unpacked zips says exactly what moved, and it is **four files,
not two**. `TerminalView.swift` and `CupertinoIcons.swift` are the fix.
`tools/starling-create` and `tools/stage-windows.ps1` came along because the
0.3.0 zip was cut before them: the scaffolder learned Windows and versioned
asset names, and `stage-windows.ps1` learned to stage against an SDK bundle's
split `engine\lib` / `engine\share` layout instead of demanding a flat engine
out-directory. Everything else — every other source file, and all five engine
artifacts — is byte for byte what 0.3.0 shipped.

Linux stays at 0.3.0 on the same reasoning read the other way: it is the one
bundle nobody has to think about, and moving its version would cost every
consumer a 23 MB re-download for a difference they cannot observe. The three
bundles are therefore deliberately not all one version.

## `starling-create` had to learn that

A split release is not something the scaffolder could express. It carried one
`SDK_VERSION` feeding both the tag and the asset name, so with macOS and Windows
at 0.3.1 it would have composed
`sdk-v0.3.1/starling-sdk-0.3.1-linux-x86_64.tar.gz` for every Linux user — an
asset that does not exist and never will. The failure is a 404 at the download,
which is at least loud, but it is a release that cannot be installed on a third
of its platforms.

It now holds one version per platform and **derives the tag from it**, which
keeps the invariant that matters: a bundle is served from the release named by
its own version. Linux resolves to `sdk-v0.3.0`, where its unchanged tarball has
been all along; macOS and Windows resolve to `sdk-v0.3.1`. The release a *user*
downloads the tool from is tracked separately, because that is a different
question — the tool is one asset on one release whatever mix of bundles that
release reissued.

Checked by composing all three URLs and asking GitHub: Linux answers **200**
today, and the two 0.3.1 assets answer **404** against the tag this release has
not created yet, which is the shape you want to see before cutting it.

The copy of the tool inside each bundle's `tools/` is a convenience snapshot;
the canonical one is the release asset. The macOS and Linux tarballs were built
before this change and carry the older copy, and are not re-cut for it — the
Windows zip carries the new one only because it was being cut anyway.

## Upgrading

Repoint your path dependency at the unpacked 0.3.1 tree; nothing else changes.
No API moved, so a rebuild is the whole upgrade.

    tar xzf starling-sdk-0.3.1-macos-arm64.tar.gz -C /opt

On Windows, the same repoint against the 0.3.1 zip. The directory inside it is
still `starling-sdk-windows-x86_64`, unversioned, so a path dependency written
against 0.3.0 needs no edit at all — unpack over it:

    Expand-Archive starling-sdk-0.3.1-windows-x86_64.zip -DestinationPath C:\

Then confirm the fix took, which takes one command:

    strings <your.app>/Contents/MacOS/<exe> | grep '\.build.*\.bundle'

Empty output is the fix. Anything printed is a path that exists only on your
machine, and the app will trap at startup wherever that path does not exist.

## Verification

Built from `release-sdk-0.3.1` — that branch in this repo and in
starling-engine is the record of what this came from. It is `terminal-v0.1.0`
plus the fix and nothing else, deliberately: basing a patch on `main` would
have swept in every unrelated change since 0.3.0 and made "0.3.0 plus one fix"
untrue.

The engine claim was checked rather than asserted — both binaries in the
tarball were compared byte for byte against the ones inside the 0.3.0 tarball
and are identical. That is stronger than naming a commit, because the engine
out-directory is shared and can be rebuilt underneath you.

The fix was checked the way the bug demanded. `CounterApp` was built as a
path-dependency consumer from a clean unpack, with `STARLING_ENGINE_OUT`,
`FLUTTER_SWIFT_ENGINE_OUT` and `STARLING_SDK_BUNDLE` all cleared so the link
had only the bundle's own `engine/lib` to resolve against. Built from **0.3.0**
that binary carries two absolute build-directory paths; built from **0.3.1** it
carries none. Compiling successfully is not the test — a 0.3.0 consumer
compiles perfectly and crashes on somebody else's machine.

The Windows zip got the same treatment on the Windows box, and its engine claim
is the stronger of the two: all five engine artifacts in it — `flutter_engine.dll`,
`flutter_windows.dll`, both `.dll.lib` import libraries and `icudtl.dat` — were
compared byte for byte against the ones inside
`starling-sdk-0.3.0-windows-x86_64.zip` and are identical, so the two bundles
differ only in the four files listed above. It was unpacked to a clean
directory and built with `FLUTTER_SWIFT_ENGINE_OUT`, `STARLING_ENGINE_OUT` and
`STARLING_SDK_BUNDLE` all cleared: `tools\build-windows.ps1` compiled the whole
framework and all three example executables — `CounterApp.exe`,
`TerminalDemo.exe`, `TerminalTiling.exe` — in 360 s, none of which carries a
`.build`-directory resource-bundle path. The vendored-header drift check ran
(it needs Git bash and `swiftc` on PATH, and is silently skipped without them)
and passed against the same `ea78543` engine.
