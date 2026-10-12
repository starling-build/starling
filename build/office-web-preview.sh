#!/usr/bin/env bash
# Put the three working editors beside the local Office landing page.
# Build OfficeApp first; optionally point at another compatible stage.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${1:-$ROOT/.stage-web-OfficeApp}"
[ -f "$STAGE/app.wasm" ] || { echo 'Build OfficeApp with build/web-app.sh first.' >&2; exit 1; }
for app in writer slides sheets; do
    DEST="$ROOT/ui/openoffice/apps/$app"
    mkdir -p "$DEST"
    cp -R "$STAGE"/. "$DEST/"
    python3 "$ROOT/build/tools/office-web-start.py" "$DEST" "$app"
done
printf 'Editors ready under ui/openoffice/apps/ (serve ui/ for the landing page and apps).\n'
