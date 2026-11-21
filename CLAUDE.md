# starling-desktop — project guide

The Starling desktop: Swift shell + compositor + apps + the Flutter→Swift
framework (`sdk/`), running on the Flutter engine's C core from the sibling
repo **starling-engine**, reached through the repo-root `engine` symlink that
`./bootstrap.sh` makes after cloning. Read starling-engine's `CLAUDE.md` too:
a feature often touches both repos, and both get committed. (`sdk/` spent a
stretch as its own repo; it was folded back as a git subtree in 2026-08 —
`git subtree split --prefix=sdk` re-extracts it if that ever reverses.)

Everything needed to build, run, drive, and package the desktop is in this repo
(`build/`). The older `starling-os` repo still holds the Bazel-built Starling OS
image and its QEMU boot gates; the desktop dev loop no longer depends on it.

**Branches: work on mainline, in both repos.** This repo's mainline is `main`.
The engine's is **`starling`** — *not* `main`. starling-engine is a fork of
`flutter/flutter` carrying upstream's full history, so it has hundreds of
branches including upstream ones; `starling` is the repo default
(`origin/HEAD -> origin/starling`) and the only one we ship from. Commit
straight to mainline in both; do not open a feature branch, and do not offer
one, unless asked. `prime-render-offload` is **retired** in both repos — do
not work on it or check it out (it holds nothing `starling` lacks). A change
that spans both repos is committed in both, mainline to mainline.

**Release branches pair by name, in both repos.** A release cuts the same
branch in each — `release-0.3.0` in this repo and `release-0.3.0` in the
engine — so checking out one name in both gets a buildable pair. Do not pin
the engine by writing a commit into the release notes: that was the old
convention and it went stale inside one release, because the notes named an
engine commit while the fix the notes described sat unpushed on top of it.
The branch is the record; the notes name the branch.

**Desktop, display, Wayland, apps, iOS or deploy work? Read `docs/claude-desktop.md` first.**
It holds the run/deploy recipe, the display and headless rules, iOS, packaging, the app
registry, the styles, and the compositor traps. Three rules from it apply to every session,
because breaking them blanks the real screen of the person using this machine:
never write `off` to a DRM connector's `status` (and never write anything to `eDP-1`'s);
read an EDID with `cat`, never `stat`; never hardcode a `cardN` number.

## Layout

```
sdk/       the Flutter→Swift framework port (SwiftPM package "FlutterSwift"),
           no Dart VM. In-repo — edit it here. Has its own CLAUDE.md.
engine      -> SYMLINK to a starling-engine checkout
host/       the windowed host (FlutterRunner + GLFWBridge): run a Swift Flutter
            app in an ordinary window instead of compositing through the shell.
            Demos only — Examples/HelloWindow. Stayed behind
            when the framework was extracted, because it drags a vendored libglfw
            and resolves assets under /usr/share/starling.
registry/  the app registry — the ONE description of every app the desktop knows
           about (catalog.d/*.app), shared by the shell and the App Store
shell/     DesktopShellApp package — its own CLAUDE.md in Sources/DesktopShellApp/
  Sources/DesktopShellApp/   Shell/ Window/ Compositor/ Wayland/ Fluent/ Launcher/ Portal/ Utils/
                             (Fluent/ is the Windows style's chrome; the macOS
                              style's lives in Shell/ — see Standing directions)
  Sources/WaylandServer/     the Wayland compositor, in C (~5k lines)
  Sources/PortalService/     xdg-desktop-portal (sd-bus/basu)
  Sources/X11Server/         in-tree X server (DRI3/Present) — do not touch unless asked
apps/      first-party apps, one SwiftPM package each
build/     stage.sh (assembles the tree — the single definition of the layout),
           run-desktop.sh (run it), shell-drive.py (input + screenshots),
           package-desktop.sh (Ubuntu .deb), session/ (the four
           system-integration files it installs verbatim), app-run/app-install,
           tools/ (drm_screenshot), vendored flutter_assets, bundled wallpapers
           live in shell/Resources, ios-app.sh (stage.sh's iOS counterpart)
macos-compat/  research: running unmodified Mach-O macOS binaries on Linux.
               Not part of the desktop, and deliberately not part of the SDK.
docs/plans/    design notes, including standalone-sdk.md — the framework's
               spell as its own repo, reversed 2026-08 (folded back for one
               public repo; re-splittable via git subtree)
```

## Build & iterate

