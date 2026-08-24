# Building Starling from scratch

Everything needed to go from an empty machine to a running desktop, in order.
Both halves get built: **starling-engine** (the Flutter engine fork, C++) and
**starling-desktop** (the Swift framework port, shell, and apps).

Verified end to end on **2026-07-25** on a fresh **Ubuntu 26.04 LTS (resolute)**
— 12 vCPU, 16 GB RAM, 200 GB disk — starting from a plain cloud image with no
toolchain of any kind installed, and finishing with the desktop running on DRM
and an app window compositing.

Re-verified on **2026-08-02** on real hardware (a Lenovo laptop, 16 threads,
14 GB RAM, AMD Radeon 680M driving the panel), through the live-desktop tier:
`sudo test/run.sh --functional` passed 17 checks. The times below assume an
otherwise-idle machine; they stretch considerably if you overlap the steps.
The fourth package group in §2.1 came out of that run — every one of those
failures happens after a completely successful build.

| step | wall clock | disk |
|---|---|---|
| `gclient sync` (engine DEPS) | 25 min | 29 GB |
| engine `ninja` host_debug | 8 min | 680 MB |
| engine `ninja` host_release | 7 min | 308 MB |
| desktop `swift build` — shell | 2 min | |
| desktop `swift build` — 5 apps | 9 min (1m45 each) | |
| `build/stage.sh` | seconds | 252 MB |
| `build/package-desktop.sh` | ~1 min | 61 MB `.deb` |
| **total** | **~55 min** | **~41 GB** |

