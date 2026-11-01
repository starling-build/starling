#!/bin/bash
# test/tools/stamp.sh [-r REV] PATH… — the STAMP of a set of inputs: one line per
# path with its git tree/blob hash (as of REV, or as the WORKING TREE when no -r is
# given, so a fix can be stamped before it is committed and the stamp equals what
# `git rev-parse HEAD:PATH` says after), then the engine's commit and the font source.
# Scores stored beside a stamp are valid for any tree whose stamp is the same.
# Never put the scores directory itself among the PATHs: committing scores must not
# invalidate them.   ENGINE_REPO (default <repo>/engine), STAMP_FONTS (default bundled/windows)
cd "$(dirname "$0")/../.." || exit 2
REV=""; [ "${1:-}" = "-r" ] && { REV=$2; shift 2; }
if [ -z "$REV" ]; then
  T=$(mktemp -d); export GIT_INDEX_FILE=$T/index
  git read-tree HEAD && git add -A -- "$@" 2>/dev/null
  TREE=$(git write-tree); REV=$TREE
fi
for p in "$@"; do printf '%s %s\n' "$p" "$(git rev-parse "$REV:$p" 2>/dev/null || echo missing)"; done
printf 'engine %s\n' "$(git -C "${ENGINE_REPO:-engine}" rev-parse HEAD 2>/dev/null || echo unknown)"
# The engine LINKED, not the repo's pin (STARLING_ENGINE_OUT, else the first
# engine/src/out/host_release* here), since the checkout's HEAD says nothing about what was
# built when (Linux's StarlingText* exports, 968d6ffad3e, moved scores with no change in this repo).
EO=${STARLING_ENGINE_OUT:-}
[ -n "$EO" ] || for d in engine/src/out/host_release_arm64 engine/src/out/host_release; do [ -d "$d" ] && { EO=$d; break; }; done
LIB=$(ls "$EO"/libflutter_engine.so "$EO"/libFlutterMacOS.dylib "$EO"/libflutter_engine.dylib "$EO"/flutter_engine.dll "$EO"/flutter_windows.dll 2>/dev/null | head -1)
if [ "$(uname)" = Linux ] && [ -n "$LIB" ] && command -v nm >/dev/null 2>&1; then
  # On Linux the library's BYTES differ between builds of one source in different checkouts (paths
  # and build ids are embedded), which made every session's stored scores a stranger's. What the
  # binaries depend on is the exported API and what the engine was patched with: the sorted list of
  # defined dynamic symbols (catches a missing export, as 968d6ffad3e was) and the patches/ directory
  # of the engine repo (names and contents), beside the engine commit above.
  ENGINE_TOP=$(git -C "${ENGINE_REPO:-engine}" rev-parse --show-toplevel 2>/dev/null)
  printf 'enginesyms %s\n' "$(nm -D --defined-only "$LIB" | awk '{print $NF}' | LC_ALL=C sort | sha256sum | cut -c1-16)"
  printf 'enginepatches %s\n' "$( [ -d "$ENGINE_TOP/patches" ] && (cd "$ENGINE_TOP" && find patches -type f | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -c1-16) || echo none)"
else
  printf 'enginelib %s\n' "$( [ -n "$LIB" ] && { shasum -a 256 "$LIB" 2>/dev/null || sha256sum "$LIB"; } | cut -c1-16 || echo unknown)"
fi
printf 'fonts %s\n' "${STAMP_FONTS:-bundled/windows}"
# The HOST's installed fonts, on Linux: the app falls back to them for glyphs the bundled faces lack,
# even in bundled mode, so installing a package moves scores with no change in this repo. The sorted
# list of font files fontconfig knows (a font added, removed or replaced on a host changes it).
if [ "$(uname)" = Linux ] && command -v fc-list >/dev/null 2>&1; then
  printf 'hostfonts %s\n' "$(fc-list --format '%{file}\n' 2>/dev/null | LC_ALL=C sort -u | sha256sum | cut -c1-16)"
fi
[ -n "${T:-}" ] && rm -rf "$T"
exit 0