- Shell/app Swift change → `build/build-all.sh` (sdk once into the repo-root
  **`.build-shared`**, then shell + apps in seconds), then
  `build/run-desktop.sh` (it re-stages first). **`stage.sh` reads ONLY
  `.build-shared`** (`$STARLING_SCRATCH`) — a bare `cd shell && swift build`
  compiles into `shell/.build`, which nothing stages: fine as a compile check,
  invisible on the desktop, and the staged binary's fresh mtime (it is
  `install`(1)'s copy time) will happily tell you otherwise. One package alone:
  `swift build -c release --package-path apps/<App> --scratch-path
  $PWD/.build-shared`. Staging prints the tree's `BUILD-STAMP` (git sha +
  build time) and warns if a package-local scratch holds newer binaries —
  believe those two lines over any mtime.
- 3D desktop renderer → `build/build-filament.sh` once (~20 min); after
  that `build-all.sh` builds `libstarling_room.so` beside the shell and
  says `skipped` when Filament is missing (the .deb then ships the GL
  room, not the city). The city world is checked in under
  `shell/Resources/Worlds/city`; regenerate with `build/tools/voxel-world.py
  --no-sky` and commit the result.
- Engine C++ change → rebuild in the **engine repo** (`ninja -C engine/src/out/host_debug
  libflutter_linux_drm.so libflutter_engine.so`) — no shell relink needed.
  Rebuild host_release too before packaging.
- **A release build links against host_release, not host_debug.** The two
  directories are not interchangeable: `shell/Package.swift` defaults
  `engineOutDir` to `../engine/src/out/host_debug`, so that is the `-L` path
  AND the baked rpath, while `build/stage.sh` stages `host_release` into the
  package. Build a release with

      ninja -C engine/src/out/host_release libflutter_engine.so libflutter_linux_drm.so
      STARLING_ENGINE_OUT=$PWD/engine/src/out/host_release \
          swift build -c release --package-path shell

  and the shipped binary is linked against the library it will actually load.
  Leave `STARLING_ENGINE_OUT` unset and you are building a release shell
  against the *debug* engine, then shipping the release one beside it — fine
  while the two export the same symbols, and a runtime `symbol lookup error`
  on the first call the moment the engine's API grows. That failure surfaces
  only when the new call is reached (lazy binding), so it looks like "the
  feature crashes the shell", not "the build was wrong". Adding an engine
  export and rebuilding only one output is the same trap from the other side:
  host_debug missing it fails the *link*, host_release missing it fails at
  *runtime*.
- Test: `test/run.sh` (~0.4s, no GPU — run it on every change),
  `test/run.sh --build` to compile everything and the .deb,
  `sudo test/run.sh --functional` to drive a live desktop, and `test/vm.sh`
  for the release gate (.deb on a clean VM through a real GDM login — the only
  tier that can see privilege-path bugs). See `test/README.md`.
- Building on a machine with **nothing installed** (both repos, toolchains,
  apt packages, `gclient`) → `docs/BUILDING.md`.

**Ubuntu 26.04 LTS is the base platform**, for dev, test, and the shipped .deb.
The 6.2.4 toolchain is an ubuntu24.04 build, so 26.04 needs two fixes — both
already in-tree, so `swift build` takes no special flags: `bootstrap.sh` adds
the toolchain's `libxml2.so.2` symlink, and every `Package.swift` carries
`glibcMathCompat` (`-D_GLIBCXX_MATH_H` + a force-included glibc `math.h`) for
glibc 2.43's `<cmath>` clash. Delete both when swift.org ships a 26.04
toolchain. Why, in full: `docs/BUILDING.md`.

## Standing directions

- **Never post code or file contents to external paste services.**

## Traps that have cost real time

Framework (`sdk/`):
- **A `Positioned` with `right:` and no width lays out correctly and
  hit-tests as nothing.** The child sizes itself, paints exactly where you
  expect, and has no box for the pointer to hit — so the taskbar's clock and
  status buttons were visible, hovered nothing and did nothing. Span the full
  width and align inside it (`left: 0, right: 0` + `Row(mainAxisAlignment:
  .end)`) rather than anchoring by one edge. "Visible but dead to the
  pointer" is the signature.
- `ColoredBox` hit-tests **opaque even at alpha 0** — use a bare
  `SizedBox(expand:)` with `Listener(behavior: .translucent)` for overlays.
- Registering `onDoubleTap` kills **both** tap and double-tap on the DRM
  embedder (`Foundation.Timer` never fires there). Detect double-clicks
  manually inside `onTap`; use `DispatchQueue.main.asyncAfter` + a generation
  token for any timer.
- A widget tree with no `FluentApp`/`MacosApp` above it **must** be wrapped in
  `Directionality`.
- Lazy sliver list children don't rebuild on ancestor rebuild — theme/state
  changes need a bloc `.refresh` poke.