Budget **60 GB of free disk**. **Ubuntu 26.04 LTS is the base platform**, for
test and for production. It comes with two toolchain-vs-distro mismatches, both
handled in-tree — `./bootstrap.sh` and the package manifests — so there is
nothing extra to type. What they are and why is in
[26.04 notes](#ubuntu-2604-notes).

---

## 0. Prerequisites

- x86_64 **Ubuntu 26.04 LTS** — the base platform, and the only release these
  instructions target.
- Both repositories are public, so cloning needs no credentials. If you plan
  to push, register an SSH key with your account:

  ```bash
  ssh -T git@github.com     # must greet you by name, not ask for a password
  ```

- **Pick the final path of the engine checkout before you build.** ninja keys
  its cache on the absolute paths in compile command lines, `out/*/args.gn`
  records an absolute `default_git_folder`, and every Swift binary gets an
  absolute rpath into the engine's `out/host_debug`. Moving the checkout later
  means re-running `gn gen`, a full ~4400-step rebuild per config, and
  relinking every Swift binary.

The two repos sit side by side, which is what `bootstrap.sh` expects:

```
~/dev/starling-build/
    starling-engine/     the C++ half (also the flutter monorepo root)
    starling/            the desktop — shell, compositor, apps, packaging,
                         and sdk/ (the Flutter→Swift framework, in-tree)
```

`bootstrap.sh` makes one symlink, `starling/engine`, so every manifest in the
desktop can say `../engine` without hardcoding where you cloned things. The
framework needs no symlink: it lives in this repo at `sdk/`, folded back from
the separate `flutter-swift` checkout as a git subtree in 2026-08.

---

## 1. The engine

### 1.1 Host packages

```bash
sudo apt-get update
sudo apt-get install -y git curl unzip python3 pkg-config
```

That is all the engine build takes from the distro. clang, the Dart SDK, ninja,
and even a Debian sysroot for the system libraries the DRM embedder links
against (`libdrm`, `gbm`, `EGL`, `GLESv2`, `input`, `udev`, `xkbcommon`) are
hermetic — `gclient` fetches them into the checkout. No `-dev` packages needed
for this half.

### 1.2 depot_tools

```bash
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git ~/depot_tools
export PATH="$HOME/depot_tools:$PATH"       # put this in your shell profile
```

`gclient`, `ninja`, and `vpython3` all come from here. `flutter/tools/gn` has a
`#!/usr/bin/env vpython3` shebang, so without depot_tools on PATH it fails with
`env: 'vpython3': No such file or directory`.

### 1.3 Clone, and write the gclient solution

`starling-engine` is a fork of `flutter/flutter`, so it carries upstream's full
history — a clone is ~600 MB and takes a few minutes. Starling's work is the
`starling` branch, which is the repo default:

```bash
mkdir -p ~/dev/starling-build && cd ~/dev/starling-build
git clone https://github.com/starling-build/starling-engine.git
cd starling-engine
git remote add upstream https://github.com/flutter/flutter.git   # for rebases
```

Add `--branch starling --single-branch` to the clone if you want to skip
upstream's other branches. **Pick the final path before building** — see the
warning above; ninja and every Swift rpath bake in absolute paths.

`gclient` needs a `.gclient` at the repo root. It is per-checkout state and
deliberately untracked, so derive it from the upstream template in the tree:

```bash
sed 's#https://github.com/flutter/flutter.git#https://github.com/starling-build/starling-engine.git#' \
    engine/scripts/standard.gclient > .gclient
```

The solution is `"managed": False`, so `gclient` never touches the root
repository's checkout — it only hydrates `DEPS`.

### 1.4 Hydrate DEPS

```bash
gclient sync -D
```

25 minutes and 29 GB: ~50 third-party repositories, a prebuilt Dart SDK, the
clang toolchain, the sysroots. Transient
`WARNING: subprocess ... failed; will retry after a short nap` lines are normal
— gclient retries and the sync still succeeds. On a slow link,
`gclient sync --no-history` shallows the sub-repos.

### 1.5 Generate the build files

```bash
cd engine/src
flutter/tools/gn --runtime-mode=debug   --no-lto --no-backtrace --no-rbe
flutter/tools/gn --runtime-mode=release --no-lto --no-backtrace --no-rbe
```

This writes `out/host_debug/args.gn` / `out/host_release/args.gn` and runs
`gn gen`. **`out/` is untracked, so a fresh clone has no `args.gn` — these two
commands are what create it.**

`gn` itself comes from `flutter/third_party/gn/gn`, which `gclient` hydrates
(not `buildtools/`, which only carries clang). A tree without that copy — a
distribution package build, say — falls back to whatever `gn` is on PATH, and
`$STARLING_GN` overrides both. Two further knobs exist for the same reason:
`$STARLING_SWIFT_INCLUDE` sets the Swift include directory the bridge's
`BUILD.gn` reads (Arch keeps it at `/usr/lib/swift/include`, not under a
toolchain root), and `$STARLING_SWIFT_TOOLCHAIN` supplies a toolchain root to
derive it from. Version stamping degrades to `unknown` rather than failing
when the skia, dart, or framework checkouts a gclient tree provides are absent.

### 1.6 Build the two libraries

```bash
ninja -C out/host_debug   libflutter_engine.so libflutter_linux_drm.so libflutter_linux_gtk.so
ninja -C out/host_release libflutter_engine.so libflutter_linux_drm.so libflutter_linux_gtk.so
```

**depot_tools must be on PATH for these too**, not just for `tools/gn` (§1.2).
GN actions shell out to `vpython3` — SPIRV-Tools' table generator is the first
— so a build launched from a shell without it dies ~90 steps in with
`/bin/sh: 1: vpython3: not found`. Editors, CI, and `nohup`/background shells
that skip your profile are the usual way this bites.

~4400 steps per config. **Build both:**

- `host_debug` is what every Swift package links against and bakes into its
  rpath by default (`engineOutDir` in each `Package.swift`), so the desktop
  will not link without it — even for a release desktop build.
- `host_release` is what `stage.sh` copies into the shipping tree, and what
  packaging requires.

Set `$STARLING_ENGINE_OUT` to build only one of them: every `Package.swift`
and `stage.sh` read it, so pointing all of them at `out/host_release` makes a
release-only engine build sufficient. That halves the ~4400-step build, which
matters most for a distribution package that ships release binaries anyway.

Each config yields `libflutter_engine.so`, `libflutter_linux_drm.so`,
`libflutter_linux_gtk.so`, and `icudtl.dat`. That is the entire interface the
desktop consumes. The GTK one is not used by the desktop at all — it is the
embedder the SDK's windowed host runs on, so an SDK bundle built without it
produces apps that link and then die looking for it. `make-bundle.sh` copies it
only if it exists, which is exactly how a bundle ships silently incomplete.
Later
engine-only changes rebuild in seconds and need **no Swift relink**: the shell
binds only the engine's stable C API.

The engine's public headers are **vendored** into `sdk/`, not read out of the
checkout, so `sdk/` compiles with no engine tree present and needs the engine
only at link time. `sdk/tools/sync-vendored-headers.sh` refreshes them and
`--check` reports drift; re-run it after changing a bridge header in the engine.

---

## 2. The desktop

### 2.1 Host packages

```bash
sudo apt-get install -y \
    build-essential binutils libc6-dev libcurl4-openssl-dev libedit2 \
    libncurses-dev libpython3-dev libsqlite3-0 libxml2-dev libz3-dev \
    pkg-config tzdata unzip zlib1g-dev
sudo apt-get install -y \
    libwayland-dev libxkbcommon-dev libdrm-dev libgbm-dev libegl-dev \
    libgles-dev libinput-dev libudev-dev libsystemd-dev libxshmfence-dev \
    libx11-dev libxcb1-dev libpixman-1-dev libpipewire-0.3-dev
sudo apt-get install -y libva-dev
sudo apt-get install -y \
    netpbm ffmpeg mesa-va-drivers seatd
```

First group: Swift's own prerequisites. Second: what the shell's C targets
compile and link against — the Wayland compositor (`wayland-server`,
`xkbcommon`), the DRM/GBM/EGL stack, `libinput`/`libudev`, sd-bus for the portal
(`libsystemd`), the in-tree X server's `xshmfence`, and PipeWire for the
portal's ScreenCast stream (linked, not dlopen'd — `libpipewire-0.3-0` is in
every Ubuntu desktop install as the audio stack). Third: `libva-dev`, which
both halves of the hardware video path link directly — the video player's
`CH264Decoder` and the screen recorder's `CVaapiEncoder`. libva is MIT and
present wherever VA-API is, so it needs no dlopen dance.

