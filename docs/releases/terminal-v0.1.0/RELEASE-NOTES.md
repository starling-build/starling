# Starling Terminal 0.1.0 — one terminal on three desktops, and it is the fast one

The terminal from the [Starling desktop](https://starling.build), shipped on its
own for Linux, Windows and macOS. One codebase, one emulator, the same speed on
each — and on every platform it is measured against the fastest terminal there
was to beat and comes out ahead.

There is no libvte and no libvterm here: the emulator is about 2,000 lines of C
written for this, and the pixels come from the Flutter engine through the
[Starling SDK](https://github.com/starling-build/starling/releases/tag/sdk-v0.3.0).
That is the unusual part — terminals this fast are normally built on a stack
that can only ever draw a terminal.

## Install

**Linux** x86_64 — GNOME, KDE, Wayland or X11:

    curl -LO https://github.com/starling-build/starling/releases/download/terminal-v0.1.0/starling-terminal_0.1.0_amd64.deb
    sudo apt install ./starling-terminal_0.1.0_amd64.deb

Everything it loads rides inside the package under `/usr/lib/starling-terminal`;
`dpkg-shlibdeps` computed the system dependencies, so a missing GTK or libinput
is a package error rather than a crash on launch. It opens from the app grid as
**Starling Terminal**, or as `starling-terminal` from any prompt, and installs
cleanly beside the desktop package. On the Starling desktop there is nothing to
install — the terminal is part of the desktop.

**macOS** arm64 — macOS 14 or newer:

    curl -LO https://github.com/starling-build/starling/releases/download/terminal-v0.1.0/starling-terminal-0.1.0-macos-arm64.zip
    ditto -xk starling-terminal-0.1.0-macos-arm64.zip /Applications

The bundle is ad-hoc signed and **not notarized**, so macOS holds the first
launch — and `ditto` carries the download's quarantine flag onto the installed
app, so this applies to the recipe above. Right-click → **Open** once, or
approve under System Settings → Privacy & Security → **Open Anyway**, or clear
it with
`xattr -dr com.apple.quarantine "/Applications/Starling Terminal.app"`.
After that it opens normally.

**Windows** x86_64 — Windows 10 or 11:

    curl.exe -LO https://github.com/starling-build/starling/releases/download/terminal-v0.1.0/starling-terminal-0.1.0-windows-x86_64.zip
    Expand-Archive starling-terminal-0.1.0-windows-x86_64.zip -DestinationPath StarlingTerminal
    .\StarlingTerminal\TerminalApp.exe

A native Win32 window, no installer and nothing to put on `PATH`. **Give it a
folder of its own**: the archive extracts flat, and all 52 files have to stay
together — Windows resolves imports from the executable's own directory, and the
bundled ConPTY console host sits beside it. Miss one and it dies with
`STATUS_DLL_NOT_FOUND` before `main`, silently.

Verify any download against `SHA256SUMS`.

## Speed

Thirteen tests per platform — ten escape-sequence workloads, two 500 MB `cat`s
and DOOM-Fire — every one at steady state, with each workload repeated until the
slower side sustains one to two minutes. Matched fonts and cell metrics where the
other terminal is configurable, and the grid verified on both sides before every
leg. Raw runs are in [`docs/perf/`](../../perf).

| | rival | suite | CPU | DOOM-Fire | notes |
|---|---|---|---|---|---|
| Linux | ghostty nightly | **1.38×** | 0.53× | **1.94×** | unicode `cat` 1.79× |
| macOS | ghostty nightly | **1.28×** | 0.44× | 1.05× | ten of ten workloads at or ahead |
| Windows | Windows Terminal | **1.41×** | 0.50× | **1.24×** | every test a win |

Across all three platforms the only test the other side keeps by more than noise
is the Linux ascii `cat`, by ~6% — ghostty's `io_uring` read path gets under the
`read(2)` floor ours sits on. macOS has no io_uring and the same test flips to
us.

Two results worth pulling out. **The binary dump is 3.5–4.3× everywhere**
(40.9 s against Windows Terminal's 177.6 s), and **memory on Windows is 73 MB
against 1,026 MB** for the same ten workloads — a figure Windows Terminal
reproduces across machines. Our resident set is flat on all three platforms: the
same size no matter how much has been drawn.

The Windows round is the first on real hardware rather than a VM, and the first
run with the console on the UTF-8 code page — which matters, because on the
legacy code page the unicode workloads were measuring mojibake on both sides.
Its rival column is Windows Terminal **Preview 1.25**, chosen because the stable
build hands new windows to whatever Windows Terminal is already running, which
makes an isolated measurement impossible.

## Text, done properly

Zero `ucs-detect` errors in **107,189 measurements** — wide characters, emoji
families, 118 languages of conjuncts — where the ghostty nightly logs 40.
Braille, box drawing, blocks and colour emoji all render from a bundled fallback
chain, because a codepoint with no glyph paints nothing and costs *less*, so a
coverage gap arrives disguised as a better benchmark.

## What is in it

Tabs — `Ctrl+T` (`⌘T` on macOS) opens one, `Ctrl+Shift+W` or `⌘W` closes it, or
the `✕` on the tab; the bar stays hidden until there are two. Find in
scrollback on `Ctrl+Shift+F` / `⌘F`, newest match first, Enter for older and
Shift+Enter for newer. Selection and clipboard, mouse reporting so full-screen
apps get the wheel, 2,000 lines of scrollback, wide characters and grapheme
clusters, and a cursor that blinks only at rest.

## Provenance

All three binaries are assembled **against the published SDK 0.3.0 bundles**,
not against a private tree — the same download anyone gets from
[`sdk-v0.3.0`](https://github.com/starling-build/starling/releases/tag/sdk-v0.3.0).

One caveat on the numbers above: they were measured on the immediately preceding
build on each platform, before the tab work landed. Re-measure before quoting
them against these exact archives.

## Build your own instead

The terminal is a widget. `starling-create` from the SDK release scaffolds a
project with one in it, in about twenty lines of Swift — see
<https://starling.build/terminal.html>.
