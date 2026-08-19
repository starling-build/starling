# Starling Terminal 0.1.1 — the macOS build now runs on your Mac, not just ours

A macOS-only patch. **No feature changed**, and Linux and Windows are not
affected: their 0.1.0 downloads are current and this release does not replace
them. If you are on either, there is nothing here for you.

If you are on macOS, 0.1.0 almost certainly did not work, and this explains why.

## What was wrong

**It crashed at startup on every Mac but the one that built it.**

    Flutter/resource_bundle_accessor.swift:12: Fatal error:
    could not load resource bundle

SwiftPM generates its `Bundle.module` accessor with exactly two candidates: the
app bundle's own directory, and **an absolute path into the build directory
that produced the binary**. Inside a `.app` the first misses — resource bundles
belong under `Contents/Resources/`, which is where they are staged — and the
second resolved on precisely one machine. Everywhere else both miss, and the
accessor traps on the first font load, which is startup.

It survived testing because the obvious check is to unpack the archive and run
it, and doing that on the build machine exercises the one path that exists
there. `strings` on the executable is what finally showed it: someone else's
home directory, compiled in.

**And its signature did not survive being unzipped.** `ditto -c -k` without
`--sequesterRsrc` stores each file's extended attributes as AppleDouble;
command-line `unzip` then materialises those as real `._Foo` files *inside* the
bundle — including `Contents/_CodeSignature/._CodeResources` — and `codesign`
reports `a sealed resource is missing or invalid`. The 0.1.0 install
instructions said `ditto -xk`, which understands AppleDouble and unpacks
correctly, so the release's own recipe hid the bug from the release.

## What changed

The framework now **searches** for its resource bundles —
`Contents/Resources` for a macOS app, the executable's directory for the Linux
and Windows layouts — and returns nothing rather than trapping when they are
absent, because a terminal using the system's fonts is degraded while one that
refuses to start is not usable at all. `CupertinoIcons` had the same bug one
target over; its hand-written fallback could never run, since reaching
`Bundle.module` to test it is what traps.

Two checks now stand where there were none. `build/macos-app.sh` fails the
build if any build-directory path survives into the executable, and it verifies
the finished archive by unpacking it with plain `unzip` — not `ditto -x`, which
would repair the very thing under test.

## Install

**macOS** arm64 — macOS 14 or newer:

    curl -LO https://github.com/starling-build/starling/releases/download/terminal-v0.1.1/starling-terminal-0.1.1-macos-arm64.zip
    ditto -xk starling-terminal-0.1.1-macos-arm64.zip /Applications

The bundle is ad-hoc signed and **not notarized**, so macOS holds the first
launch, and `ditto` carries the download's quarantine flag onto the installed
app. Right-click → **Open** once, or approve under System Settings → Privacy &
Security → **Open Anyway**, or clear it with
`xattr -dr com.apple.quarantine "/Applications/Starling Terminal.app"`.
After that it opens normally.

Plain `unzip` is now safe too, which it was not in 0.1.0.

## Provenance

Built on macOS from `release-terminal-0.1.1` — the branch of that name in this
repo and in starling-engine, which is the record of what this was built from.

**From the released SDK bundle alone**, which is the path 0.1.0 used and the
one that matters: it produces the terminal exactly the way an external consumer
would, so every release exercises the SDK it ships beside.

    tar xzf dist/starling-sdk-0.3.1-macos-arm64.tar.gz -C /tmp/sdk
    env -u STARLING_ENGINE_OUT -u FLUTTER_SWIFT_ENGINE_OUT \
        STARLING_SDK_BUNDLE=/tmp/sdk/starling-sdk-macos-arm64 \
        STARLING_APP_VERSION=0.1.1 build/macos-app.sh TerminalApp --zip

There was a window where that was impossible and it is worth recording. The fix
is in the framework's own sources, and `starling-sdk-0.3.0-macos-arm64.tar.gz`
carried a copy that predated it — so building 0.1.1 from 0.3.0 would have
faithfully reproduced the crash this release exists to fix, and said nothing
while doing it. The first 0.1.1 archive was therefore built against the repo's
own `sdk/` and shipped with that stated as a weakness. **SDK 0.3.1 removed the
reason, and this archive is the rebuild.**

Three checks, each aimed at a way this could look right and be wrong:

- **Was it really a consumer build?** The build plan, not the command line, is
  the evidence: 45 references to the unpacked bundle, zero to `starling-engine`
  or to the repo's `sdk/`. With `STARLING_ENGINE_OUT` or
  `FLUTTER_SWIFT_ENGINE_OUT` set, the manifest's `-L` finds a checkout and the
  build passes while proving nothing, so both were cleared.
- **Is the engine the bundle's?** Compared by **Mach-O UUID**, not by hash —
  the app re-signs `FlutterMacOS.framework` and `libswift_bridge.dylib` on the
  way in, so their bytes differ from the bundle's copies while the code is
  identical. A hash comparison reports a false mismatch here, and did.
- **Does it run anywhere else?** With every resource bundle hidden from both
  build directories, the unpacked archive was launched under `env -i` and drew
  a shell, and its signature verified after a plain `unzip`.