The libav headers (`libavcodec-dev` and friends) used to be here, for the
recorder's encoder. They are gone: it writes its own H.264 parameter sets and
its own MP4 index now, so nothing in the tree compiles or links against
libav at all. The `ffmpeg` *binary* is still used, as a spawned process — see
below.

Fourth: nothing compiles against these, so the build succeeds without them and
each one instead fails later, at run time, in a way that does not name the
missing package:

- **`netpbm`** — `build/shell-drive.py` shells out to `pnmtopng` to turn the
  shell's `.ppm` dump into a PNG. Without it every `shot` dies with a bare
  `FileNotFoundError: 'pnmtopng'` after the screenshot was already captured.
- **`ffmpeg`** — the *binary*, which is a separate thing from the `-dev`
  headers above. It is the recorder's pipe fallback, and
  `shell-drive.py`'s `record-stop` also uses it. Missing, the shell logs
  `[Recording] no VAAPI encoder — software x264, large screens capture at half
  size`, which reads like a GPU problem but only means the fallback encoder
  is not installed.
- **`mesa-va-drivers`** — VAAPI itself. Without it there is no hardware
  encoder at all and the zero-copy recording path silently degrades.
- **`seatd`** — lets the shell take the seat with no sudo, which is the
  shipping model; see §3.

### 2.2 Swift 6.2.4

swift.org publishes no `ubuntu26.04` build of 6.2.4; the `ubuntu24.04` one runs
fine on 26.04:

```bash
TC="$HOME/.local/share/swiftly/toolchains/6.2.4"
mkdir -p "$TC"
curl -fL -o /tmp/swift.tar.gz \
  https://download.swift.org/swift-6.2.4-release/ubuntu2404/swift-6.2.4-RELEASE/swift-6.2.4-RELEASE-ubuntu24.04.tar.gz
tar -xzf /tmp/swift.tar.gz -C "$TC" --strip-components=1
export PATH="$TC/usr/bin:$PATH"
swift --version          # Swift version 6.2.4 (swift-6.2.4-RELEASE)
```

That path is a convention, not a requirement. No `Package.swift` names a
toolchain directory: `<swift/bridging>`, the only toolchain header the bridge
headers need, is vendored into `sdk/` by `sdk/tools/sync-vendored-headers.sh`
and resolves through the package's own include directory. So installing 6.2.4
with `swiftly`, unpacking it anywhere, or using a distribution's own Swift all
work, provided `swift` is on PATH. The engine's `BUILD.gn` is the one place
that still needs the include directory itself, and it can be pointed anywhere
(§1.5).

