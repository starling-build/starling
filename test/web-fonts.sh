#!/usr/bin/env bash
# The browser build's on-demand script fonts (docs/plans/web-lazy-fonts.md),
# in a real headless Chromium against the staged tree:
#   - a Chinese document fetches the CJK collection(s) once, Regular only,
#     and none of the other scripts' files;
#   - a document of Arabic, Thai and emoji fetches exactly those on first use;
#   - the Latin start-up fetches no script font at all.
# Needs build/web-app.sh OfficeApp --package apps/OfficeApp staged first, a
# Chromium (CHROME, default /snap/bin/chromium; a snap cannot read /data, so
# the work files live under $HOME/tmp) and node. Skips without them.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="${STAGE:-$REPO/.stage-web-OfficeApp}"
export CHROME="${CHROME:-/snap/bin/chromium}"
skip() { echo "  SKIPPED — $1"; exit 0; }
[ -f "$STAGE/fonts/manifest.json" ] || skip "no staged web tree ($STAGE)"
[ -x "$CHROME" ] || skip "no Chromium ($CHROME)"
command -v node >/dev/null || skip "no node"
grep -q '"faces"' "$STAGE/fonts/manifest.json" || skip "the staged tree has no script fonts"

WORK="$HOME/tmp/web-fonts-$$"; mkdir -p "$WORK"
PORT=$((8500 + RANDOM % 400)); export PORT=$((PORT + 1)) URL="http://127.0.0.1:$PORT/" CHROME_PROFILE="$WORK/profile"
SERVE=$((PORT - 1)); URL="http://127.0.0.1:$SERVE/"
python3 -u "$REPO/build/tools/web-serve.py" "$STAGE" "$SERVE" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; sleep 1; rm -rf "$WORK" 2>/dev/null || true' EXIT
for _ in $(seq 1 20); do curl -sf "$URL" >/dev/null && break; sleep 0.5; done

python3 - "$WORK" <<'PY'
import sys, zipfile
work = sys.argv[1]
def docx(path, lines):
    body = ''.join(f'<w:p><w:r><w:t xml:space="preserve">{t}</w:t></w:r></w:p>' for t in lines)
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        z.writestr('_rels/.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        z.writestr('word/document.xml', f'<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>{body}<w:sectPr/></w:body></w:document>')
docx(work + '/zh.docx', ['温岭市市政设施养护管理标准', '第一章 总则'])
docx(work + '/mixed.docx', ['مرحبا بالعالم', 'สวัสดีชาวโลก', 'emoji \U0001F600\U0001F680'])
PY

fails=0
drive() { node "$REPO/build/tools/web-drive.mjs" wait 12000 click 700 400 chord ctrl o wait 1500 setfile "$1" settle "$2" 2>&1 | grep -v "^log:" || true; }
fetched() { { tr -d '\0' < "$WORK/serve.log" | grep -a '"GET /fonts/Noto' | sed -E 's/.*GET \/fonts\/([^ ]+) .*/\1/' | sort | uniq -c; } || true; }
check() { # name expected-list
    local got; got="$(fetched | awk '{print $2 ":" $1}' | tr '\n' ' ')"
    if [ "$got" = "$2" ]; then echo "  ok   $1: ${got:-no script fonts}"; else echo "  FAIL $1: fetched [$got], expected [$2]"; fails=$((fails + 1)); fi
}

# Fresh browser profile each case, so the HTTP cache cannot hide a fetch.
sleep 2; rm -rf "$CHROME_PROFILE" 2>/dev/null || true; : > "$WORK/serve.log"
node "$REPO/build/tools/web-drive.mjs" wait 12000 >/dev/null 2>&1 || true
check "Latin start-up" ""
sleep 2; rm -rf "$CHROME_PROFILE" 2>/dev/null || true; : > "$WORK/serve.log"
drive "$WORK/zh.docx" zh.docx
check "Chinese" "NotoSansCJK-Regular.ttc:1 "
sleep 2; rm -rf "$CHROME_PROFILE" 2>/dev/null || true; : > "$WORK/serve.log"
drive "$WORK/mixed.docx" mixed.docx
check "Arabic, Thai, emoji" "NotoColorEmoji.ttf:1 NotoNaskhArabic-Regular.ttf:1 NotoSansArabic-Regular.ttf:1 NotoSansThai-Regular.ttf:1 "

# (Ink = dark pixels on the canvas: mid-load it must match the screen before
# the open — the document not drawn, no boxes — and differ once text is up.)
# Mid-load. The Chinese font is slowed to 2.5 s. The page must (1) draw no ink
# for the document while its font is on the way — no box glyphs — and (2) hold
# its first layout for that font (the page logs how long each hold lasted).
INK='(async()=>{const c=document.querySelector("canvas");const u=c.toDataURL("image/png");const i=new Image();i.src=u;await i.decode();const k=document.createElement("canvas");k.width=i.width;k.height=i.height;const x=k.getContext("2d");x.drawImage(i,0,0);const d=x.getImageData(0,0,k.width,k.height).data;let n=0;for(let p=0;p<d.length;p+=4)if(d[p]+d[p+1]+d[p+2]<240&&d[p+3]>200)n++;return n})()'
sleep 2; kill $SERVER 2>/dev/null; sleep 1
STARLING_SERVE_FONT_DELAY_MS=2500 python3 -u "$REPO/build/tools/web-serve.py" "$STAGE" "$SERVE" > "$WORK/serve.log" 2>&1 &
SERVER=$!
for _ in $(seq 1 20); do curl -sf "$URL" >/dev/null && break; sleep 0.5; done
rm -rf "$CHROME_PROFILE" 2>/dev/null || true
out="$(node "$REPO/build/tools/web-drive.mjs" wait 12000 click 700 400 chord ctrl o wait 1500 eval "$INK" setfile "$WORK/zh.docx" wait 1200 eval "$INK" eval 'window.__starlingFontHolds||[]' settle zh.docx wait 800 eval "$INK" eval 'window.__starlingFontHolds||[]' 2>&1 | grep '^eval:' || true)"
val() { echo "$out" | sed -n "${1}p" | sed -E 's/^eval: //'; }
before="$(val 1)"; mid="$(val 2)"; final="$(val 4)"
echo "  (ink before=$before mid-load=$mid final=$final; holds: $(val 5))"
if [ -n "${before:-}" ] && [ -n "${mid:-}" ] && [ -n "${final:-}" ] && [ "$mid" -le $((before + 150)) ] && [ "$mid" -ge $((before - 150)) ] && [ $((final > before ? final - before : before - final)) -gt 500 ]; then
    echo "  ok   no box glyphs while the font loads, text after"
else echo "  FAIL ink: before=${before:-?} mid=${mid:-?} final=${final:-?}"; fails=$((fails + 1)); fi
holdlast="$(echo "$out" | sed -n '5p' | sed -E 's/^eval: \[//; s/\]$//; s/.*,//')"
if [ -n "$holdlast" ] && [ "$holdlast" -ge 1500 ] 2>/dev/null; then echo "  ok   first layout waited ${holdlast} ms for the CJK face"
else echo "  FAIL the first layout did not wait for the font (holds: $(val 5))"; fails=$((fails + 1)); fi
exit $fails
