# Starling SDK 0.3.1 — apps built on it now run on other people's machines

One source fix, cut on top of **`terminal-v0.1.0`** — the commit the shipped
terminal was built from. The engine is unchanged, byte for byte the same
binaries 0.3.0 carries, and no API moved. **All three bundles ship at 0.3.1** —
macOS, Linux and Windows. What the fix does for each is below: on macOS it is
the whole point, and on the other two, nothing.

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

**Linux and Windows are reissued anyway, and carry no behaviour change.** Both
are the same source fix — the search runs there too, it simply never had to —
and the same engine as 0.3.0, byte for byte. The reason to ship them is that
these bundles carry *source*: a platform left at 0.3.0 publishes the same
framework in two different states, and "which SDK version am I on" then needs a
per-platform answer every time it is asked. If you are not on macOS there is no
bug to escape and no urgency to upgrade.

Diffing the unpacked Windows zips says exactly what moved between 0.3.0 and
0.3.1 there, and it is **four files, not two**. `TerminalView.swift` and
`CupertinoIcons.swift` are the fix. `tools/starling-create` and
`tools/stage-windows.ps1` came along because the 0.3.0 zip was cut before them:
the scaffolder learned Windows and versioned asset names, and
`stage-windows.ps1` learned to stage against an SDK bundle's split
`engine\lib` / `engine\share` layout instead of demanding a flat engine
out-directory. Everything else — every other source file, and all five engine
artifacts — is byte for byte what 0.3.0 shipped.

## `starling-create` can now express a partial release

It could not, and this release spent most of its life being one. The plan
through the day was macOS only, then macOS and Windows; Linux was rebuilt last.
Through all of that the scaffolder carried a single `SDK_VERSION` feeding both
the tag and the asset name, so it would have sent every Linux user to
`sdk-v0.3.1/starling-sdk-0.3.1-linux-x86_64.tar.gz` — an asset that would not
have existed. The failure is a 404 at the download, which is at least loud, but
it is a release that cannot be installed on a third of its platforms.

It now holds one version per platform and **derives the tag from it**, which
keeps the invariant that matters: a bundle is served from the release named by
its own version, so a platform that is not rebuilt keeps being served from the
tag that first published it. As of this release all three rows read 0.3.1 and
the table looks redundant — it is the next partial release that needs it, and
the near-miss here is why it exists at all. The release a *user* downloads the
tool from is tracked separately, because that is a different question: the tool
is one asset on one release whatever mix of bundles that release reissued.

Checked by composing all three URLs and asking GitHub for each: all three answer
**404** against `sdk-v0.3.1`, the tag this release has not created yet, which is
the shape you want to see before cutting it — and the Linux row pointed at
`sdk-v0.3.0` answers **200**, which is the case the table exists for and the one
that cannot be tested once every row reads the same.

The copy of the tool inside each bundle's `tools/` is a convenience snapshot;
the canonical one is the release asset. Only the Windows zip carries the current
one, because it was the last of the three to be cut.

## Upgrading

Repoint your path dependency at the unpacked 0.3.1 tree; nothing else changes.
No API moved, so a rebuild is the whole upgrade.

    tar xzf starling-sdk-0.3.1-macos-arm64.tar.gz -C /opt     # or
    tar xzf starling-sdk-0.3.1-linux-x86_64.tar.gz -C /opt

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

The Linux tarball was verified the same way on the dev box, and its engine did
**not** come from `host_release`: all four files were taken out of the published
`starling-sdk-0.3.0-linux-x86_64.tar.gz` and compared with what shipped. Read
from the shared out directory they would not have matched — that
`libflutter_engine.so` had been relinked from `starling`, three commits past the
release commit. `dist/README.md` has the full account; it is the failure that
directory already warned about, caught this time.

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