On 26.04, `swift-build` cannot start until the toolchain gets a libxml2 compat
symlink; `./bootstrap.sh` in the next step creates it. It looks under
`$STARLING_SWIFT_TOOLCHAIN`, defaulting to the swiftly path above. Other
distributions do not need the symlink at all — it exists because the 6.2.4
binary is an ubuntu24.04 build.

### 2.3 Clone, and point it at the engine

The Flutter→Swift framework lives in this repo at `sdk/` — nothing to clone
for it. Only the engine is a sibling checkout:

```bash
cd ~/dev/starling-build
git clone https://github.com/starling-build/starling.git
cd starling
./bootstrap.sh                  # engine -> ../starling-engine/engine
```

Every engine reference in this repo goes through that symlink; pass a path
to `bootstrap.sh` to use a checkout elsewhere (`./bootstrap.sh <engine>`,
or `$STARLING_ENGINE`).

### 2.4 Build the shell and the apps

The set the `.deb` ships is defined by the registry, not by a list here:
every `registry/catalog.d/*.app` record with `Kind=first-party` names its
executable in `Exec=`, and `package-desktop.sh` requires a built binary for
each one (a record without a binary is a hard error — an installed desktop
would show a launcher tile that launches nothing). Build the shell, then
every first-party app the catalog declares:

```bash
swift build -c release --package-path shell
for a in $(grep -l "^Kind=first-party" registry/catalog.d/*.app \
             | xargs -n1 sed -n 's/^Exec=//p'); do
    swift build -c release --package-path "apps/$a"
done
```

No extra flags on any release: the manifests carry what 26.04 needs.

The shell pulls in `sdk/` (the `FlutterSwift` framework port) as a package
dependency, so there is nothing to build there separately. `apps/` holds more
than the catalog declares (dev and demo tools — DSATool,
FlutterDemoApp); those have no record and stay out of the package on purpose.
Staging picks up any app with a built binary, so a partial build still runs —
only packaging insists on the full first-party set.

### 2.5 Stage

```bash
build/stage.sh                  # -> .stage/
```

`stage.sh` is the single definition of the installed layout: the shell, the
engine libraries, the Swift runtime, the apps, and the assets, collected into
one self-contained tree that mirrors what the package installs.

**Always run from the staged tree, never straight out of `.build`.** Child apps
are spawned with `LD_LIBRARY_PATH` scrubbed and resolve libraries through their
own `$ORIGIN` only, so they work solely when the libraries sit beside them —
exactly what staging arranges. A `.build`-relative layout appears to work right
until a child app dies with
`libflutter_engine.so: cannot open shared object file`.

---

## 3. Run it

```bash
build/run-desktop.sh
```

Re-stages, then runs the desktop out of `.stage/`. It needs the GPU free — no
display manager or compositor holding `/dev/dri/card*`:

```bash
sudo systemctl isolate multi-user.target     # or drop to a TTY
sudo fuser -v /dev/dri/card*                 # expect nothing
```

Seat access is automatic: libseat (seatd or logind, no sudo — the shipping
model) when a seat manager is reachable, else a root device open via sudo.

Two group memberships make the no-sudo path work, and both matter only in the
dev loop, where the display manager is stopped and you are typically on SSH.
A real session gets each of these from logind as an ACL on the device; an SSH
session is not seat-active, so it gets neither and falls back to group
permissions:

```bash
sudo usermod -aG video,render "$USER"        # log in again to pick them up
```

`video` reaches `/run/seatd.sock` (`root:video`), without which `run-desktop.sh`
drops to the sudo path. `render` reaches `/dev/dri/renderD*` (`root:render`),
which the shell opens **directly** to probe for an in-process VAAPI encoder —
so without it recording loses the zero-copy path even with `mesa-va-drivers`
installed. Confirm with `getfacl /dev/dri/renderD129`: if no `user:<you>` entry
appears, the group is the only thing granting access.

Drive it and take screenshots without touching a keyboard:

```bash
sudo build/shell-drive.py "click 1125 1035" "shot /tmp/x.png"
```

Note the quoting: each action **and its arguments** is one argv entry.

