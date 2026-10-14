#!/usr/bin/env bash
# Package the static Starling/desktop site and standalone Office site.
# No OfficeApp build, slides, fonts, or WASM runtime is needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/.stage-landings}"
if [ -e "$OUT" ]; then
    echo "error: output already exists: $OUT (choose a fresh directory)" >&2
    exit 1
fi
mkdir -p "$OUT/starling/desktop" "$OUT/office/img"
cp "$ROOT/ui/index.html" "$ROOT/ui/styles.css" "$ROOT/ui/main.js" "$ROOT/ui/CNAME" "$OUT/starling/"
cp -R "$ROOT/ui/img" "$ROOT/ui/video" "$OUT/starling/"
cp "$ROOT/ui/desktop/index.html" "$OUT/starling/desktop/"
cp "$ROOT/ui/openoffice/index.html" "$ROOT/ui/styles.css" "$OUT/office/"
cp -R "$ROOT/ui/img/office" "$OUT/office/img/"
cp "$ROOT/ui/openoffice/download.html" "$ROOT/ui/openoffice/download.css" "$ROOT/ui/openoffice/download.js" "$OUT/office/"
cp -R "$ROOT/ui/openoffice/images" "$OUT/office/"
printf 'openoffice.starling.build\n' > "$OUT/office/CNAME"
touch "$OUT/starling/.nojekyll" "$OUT/office/.nojekyll"
python3 - "$OUT" <<'PY'
import hashlib
from pathlib import Path
import sys

root = Path(sys.argv[1])
for site in [root / 'starling', root / 'office']:
    css = hashlib.sha256((site / 'styles.css').read_bytes()).hexdigest()[:12]
    script = site / 'main.js'
    js = hashlib.sha256(script.read_bytes()).hexdigest()[:12] if script.exists() else None
    for html in site.rglob('*.html'):
        source = html.read_text().replace('styles.css"', f'styles.css?v={css}"')
        if js:
            source = source.replace('main.js"', f'main.js?v={js}"')
        for asset in ['download.css', 'download.js']:
            if (site / asset).exists():
                version = hashlib.sha256((site / asset).read_bytes()).hexdigest()[:12]
                source = source.replace(f'{asset}"', f'{asset}?v={version}"')
        for icon in (site / 'img' / 'office').glob('*.svg'):
            version = hashlib.sha256(icon.read_bytes()).hexdigest()[:12]
            source = source.replace(f'{icon.name}"', f'{icon.name}?v={version}"')
        for app in ['writer', 'slides', 'sheets']:
            source = source.replace(f'href="apps/{app}/"', f'href="https://{app}.starling.build/"')
            source = source.replace(f'href="openoffice/apps/{app}/"', f'href="https://{app}.starling.build/"')
        html.write_text(source)
PY
printf 'Starling + Desktop: %s/starling\nOffice: %s/office\n' "$OUT" "$OUT"
