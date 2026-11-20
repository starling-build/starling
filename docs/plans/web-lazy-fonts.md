# Web build: fonts that load when a document needs them

Status: design (lenovo-3, 2026-11-01), for starling-bd. Not built. The
prototype waits for amd-perf's bundle (names below are placeholders until
they answer) and for lenovo-2's collection call.

## Why

amd-perf is adding about 105 MB of fonts to the Office app: the Noto CJK
collections, Arabic, Hebrew, Thai, Devanagari, emoji. The desktop reads them
from disk. The browser must not fetch them at start-up: the page today ships
the Latin set (Carlito, Selawik, DejaVu Sans eager; Liberation, Caladea, Noto
Sans, Poppins and so on lazy) and is about 4 MB of wasm plus 23 MB of fonts
before laziness.

## What is already there (so we extend it, not replace it)

- `build/web-app.sh` stages `Resources/fonts/*.ttf|*.otf` into `fonts/` and
  writes `fonts/manifest.json`: `{url, families[], lazy?, fallback?}`.
  A trailing `?` in the script's table makes an entry `lazy`, a trailing
  `!` makes it a glyph `fallback`. **It does not look at `*.ttc` at all.**
- `web/host/font-loader.js` (`createFontLoader`, tested by
  `test/web/font-loader-test.mjs`) fetches a lazy family as a unit — all
  its files — registers each under every alias, then calls
  `starling_fonts_changed`, which tells the framework fonts changed and
  schedules a frame. Failures show once, retry only on a click.
- The trigger is the family NAME: `ParagraphBuilder.familiesWithFallbacks`
  calls `starling_host_request_font` for each family a style names, once.
  `OfficeFonts` already names script families in its fallback lists ("Noto
  Naskh Arabic", "Noto Sans Thai", "Noto Serif CJK SC" for 宋体, "Noto Sans
  CJK JP/SC/TC" by the face's script). Any family named in a manifest entry
  therefore loads on demand with no code change.
- `index.html` has the "Loading document fonts…" chip fed by `onFontStatus`;
  `starling.fontsPending()` is what exports and screenshot scripts wait on.

## What is missing

1. **Characters, not names.** A run in Calibri with Chinese text names no CJK
   family. Natively the system picks one by character; skwasm sees only the
   fixed `fallbackFamilies` (DejaVu Sans, Selawik). Nothing asks for the
   file, and the text draws as boxes.
2. **Collections.** One .ttc holds several faces (Sans CJK: JP, KR, SC, TC, HK
   and the Mono ones). `typeface_create(data)` takes no face index, so skwasm
   would register face 0 (JP) only, and Chinese text would get Japanese
   forms for shared characters. It needs a skwasm export taking an index
   (the web twin of lenovo-2's `LoadFontFromFileFace`).
3. **Memory and copies.** `registerFont` makes a new SkData per alias; a
   19 MB collection under four names is 78 MB of copies. One SkData per
   file, one typeface per face from it.
4. **Order.** `fallbackFamilies` is appended in the order files arrive, so
   which face wins for a character depends on the network. It must be the
   manifest's order.
5. **Waiting.** Layout runs before the face arrives; the line breaks twice.

## Measured (this server, fonts-noto-cjk 2024-08)

| file | size | gzip |
|---|---|---|
| NotoSansCJK-Regular.ttc (all regions) | 19.5 MB | 15.6 MB |
| one region (SC) as a single OTF | 16.4 MB | 13.6 MB |
| SC subset: GB2312 + Big5 + JIS + KS repertoires, 31.5k code points | 11.2 MB | 9.1 MB |
| Sans Bold / Serif Regular / Serif Bold collections | 20.1 / 26.4 / 27.4 MB | — |

So splitting by region saves nothing (the collection shares glyphs between
regions; four separate files would be 65 MB), and a character subset saves
about a third while losing coverage the desktop has. **Ship the collection as
Noto makes it and fetch it once**, about 15 MB over the wire for the first
Chinese, Japanese or Korean document. That is the cost to design around, not
to engineer away.

## Design

### 1. The manifest says which script a file serves

`fonts/manifest.json` entries gain two optional fields:

```
{"url": "fonts/NotoSansCJK-Regular.ttc.gz", "lazy": true, "gzip": true,
 "faces": [{"index": 2, "family": "Noto Sans CJK SC"}, {"index": 3, "family": "Noto Sans CJK TC"}, ...],
 "scripts": ["Hani", "Hira", "Kana", "Hang"], "fallback": true, "weight": 400}
```

- `faces`: face index → family, replacing the `families` alias list for
  collections. Plain files keep `families`.
- `scripts` (ISO 15924): the character scripts the file is the fallback for.
  `fallback` + `lazy` together mean "when loaded, add me to the glyph
  fallback list" (today `fallback` is only read for eager entries).
- `gzip`: GitHub Pages sends no Content-Encoding for fonts
  (`build/web-deploy.sh` has this problem for the wasm and inflates `.gz` in
  the page). The loader does the same: fetch `*.gz`, inflate with
  `DecompressionStream('gzip')`, so the wire carries 15.6 MB, not 19.5.
  The browser's HTTP cache keeps the .gz; `releases/<sha>/` paths make them
  immutable.

`build/web-app.sh` writes this from ONE table that both the web and the
desktop read (see "One mapping" below) instead of the `case` list it has
now.

### 2. Two ways to ask, one loader

- **By name** (exists): a style names a family → `request_font(family)`.
- **By character** (new): `AddTextSafe` scans the text it is given. Cheap:
  it only classifies each scalar into a script bucket by range (no ICU), keeps
  a `Set<Script>` of those already requested, and for a new bucket calls a new
  host import `starling_host_request_script(utf8 script code)`. The page maps
  the script to a manifest entry (`scripts`) and loads it exactly as a named
  family. Latin, Greek and Cyrillic are covered eagerly (Carlito, DejaVu) and
  never ask.
- Which region's face (SC vs TC vs JP vs KR) a Han character gets follows the
  RUN's language when the document says it (`w:lang`, `a:latin lang`) and
  otherwise the document's East Asian font name (SimSun → SC, MingLiU →
  TC, MS Mincho → JP): the same decision `OfficeFonts` already makes for
  named faces. The script request carries a region hint (`Hani:SC`) and
  falls back to SC.

### 3. Prefetch when a file opens, not when the first line is drawn

`FlutterWeb/WebFiles.swift` hands the opened file's bytes to the app. Before
the first layout the Office loader (`Docx`/`Pptx`/`Xlsx` read) already walks
all text; it adds a pass (`DocumentScripts.scan`) returning the scripts and
the region hints it saw, and calls `starling_host_request_script` for each.
The page then holds the document's FIRST layout until the files arrive or 4 s
pass, whichever is first, showing the existing chip. Why hold: laying out with
boxes and again with the real face re-breaks every Chinese line and can change
the page count — the 30-page vs 26-page confusion we have seen before is the
kind of thing a flash of the wrong count would repeat. After 4 s we lay out
with what we have and relayout on arrival (the path that exists).

For typing and IME: the first CJK keystroke has no prefetch to rely on. We
also start an idle prefetch for the page's `navigator.language` (zh-CN → SC, zh-TW/HK → TC,
ja → JP, ko → KR: the one face the language names) 3 s after start-up
when the connection is not metered (`navigator.connection.saveData` false),
so the common reader never types into boxes.