**`shell-drive.py` speaks logical coordinates; screenshots come out physical.**
The virtual pointer is built against `SCREEN_W_PHYS / DPI`, so on a HiDPI panel
(2560x1600 at scale 2 = logical 1280x800) a point read off a screenshot must be
**halved** before you click it. Getting this wrong does not fail: the click just
lands at 2x the intended spot, usually off-screen, and the feature under test
looks broken. Avoid the conversion entirely where you can — `"dock ?"` lists
every dock icon's real centre, as the dock is laid out right now, and
`"dock calculator"` clicks one by name:

```bash
sudo build/shell-drive.py "dock ?"
sudo build/shell-drive.py "dock calculator" "sleep 2" "shot /tmp/x.png"
```

---

## 4. Package

```bash
build/package-desktop.sh        # -> starling-desktop_<ver>_amd64.deb
```

Wraps `stage.sh`'s output with control metadata and the system-integration
payload, and computes `Depends` with `dpkg-shlibdeps`. Prereqs: the release
shell, every first-party app in the catalog (§2.4), and the engine's
**`host_release`**.

That payload — the session launcher, its wayland-session entry, the polkit
policy, and the NetworkManager drop-in — lives in `build/session/` as real
files, installed verbatim. Packaging Starling for another distribution means
consuming `stage.sh` for the tree and `build/session/` for those four files;
`build/session/README.md` gives the install paths and modes.

The result
bundles the Swift runtime and the engine privately, installs under
`/usr/lib/starling` + `/usr/share/starling`, and adds a "Starling" session to
the login screen. It `Recommends: gdm3 | lightdm | sddm` — a bare server image
has no display manager, and without one nothing shows the session menu.

---

## Ubuntu 26.04 notes

Two things break on 26.04 and on no earlier release. Both come from running an
`ubuntu24.04`-built Swift toolchain on a newer distro — neither is a Starling
bug, and both are now fixed in-tree, so this section is background rather than
instructions. **Both disappear once swift.org ships a 26.04 release toolchain**
(`main` snapshots have had one since 2026-07-11); at that point delete the fixes.

### `libxml2.so.2: cannot open shared object file`

26.04 ships only `libxml2.so.16` (package `libxml2-16`); the toolchain's
`libFoundationXML.so` links the old soname, so `swift-build` won't even start.
Its `RUNPATH` is `$ORIGIN`, so a symlink beside it is enough — nothing
system-wide changes.

**Fixed by `bootstrap.sh`**, which creates that symlink when the distro has no
`libxml2.so.2` of its own. Idempotent, and a no-op on older releases.

### `cmath:100: redefinition of 'acos'` → `could not build C module '_FoundationCShims'`

Every Starling target uses C++ interop, so the clang importer compiles
Foundation's C shim in **C++** mode. Its `#include <math.h>` then resolves to
libstdc++'s C++ wrapper, which pulls `<cmath>` in textually — while the prebuilt
`std` module already contains it. clang sees every overload twice. 26.04's
glibc 2.43 / libstdc++ 15 combination is what exposes it; 25.10 (glibc 2.42)
builds clean. It is not a Swift-version problem — 6.3 fails identically.

The fix predefines the wrapper's include guard so it stops pulling `<cmath>`,
and force-includes glibc's `math.h` so every TU still gets the C declarations —
what libstdc++'s own `_GLIBCXX_INCLUDE_NEXT_C_HEADERS` path would do:

```bash
-Xcc -D_GLIBCXX_MATH_H -Xcc -include -Xcc /usr/include/math.h
```

**Carried by every `Package.swift`** as `glibcMathCompat`, folded into the
`toolchainSwiftCFlags` each Swift target already passes to the clang importer.
Applied on all Linux releases rather than version-gated: the semantics are
identical on older glibc, and uniform behaviour is the point of a base platform.
Putting it in the manifests rather than a wrapper script also keeps
sourcekit-lsp working — the editor hits the same failure otherwise.

Verified against all three consumers: the Swift importer (Foundation *and* the
C++ `std` module), C++ TUs including `<cmath>`, and C++ TUs including
`<math.h>`.

One caveat worth knowing: `#include <math.h>` in C++ no longer injects the
`using std::…` names into the global namespace. Nothing in the tree relies on
that.

### Watch out when testing workarounds

clang's module cache makes flag experiments lie: a `.pcm` built under one flag
set gets reused under another, so a broken configuration can appear to pass.
Clear it between attempts:

