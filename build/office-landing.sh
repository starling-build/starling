#!/usr/bin/env bash
# Prepare the Slides-powered landing page from built native and web Office apps.
# OFFICE_BIN can select a native build. Serve ui/openoffice after this command.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OFFICE_BIN="${OFFICE_BIN:-$REPO/apps/OfficeApp/.build/release/OfficeApp}"
[ -x "$OFFICE_BIN" ] || { echo "Build native OfficeApp first" >&2; exit 1; }
[ -f "$REPO/.stage-web-OfficeApp/app.wasm.gz" ] || { echo "Build web OfficeApp first" >&2; exit 1; }
mkdir -p "$REPO/ui/openoffice/slides"
"$OFFICE_BIN" --landing-deck "$REPO/ui/openoffice/slides/landing-wide.pptx"
"$OFFICE_BIN" --landing-deck "$REPO/ui/openoffice/slides/landing-tall.pptx" --portrait
python3 - "$REPO" <<'PY'
from pathlib import Path
import hashlib,json,shutil,sys
root=Path(sys.argv[1]); stage=root/'.stage-web-OfficeApp'; site=root/'ui/openoffice'
files=[stage/name for name in ['starling.js','font-loader.js','keymap.js','app.wasm.gz']]
files+=sorted((stage/'fonts').glob('*'))+sorted((stage/'skwasm').glob('*'))
files=[p for p in files if p.is_file()]
h=hashlib.sha256()
for p in files:h.update(str(p.relative_to(stage)).encode());h.update(p.read_bytes())
base='runtime/'+h.hexdigest()[:16]+'/'
for p in files:
 out=site/base/p.relative_to(stage);out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,out)
manifest=json.loads((stage/'fonts/manifest.json').read_text())
for font in manifest:font['url']=base+font['url']
(site/base/'fonts/manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(site/'runtime.json').write_text(json.dumps({'base':base},indent=2)+'\n')
print('Prepared landing page:',site,'runtime:',base)
PY