### 4. What shows while it loads

- Layout and paint use the current fallback list. For a script whose file
  is **pending**, the builder sets the run's text colour to alpha 0, so the
  page shows no field of squares. The line breaks and metrics are those of
  the missing-glyph box (about an em wide, close to a CJK advance), so
  the first layout is near the final one, and the text appears when the face
  does. A document mostly in Chinese is blank for the seconds it takes, with
  the chip saying why. This is the only part that touches the paragraph
  builder's paint; the prototype tries it and falls back to plain boxes if
  skparagraph resists.
- Failure: the existing "Some fonts could not load" chip and Retry; the text
  stays blank for that script rather than boxes, and PDF/PNG export refuse
  with a message naming the script (they already wait for `fontsPending()`).
- Export and print wait for `fontsPending() == 0` and force-request every
  script the document has.

### 5. Weights and families

Bold CJK is another 20 MB. Load the Regular on first need. Load Bold only
when a bold run in that script is laid out; until it arrives the run uses the
Regular face (skwasm synthesizes bold), then it swaps. Same for Serif
(宋体/明朝 map to Noto Serif CJK): the Serif collection loads only when a
document names a serif East Asian face. Mono CJK faces inside the Sans
collection are not exposed by name.

Emoji (11 MB colour font) loads on the first emoji scalar. Arabic, Hebrew,
Thai and Devanagari are 0.1–0.6 MB each and are simply lazy by name already.

### 6. One mapping

The desktop and the web must choose the same face for the same character, or
`test/office-layout.sh` (web vs desktop line for line) fails on any
non-Latin document. So: **one table**, checked in beside the fonts —
`Resources/fonts/scripts.json`: file, face index → family, scripts, weight,
fallback order. `OfficeFonts` (native registration), `build/web-app.sh`
(manifest) and the prototype's script classifier all read it. amd-perf owns
the file names and the table's first version; the web adds only `gzip`.

### Engine / host work

| piece | who | note |
|---|---|---|
| `typeface_create` with a face index (skwasm export, e.g. `typeface_createFace(data, index)`), bound to 0 in older skwasm like our other additions | lenovo-2 / engine | web twin of `LoadFontFromFileFace` |
| `registerFont(bytes, faces)` shares one SkData | web/starling.js | |
| `starling_host_request_script` import + scan in `AddTextSafe` + document scan | sdk / OfficeApp | |
| `font-loader.js`: `.gz`, `faces`, `scripts`, manifest-order fallback, hold-first-layout | web | extend the existing test |
| `web-app.sh`: `.ttc` handling, one table | build | |
| alpha-0 for runs in a pending script | sdk | try; fall back to boxes |

### Tests

- `test/web/font-loader-test.mjs`: scripts → entry, face index registration,
  fallback order independent of arrival order, `.gz` inflate, bold only on
  demand.
- A browser gate (`web-drive.mjs`): open a Chinese docx with an empty
  cache; assert zero CJK bytes fetched before the open, exactly one Regular
  collection after, the same line count as the desktop dump, and no boxes in
  a screenshot taken after `fontsPending() == 0`.
- Page-weight gate: the eager set stays under its current size; any new
  eager font fails `build/tools/wasm-size.py`-style budget.

## Open questions

- amd-perf: file names, the family per face index, the script table's home.
- lenovo-2: is the collection call usable from wasm (no filesystem), i.e. does
  it take bytes and an index? If it only takes a path, the web needs the
  separate export above.
- Offline use: a service worker that precaches the Latin set and caches CJK
  on first use is cheap once the paths are immutable; not designed here.