```bash
rm -rf ~/.cache/clang
```

---

## A Windows build host, from nothing

Everything above builds the Linux desktop. The Windows terminal
(`dist/starling-terminal-windows-x86_64.zip`) needs its own host, and a Windows
box with nothing installed hits **five** separate walls before the engine
compiles. Each one surfaces only when the build reaches it, so they cost five
round trips rather than one. Budget ~45 minutes of build after the installs, and
~10 GB for the engine checkout plus its `out/`.

Toolchain versions are not a free choice: use **Swift 6.2.3, MSVC 14.44, Windows
SDK 10.0.22621**. Newer Swift and SDKs are on offer and were deliberately not
taken — `sdk/tools/build-windows.ps1`'s cold-cache retry is keyed to that exact
pairing, and a shipped binary should stay comparable to the one it replaces.

1. **VS Build Tools with the C++ workload.** `winget install
   Microsoft.VisualStudio.2022.BuildTools` installs the shell, but its
   `--override` carrying the workload is silently not honoured — you get a VS
   with no compiler. Verify `VC\Tools\MSVC` is non-empty rather than trusting
   the exit code, and add the workload through the installer directly:

       setup.exe modify --installPath "...\2022\BuildTools" \
           --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended \
           --quiet --norestart

   Launch that with `Start-Process -Wait -PassThru`. `setup.exe` is a
   GUI-subsystem binary, so PowerShell does not wait on it and `$LASTEXITCODE`
   comes back **empty** — which reads exactly like a command that ran and
   succeeded.

2. **Build Tools is invisible to Chromium's VS detection.**
   `build/vs_toolchain.py`'s `DetectVisualStudioPath()` searches only for
   Enterprise, Professional, Community and Preview, so `gclient`'s hooks die
   with `Visual Studio Version 2022 (from GYP_MSVS_VERSION) not found` on a
   perfectly good install. It checks a `vs<year>_install` variable *before* that
   list, so set

       $env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"     # use local VS, not Google's package
       $env:GYP_MSVS_VERSION = "2022"
       $env:vs2022_install = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools"
       $env:GYP_MSVS_OVERRIDE_PATH = $env:vs2022_install

   for both `gclient sync` and the `gn`/`ninja` run — `setup_toolchain.py`
   shares that detection code.

3. **Windows SDK 10.0.22621, specifically.** `build/toolchain/win/setup_toolchain.py`
   hardcodes `SDK_VERSION = '10.0.22621.0'` and passes it to `vcvarsall`
   deliberately, "to avoid accidentally building with a new and untested SDK".
   A box carrying only the current SDK fails with `Path
   ...\include\10.0.22621.0\um ... does not exist`. Add
   `Microsoft.VisualStudio.Component.Windows11SDK.22621`.

4. **Debugging Tools for Windows.** gn's `copy_dlls` step wants
   `Windows Kits\10\Debuggers\x64\dbghelp.dll`, which no VS component installs —
   it is an SDK *feature*. The SDK bootstrapper is already cached; find the one
   matching 22621 and add just that feature:

       Get-ChildItem "C:\ProgramData\Package Cache" -Recurse -Filter winsdksetup.exe
       winsdksetup.exe /features OptionId.WindowsDesktopDebuggers /quiet /norestart

5. **ATL.** `flutter/third_party/accessibility` includes `<atlbase.h>`, so
   without it ninja builds ~1970 objects and *then* fails. Add
   `Microsoft.VisualStudio.Component.VC.ATL`. **Re-run `gn`, not just `ninja`:**
   the toolchain environment block is captured at gn time, so a newly installed
   include directory never reaches an existing `environment.x64`.

Then Swift itself, where two environment facts produce misleading failures:

- **`swift.exe` needs both its `Toolchains\...\usr\bin` and `Runtimes\...\usr\bin`
  on PATH.** With only the first it exits **53 and prints nothing at all**.
- **`SDKROOT` is written to the *User* environment by the installer**, so any
  shell that was already open never sees it — and every compile, including
  SwiftPM's own manifest compile, fails with `unable to load standard library
  for target 'x86_64-unknown-windows-msvc'`. Read it back explicitly:
  `[Environment]::GetEnvironmentVariable('SDKROOT','User')`.

With all of that in place, and `vcvars64.bat` sourced into the session:

```powershell
# engine (~17 min, 4710 steps)
cd <engine>\engine\src
vpython3 flutter\tools\gn --runtime-mode=release --no-lto --no-backtrace --no-rbe
ninja -C out\host_release flutter_engine flutter_windows

