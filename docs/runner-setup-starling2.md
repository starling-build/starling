# Setting up a render-gate runner from source (starling2, 2026-11-20, s2)

Everything is built on the box itself; proof: 50/50 PDFs byte-identical to AMD at the same commit.

1. Engine: clone public starling-build/starling-engine (branch starling) at e0559255f1 under /data/gate/starling-engine,
   gclient sync, then build `host_release` with gn + ninja (libflutter_engine.so, libflutter_linux_drm.so, libflutter_linux_gtk.so).
   MISSING FROM BUILDING.md (host path): run `scripts/apply_engine_patches.sh` (22 Skia patches) BEFORE ninja,
   or font_collection_bridge.cc fails ("internalMakeGlyph is private").
   Needs the desktop apt packages (libgbm-dev etc.), else DmaBufBridge fails on gbm.h.
   If ninja complains about python3_bin_reldir.txt: unset DEPOT_TOOLS_UPDATE and run depot_tools ensure_bootstrap.
2. Swift 6.2.4: swiftly has no Ubuntu 26.04 build. Download the official
   swift-6.2.4-RELEASE-ubuntu24.04.tar.gz from download.swift.org, unpack with --strip-components=1 into
   ~/.local/share/swiftly/toolchains/6.2.4, and add
   `ln -s /usr/lib/x86_64-linux-gnu/libxml2.so.16 .../6.2.4/usr/lib/swift/linux/libxml2.so.2`.
3. OfficeApp: `swift build -c release --product OfficeApp --package-path apps/OfficeApp --scratch-path $PWD/.build-shared` (about 14 min).
4. Runner user ghrunner: member of group corpusread (corpus cache and /data/landq are 770 corpusread; nothing world-readable),
   ACL `u:ghrunner:--x` on the tool owner's home. Until the gate script reads TOOLS_HOME everywhere, ghrunner's home needs
   symlinks: ~/bin/office-env.sh, ~/.local/share/swiftly, ~/venv-word -> the tool owner's.
5. Approvals/sample/base in /data/landq are synced from AMD by cron (rsync every minute).
6. Hand-run check before starting the service: `ENGINE_DIR=... TOOLS_HOME=... test/tools/render-gate.sh <base>` as ghrunner.
   PR #36: clean, 556 s including both builds.