- Changing a lazy list's cell SHAPE needs a `key` on the ListView. An
  in-place update does rebuild inflated children with the new builder, but a
  child whose root widget TYPE changed remounts through the sliver element's
  `insertRenderObjectChild` — a no-op there (children arrive via
  `createChild` during layout) — so the fresh render objects go nowhere and
  the old cells keep painting inside the new extents. Keying by mode
  remounts the whole sliver down the working path. (Files' view modes.)
- Element **remount is the dominant update path** (no `updateRenderObject`); if
  fresh content never composites, suspect paint marking.
- `print()` is block-buffered through pipes — debug with raw `write(2, …)`.
- Widgets have **two spellings**: the ported `children:`/`child:` initializers
  (canonical, 1:1 with Dart) and the trailing-closure overloads in
  `Widgets/ResultBuilders.swift`, which add `if`/`for`/`switch` inside the tree.
  They compile to the identical tree. **Adding a parameter to a ported widget
  init means adding it to that widget's builder overload too** — otherwise the
  block form silently cannot express it, with no warning at the call site.
  `test/lint.py` compares the two and fails on drift.

Build / runtime:
- **Clang normalises `-L` paths lexically, and `engine` is a symlink out of
  the tree.** A path built as `<repo>/engine/../<something>` is correct on
  disk — the kernel resolves the symlink first, so it lands beside the
  *engine checkout*, not beside the repo. Clang collapses `engine/..`
  textually and looks beside the repo instead. The build then fails with
  `cannot find -lflutter_engine` against a `-L` you can read on the command
  line and confirm by hand: `ls` finds the library, and `ld` with the same
  `-L` links fine, because ld does no such rewrite. Only `clang -###`
  reveals the substitution. Anything that composes a path through
  `engine/..` must canonicalise it — `resolvingSymlinksInPath()`, never
  `.standardized`, which does exactly the collapse clang does. (`sdk` used
  to be the second such symlink; it is a real directory now.)
- **Never forward the engine's env knobs as empty strings.** Several are read
  with a bare `getenv()`, and `""` is non-NULL in C: `FLUTTER_DRM_CONNECTOR=""`
  makes the connector filter compare every output against `""` and reject them
  all — `[DRM] No connected connector found` on a perfectly good display.
  Forward optional vars only when non-empty (see `build/run-desktop.sh`).
- App RUNPATHs must be **absolute** (`appPackageDir` in each `Package.swift`,
  mirroring `sdk/`). They used to be cwd-relative and worked only because the
  shell's cwd happened to be `apps/DesktopShellApp`.
- **A plain `swift build` can silently give you a stale `sdk/`.** Each package
  compiles its own copy of the framework, and their incremental state does not
  always notice that `sdk/` moved underneath them. Adding a *new file* there is
  the worst case: dependents fail with `cannot find <symbol> in scope` even
  though the manifest lists it. Editing an existing file is more dangerous,
  because it fails silently — you get a binary built from the old code and no
  error at all. This has already invalidated one round of testing and produced
  a confidently wrong conclusion about where a bug was — twice: the second
  time an hour went to "stale" rendering because the rebuilt scratch was
  `shell/.build` while the desktop stages `.build-shared` (see Build &
  iterate; the framework is `libFlutterShared.so`, so the app *binary* never
  contains the change and `nm` on it proves nothing). When a change to `sdk/`
  appears to have no effect, before theorising — with the scratch that your
  binary actually comes from (`.build-shared` for anything staged,
  `<pkg>/.build*` only for standalone builds like `.build-gtk`):

      rm -f  .build-shared/release.yaml .build-shared/build.db
      rm -rf .build-shared/*/release/Flutter.build
      build/build-all.sh            # or swift build twice: the first re-plans

- **On Windows a cold `swift build` always fails, and the failure is a lie.**
  It dies inside the MSVC standard library —
  `xmemory: no matching function for call to 'construct_at'`, under an
  instantiation of `std::vector<std::atomic<bool>, _Parallelism_allocator<…>>`
  from `<execution>`. Nothing in this tree includes those headers; Swift's C++
  importer walks them while building the `std` module, and `std::atomic` is not
  copyable. It is a toolchain bug (Swift 6.2.3 / MSVC 14.44). The failing run
  still writes a usable `.pcm`, so *the same command* run again gets further —
  and it needs one pass per interop configuration: `FlutterSwiftBridge`, then
  `Flutter` (language mode 5 keys a separate module), then it builds. Use
  `sdk/tools/build-windows.ps1` (`-PackagePath` for the app packages), which
  loops only while that exact signature appears, so a real error still fails
  once and immediately. Do not "fix" this by warming with a different target:
  different flags mean a different module, and it does nothing.