# app (~7.5 min) and the distributable tree
$env:FLUTTER_SWIFT_ENGINE_OUT = "<engine>\engine\src\out\host_release"
sdk\tools\build-windows.ps1 -PackagePath apps\TerminalApp -Product TerminalApp -Configuration release
sdk\tools\stage-windows.ps1 -PackagePath apps\TerminalApp -Product TerminalApp `
    -Configuration release -Zip -Out C:\dist\starling-terminal-windows-x86_64 `
    -EngineOut $env:FLUTTER_SWIFT_ENGINE_OUT
```

The engine's four Windows artifacts are `flutter_engine.dll`,
`flutter_windows.dll` and **both `.dll.lib` import libraries** — the link needs
the import libraries, which is why a released SDK bundle can substitute for an
engine checkout here but the staged app zip cannot: it ships only the DLLs.

### Trimming what Windows never runs

`flutter/tools/gn` turns Vulkan on for every non-Apple target — it says so in
a comment, "there's no reason the Vulkan embedder features can't work on these
platforms" — and Impeller's backends default on for every desktop platform.
Windows uses neither: the Windows embedder references Vulkan nowhere and
`flutter_windows_engine.cc` pushes `--enable-impeller=false`, so it draws Skia
on ANGLE. `build/win/engine-args.ps1` applies the following to an existing out
directory and rebuilds — **run it after any `flutter/tools/gn`**, which
rewrites `args.gn` from scratch and would silently restore both. It takes
**1.93 MB** off `flutter_engine.dll`, 11.65 to 9.72:

```
skia_use_vulkan = false
shell_enable_vulkan = false
impeller_enable_opengles = false
impeller_enable_vulkan = false
enable_unittests = false
```

Both Impeller backends off is what makes `impeller_supports_rendering` false,
which is the switch the shell and embedder already guard on — one backend off
is not a configuration: `gn` itself fails on a target-name collision between
`impellerc_gles_entity_shaders` and `impellerc_gles3_entity_shaders`.

`enable_unittests = false` is not optional either: with Vulkan gone, `gn gen`
fails on unresolved dependencies from the *test* graph
(`embedder_unittests_library` needs `//flutter/testing:vulkan`) before a single
file compiles. It also takes gtest out of the build.

`stripped_symbols = true` is a no-op on Windows — symbols live in the PDB.

**Building without Impeller needed three fixes in the fork** (`41b33fc37b0`),
none of them Impeller work — they are what nobody had hit because a GL
platform had never been built without it. They are listed here because the
symptoms point somewhere else entirely:

- `embedder_external_texture_gl.cc` included seven Impeller headers
  unguarded, and fails on **`'GLES3/gl3.h' file not found`** — the include
  directory arrives with a dependency the embedder only takes when
  `impeller_supports_rendering` is true.
- `embedder.cc` read `GL_RGBA8`, which it was getting from those same Impeller
  GLES headers. It already defines `GL_BGRA8_EXT` itself two lines above.
- `InferOpenGLPlatformViewCreationCallback` constructs
  `EmbedderSurfaceGLImpeller` under `#ifdef SHELL_ENABLE_GL`, while
  `embedder/BUILD.gn` compiles that class only under
  `impeller_supports_rendering` — an **unresolved external at link time**,
  long after the switch responsible.

One thing that keeps Impeller partly in the build no matter what: the Windows
compositor uses **`impeller::ProcTableGLES` as its GL function loader**
(`compositor_opengl.cc` calls `gl_->GenTextures`, `gl_->BindFramebuffer`), so
`//flutter/impeller/renderer/backend/gles` stays a dependency of
`flutter_windows.dll`. That target is not gated on the GN arg, so it still
builds; what goes is Impeller's renderer, entity and Aiks layers and their
shader archives.

