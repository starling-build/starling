# Starling SDK 0.3.1 — apps built on it now run on other people's machines

One source fix, cut on top of **`terminal-v0.1.0`** — the commit the shipped
terminal was built from. The engine is unchanged, byte for byte the same
binaries 0.3.0 carries, and no API moved. Linux is reissued alongside macOS so
the two platforms carry one version; Windows stays at 0.3.0. What the fix does
for each is below — on Linux, nothing, and that is the point.

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

## Why it only bites on macOS

`Bundle.module`'s first candidate is *correct* on Linux and Windows, where a
bare executable's `Bundle.main.bundleURL` is the directory the executable sits
in — which is exactly where the resource bundle is staged. The fallback is
never reached there, so the bug cannot bite.

**The Linux bundle is reissued anyway, and carries no behaviour change.** It is
the same source fix — the search runs there too, it simply never had to — and
the same engine as 0.3.0, byte for byte. The reason to ship it is that "which
SDK version am I on" should not need a per-platform answer: a Linux consumer
staying at 0.3.0 while macOS moves invites the question every time. Windows
stays at 0.3.0 because nobody rebuilt it, not because it would differ.

If you are on Linux there is no bug to escape and no urgency to upgrade.

## Upgrading

Repoint your path dependency at the unpacked 0.3.1 tree; nothing else changes.
No API moved, so a rebuild is the whole upgrade.

    tar xzf starling-sdk-0.3.1-macos-arm64.tar.gz -C /opt     # or
    tar xzf starling-sdk-0.3.1-linux-x86_64.tar.gz -C /opt

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