**The bigger win is not code at all.** `//flutter/third_party/icu/BUILD.gn`
sets `data_dir = "common"` for every desktop target, which is Chromium's full
10.5 MB browser ICU: 372 language bundles, 293 currency, 251 region, 250
timezone, 245 unit-name tables. Upstream also ships `flutter_desktop` — break
iterators (with the CJK, Thai and Burmese line-break dictionaries), collation,
layout, emoji — at **1.6 MB**, and nothing in the build ever selects it. We
have no Dart, and Foundation formats our dates and numbers, so the difference
is unused. The engine loads this file at runtime (`ICU_UTIL_DATA_IMPL=
ICU_UTIL_DATA_FILE`), so `build/win/package-shell.ps1` simply ships the slice
instead — a packaging choice, no fork divergence, `-FullIcu` to put the big
one back.

Together: an installed tree of 136.5 MB becomes 126.2 MB, and the setup exe
47.5 MB becomes 43.1 MB. **The Linux `build/stage.sh` still copies the full
set** — the same ~8.8 MB is available there and has not been tested on that
platform.

One number for scale before anyone reaches for the Dart VM: a symbol-size
breakdown of `libflutter_engine.so` puts Skia at 2.9 MB, the **Dart VM at
1.1 MB**, Impeller at 1.0 MB and the shell/embedder at 1.0 MB. Impeller came
out for three small guards; Dart is the runtime the whole `lib/ui` boundary is
written against, so the same trade there is days of surgery and a permanent
merge cost for less than the ICU line recovered.

---

## Traps

- **depot_tools must be on PATH** for `gn`/`gclient`/`ninja`, including for
  `flutter/tools/gn`'s `vpython3` shebang.
- **`out/*/args.gn` is not in the repo** — a fresh clone must run
  `flutter/tools/gn` before `ninja`.
- **Build both engine configs, or set `$STARLING_ENGINE_OUT`.** By default a
  `host_debug`-only build cannot be packaged and a `host_release`-only build
  cannot be linked against; that variable points the Swift packages and
  `stage.sh` at one config, which makes a single build enough.
- **No Swift toolchain path is hardcoded any more.** The packages resolve
  `<swift/bridging>` from the copy vendored in `sdk/`; only the engine's
  `BUILD.gn` needs the toolchain's include directory, overridable with
  `$STARLING_SWIFT_INCLUDE` or `$STARLING_SWIFT_TOOLCHAIN`.
- **Never forward the engine's env knobs as empty strings.** They are read with
  a bare `getenv()`, and `""` is non-NULL in C: `FLUTTER_DRM_CONNECTOR=""` makes
  the connector filter reject every output, giving
  `[DRM] No connected connector found` on a perfectly good display. Forward
  optional vars only when non-empty (see `build/run-desktop.sh`).
- **If the shell dies uncleanly** it leaves `/tmp/xdg-starling-<uid>/wayland-0.lock`
  and the next run listens on `wayland-1`; clients must use the socket from the
  current run's `wayland_server: listening on wayland-N` log line.
- `pkill -f <word>` matches its own `bash -c` line — use `pkill -x`.
- **On a dual-GPU laptop the VAAPI probe fails once, harmlessly.** The shell
  probes every render node, so a machine with a discrete card on `nouveau`
  alongside the iGPU logs
  `libva: nouveau_drv_video.so init failed` / `Failed to initialise VAAPI
  connection: 2` for that node and then succeeds on the other. It reads like the
  encoder is broken. The line that actually decides is
  `[Recording] zero-copy VAAPI encoder ready`; if that is present, recording is
  fine. Check which node is which with
  `basename $(readlink -f /sys/class/drm/renderD129/device/driver)`.
- **An idle desktop presents rarely, so `shell-drive.py "shot"` can time out**
  on a healthy shell. The screenshot is taken in the present callback, and
  `shot()` gives up after 6 s with `screenshot never appeared — is the shell
  running?` — while the `.ppm` lands a moment later. Precede a shot with a
  `move` (or any input) to wake the compositor:
  `sudo build/shell-drive.py "move 640 400" "sleep 1" "shot /tmp/x.png"`.
- **`sg` is not installed on a stock 26.04**, so the usual one-liner for
  running something with a group you have not logged in for again does not
  exist. Use sudo instead — and note the flag is `-P`, not
  `--preserve-groups`, which is rejected with an unhelpful bare
  `invalid option provided`:

  ```bash
  sudo -u "$USER" -g video env HOME="$HOME" build/run-desktop.sh --no-stage
  ```
