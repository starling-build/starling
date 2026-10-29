# Starling Writer / DOCX: status and gap analysis — 2026-10-28

Writer's rendering is substantially ahead of its cross-platform release validation.
The latest accepted Mac-hosted corpus run matches **99.3% of Windows Word lines and
98.2% of Mac Word lines on the 645-document Chinese corpus**. Linux now has a fresh,
private native/skwasm engine build and a passing native/browser gate. Current
Windows-native and iOS builds have not been validated against this engine set.
Rendering imported content also does not mean Writer offers Word's editing tools
for that content.

This is a read-only evidence review, not a new rendering change or release approval.
The [task board](word-gaps-tasks.md) remains authoritative for claims. Historical
sections of [office.md](office.md), [office-editor.md](office-editor.md) and
[office-overview.md](office-overview.md) contain superseded feature/test counts;
this report uses dated receipts and current source where they disagree.

## 1. Evidence boundary and latest fidelity scores

**Newest accepted rendering:** `d6e61adf` (numeric/Latin-word fitting), following
`cd963220` (opening marks), `b3a14a93` (fixed-frame first-line masks) and `bb06181a`
(WordArt). The subsequent pie-label claim `b3d2e3ae` is documentation only; private
chart controls are not accepted production changes.

The full `mac-number-gap` sweeps finished October 28 at 09:13 local time. They ran
on **macOS**, with Swift 6.2.1, bundled fonts, PyMuPDF and the pinned native bridge
`3841e45ef047247b884aa5e3868f3be917ae68041a61ed7903e18c02cca3bfd6`.
The accepted executable is
`f4310e1559b0f888795247d6bed37ab1487cf978281550f47ecaf8412073295a`.
The run began at `cd963220` plus the frozen numeric candidate; its accepted
production diff was preserved when rebased and landed as `d6e61adf`.

**Windows mode means comparison with `test/corpus/docx/word-win`; Mac mode means
comparison with `test/corpus/docx/word`. Neither label identifies the host OS.**
There are 756 documents per mode: 645 zh and 111 Apache POI.

| Reference mode / corpus | Latest mean | Median | Documents at ≥95% | October 27 snapshot mean / ≥95% | Snapshot change |
| --- | ---: | ---: | ---: | --- | --- |
| Windows / zh | 99.2971% (99.3%) | 100% | 630 / 645 | 99.3% / 628 | Rounded mean unchanged; +2 above threshold |
| Windows / POI | 90.5145% (90.5%) | 100% | 99 / 111 | 90.5% / 99 | Unchanged |
| Mac / zh | 98.2467% (98.2%) | 100% | 604 / 645 | 97.5% / 597 | About +0.7 percentage points; +7 above threshold |
| Mac / POI | 91.6555% (91.7%) | 100% | 101 / 111 | 91.6% / 101 | +0.1 point at displayed precision; threshold count unchanged |

The [October 27 snapshot](word-fidelity-status-2026-10-27.md) also estimated about
97.7% after later Mac font rules. These are **snapshot comparisons**, not a sum of
attributable gains: that document spans several source revisions. The current
reference directories have no changes between its cited `518df17c` and
`d6e61adf`; the earlier fresh-Word reprints remain in place.

### How to read these numbers

- The metric is the mean of per-document matched-line percentages, not pixel
  identity, a weighted percentage of every corpus line, editing correctness or
  a claim of complete Microsoft Word compatibility.
- Ten Windows POI references and nine Mac POI references have zero scored lines;
  the reported mean counts them as zero. Excluding only these unscorable entries
  gives **99.4763% over 101** and **99.7427% over 102** respectively. Keep the raw
  means for historical comparison; do not call those empty-reference rows failures.
- The sweep summaries report matching scored-page counts for 642/645 zh and
  111/111 POI in each mode. The exact audit's **physical PDF page counts** agree
  for 639/645 zh and 111/111 POI. Scored pages and physical pages are different
  measures; neither is blanket pagination perfection.
- The final numeric pair has zero missing outputs, zero score drops and zero
  physical-page changes in both modes. Windows geometry is unchanged. Mac
  `zh-e0ca7252` gains **1061 → 1179/1669**, still 52 pages. Two additional Mac
  documents (`zh-bdae17c0`, `zh-dc9cfa34`) improve Word-matching boundaries without
  changing the score: the scorer's shared-line-start matching hid those differences.
- Some low Mac scores are documented reference defects (`zh-a031fa16`,
  `zh-d9b085b1`, `zh-e8d4c046`). They remain in the raw mean. Reference repair needs
  its own reviewed evidence; do not tune rendering to broken prints.

## 2. What changed since October 27

| Area | Accepted result / present status |
| --- | --- |
| Long-word engine rule | `39bb8cb9328` is now pushed, with confirming full same-engine pairs and no drops. It is no longer an unpushed keep-or-revert decision. |
| Native/browser font widths | `6461fc4819e` preserves requested FreeType size for linear advances. Font/ink probes and actual line-advance dumps resolved the old Mac browser/native mismatch. The Linux pair documented a narrow cancelling-error exception at existing grid ties; the underlying grid residual remains open. |
| Continued rows | `70126e36`: `zh-13552a3a` Windows 810 → 854/854; smaller improvement in `zh-0978dee9`. |
| Embedded-font spaces | `ded14d73`: narrow Mac subset/Latin-face rule takes `zh-c2229d4a` 113 → 265/265. Broad ordinary-space exemptions were rejected, not landed. |
| Mac marks, glyph metrics and fallback | `24aad564`, `76916cff`, `1fd16ce8`, `40a6fc09`, followed by `cd963220`: measured opening-mark fitting, YaHei symbols, mixed-face/tab fallback and later opener-pair spacing. `zh-72da925e` is now 1144/1309 in Mac mode. Removing its Windows-only paragraph-final grid guard was rejected. |
| Sections and drawing | `a279a3b7` fixes odd/even section starts with continued numbering. `bb06181a` uses tight glyph ink for WordArt with native/skwasm support from engine `bd7be6b10e59`. |
| Fixed text boxes | `b3a14a93` shifts/clips only the corrected first line through separate text masks. Broad frame clipping and geometric line bands were rejected after corpus drops and an overlapping second-line glyph regression. `zh-b24b396a` is now Windows 339/362 and Mac 337/360. General frame overflow is still unsolved. |
| Numeric fitting | `d6e61adf`: +118 Mac matched lines in `zh-e0ca7252`; five new Word/native/browser Latin-word controls. Opener regression adds twelve controls; fixed-frame regression has eleven pages. |
| Validation infrastructure | `fc16727c` initializes ICU correctly in native tests; 530-test debug/release agreement was established, with two existing skips. `97e57864` fixes termd's loaded-test reply-order race. `6413b39d` separates HTTP/CDP ports and waits for document/font readiness before exact browser-layout comparison. |

The historical showcase F03 major-unit issue is already fixed by `6384a10a`;
it is not an open gap despite an older board entry saying “LEFT”.

The last point matters: on Linux, an 8-second capture of boringcrypto differed
by 84 dump lines, while a fresh 38-second capture matched native exactly. The
corrected bounded readiness gate passes; it does **not** relax the layout diff or
prove fast loading. The observed OS/2 ascent difference between native-transformed
and browser-staged Word font variants is preserved as a separate observation,
not a demonstrated remaining parity defect.

## 3. Platform status

Engine source baseline is `origin/starling` at `bd7be6b10e59`, including
`39bb8cb9328` and `6461fc4819e`. The complete ten-patch set is: fractional line
heights, FreeType linear size, ideographic-space justification, long-word
next-line, no per-line spacing shift, PDF fake bold, run shift once, scaleX,
shaper scaleX and stencil null-check. Apply it using BUILDING §1.7; a checkout
revision alone does not prove its runtime binaries contain those changes.

| Platform | Build / actual runtime evidence | Layout and regression coverage | Remaining platform gate |
| --- | --- | --- | --- |
| **macOS native** | Accepted `d6e61adf` executable above; Swift 6.2.1; pinned `3841e45e…` bridge. Current engine source includes the full accepted changes through `bd7be6b10e59`. | Fresh 756-document sweeps in each reference mode; Mac native/browser gate and fixed-frame, opener and Latin-fit controls pass. Full 530-test RELEASE suite passed on the earlier frozen mask snapshot, not newly claimed on `d6e61adf`. | Supported-toolchain release package, latest-snapshot unit suite and interactive editing checks before distribution. Swift 6.3.2 was not a substitute: prior release compilation/runtime failures were reproduced with baseline too. |
| **Linux native** | Private release engine `bd7be6b10e59`, all ten patches applied, Swift 6.2.4. `libflutter_engine.so` SHA256 `4485edfc…`; `ldd` resolves the private library. Native GTK/DRM engine targets build. Office snapshot **`cd963220` + harness `6413b39d`** builds. | Full `office-layout.sh` passes welcome/TextEdit/24-page boringcrypto, all save roundtrips, font/ink probe, eleven fixed-frame pages in both native modes/browser and twelve opener controls. No skips. | This is headless/private validation, not a current GTK/DRM interactive package sign-off or a full Linux sweep on `d6e61adf`. The shared checkout still reports **`39bb8cb9328`** and was deliberately not promoted; do not launch a stale shared runtime and attribute the private result to it. |
| **Windows native** | **Receipt 2026-10-28 (Windows box DESKTOP-URK35LH, Claude):** engine fast-forwarded `c34c8aa8eba` → `bd7be6b10e59`, all ten `patches/` applied (2 new, 8 already in), host_release rebuilt incrementally (7 steps). `flutter_engine.dll` SHA256 `5e45502fa77b1a77b51087c9b31f1228c369b3b8771c32e15cec6d36a1bbdd26`, exports `GetGlyphInkBounds` (absent from the backup); `flutter_windows.dll` `79f4d850…`. `skia-freetype-linear-size` (6461fc4819e) is applied but compiles into nothing on Windows: `SkFontHost_FreeType` is not in the Windows build graph (DirectWrite). Previous DLLs kept in `out/host_release/bak-c34c8aa8eba`. OfficeApp release (Swift 6.2.3) built in a private clone at office `d2340b7d` (exe `5f808c25…`) and with `fd127eb8` (`ba416483…`). | Native gate documents match the Mac receipt: welcome 1 page/34 lines, TextEdit 3/88, boringcrypto 24/1071 dump lines, every save round trip 0 differing lines; all 14 native Word-control scripts that `office-layout.sh` runs pass in both modes (fixed frames, openers, Latin/cell-word fit, grid band, empty list, font alternates, kinsoku, minimum baselines, GB2312 names, picture grid, pie labels, row borders, SimHei). Full 756-document sweeps, bundled fonts, PyMuPDF: Windows mode zh **99.0107%** (625 ≥95%) at `d2340b7d`, **99.2084%** (630 ≥95%, 642 page-equal) with `fd127eb8`; POI 89.8721% (98). Mac mode zh 98.3481% (609), POI 91.0126% (100), unchanged by the fix. First cause of the Windows-host gap found and fixed: Foundation on Windows cannot encode `.shiftJIS`, so `windowsMinchoCovers` was nil and Mincho faces lost their JhengHei lines (`fd127eb8`: zh-d97c5474/10e3a42b/202582e2/f6686f89/2a241df1 +18 to +48, nothing down). POI gap vs the Mac-hosted means (−0.64 in both modes) is exactly `rtl` (28.6% here, 100 Mac-hosted): Windows Times New Roman's Arabic reads back as U+06CC/U+06BE and presentation forms in our PDF, and its lines step ~2pt taller than Word's — open. Remaining zh difference vs the Mac-hosted 99.2971% is ~0.09 point (~57 line-percent points), not localised: no per-document Mac-hosted list is on this box. Evidence: `~/starling-doc-check/wn-{win,mac}756{,-cand}.match`, `wn-gate/`. | No browser/skwasm run on Windows (no Chrome/node/wasm build here); no exact Mac dump diff (counts only); no interactive UI pass; no crash-witness rerun. Localise the last ~0.09 zh point against a Mac per-document list; `rtl` Arabic text layer/line height. |
| **iOS native** | Last documented build: September 30 iPad Pro simulator, `build/ios-app.sh OfficeApp`, engine `1848a377952`. Read-only inspection still finds that HEAD in `starling-engine-ios`, with simulator output present. This predates the current engine fixes. | Welcome, ribbon, fonts and typing were observed on that simulator. No fresh DOCX corpus/parity gate, current device build, or physical-device receipt is available. | Rebuild current engine/app for simulator and device; verify PDF/layout, touch selection, keyboard/IME, file picker/save/share and memory on iPhone/iPad. The historical phone desktop-ribbon layout is not a mobile product sign-off. Suggested owner: UIKit/iOS host owner. |
| **Web / skwasm** | Local builds pass. Fresh Linux skwasm SHA256 **`c14456aa8ed4e35af2fa4d952cb7a80f93d169df4641be4d06b482264cc34667`** matches the validated Mac artifact. Mac browser checks cover `d6e61adf`; Linux browser/native checks cover `cd963220` only. | Chrome parity, roundtrips, fractional-font/ink checks and drawing/opener/Latin controls as scoped above. `settle NAME` now fails on document-open/font timeout before taking the exact dump. | Not a Safari/WebKit, mobile browser, all-756-document browser sweep or live deployment receipt. The Linux build had no wasm-opt and is not a performance sign-off. Prepare the optimized release package and run cold/warm/cache/save/PDF gates before publishing. |

The Linux private validation preserved all 17 recorded shared artifact hashes;
minimum recorded free space was 72.5 GiB. Both engine environment variables and
ICU were pinned. The older Linux sweep without explicit ICU is invalid evidence;
it must not be used to claim parity or current fidelity scores.

### Installed fonts: T203 is a user choice, not an all-platform invariant

- **macOS:** CoreText family enumeration; native defaults to installed fonts when
  present, falls back to bundled stand-ins. Current corpus/parity receipts pin
  `OFFICE_FONT_SOURCE=bundled`, so they do not certify arbitrary local-font output.
- **Linux:** `fc-list : family` supplies the installed list. The same preference
  and fallback are implemented; this session validated bundled mode, not a fresh
  interactive installed-font matrix or the user's running desktop package.
- **Windows:** family-table/cloud-font enumeration and follow-ups are implemented.
  The October 25 `1be7bdc8` receipt improved showcase F01 from 17/28 bundled to
  25/28 local matched lines and verified installed faces and launch preferences.
  The on-screen switch was not driven. Subsequent alias/fallback fixes are landed;
  retain those tests in the current Windows rebuild rather than treating the old
  receipt as proof of today's DLL.
- **iOS:** current `OfficeFonts.installedFamilies` has branches for macOS, Linux
  and Windows, **none for iOS**. Its native settings UI/default alone does not
  establish local-font enumeration; T203 equivalence on iOS is a code/validation gap.
- **Web:** `OfficeFonts.fontSource` explicitly returns bundled; there is no local
  machine font list. Deferred families and embedded document fonts must finish
  registration/relayout before comparisons. This differs intentionally from the
  native installed-font default.

Native Options persists the preference; `OFFICE_FONT_SOURCE=bundled|local`
overrides it. The UI says the choice applies to documents opened afterward.
Cross-platform parity claims require the same fonts and reference mode. Different
installed font inventories can legitimately change layout and need separate tests.

### Crash / blocker assessment

No DOCX conversion crash is reported in the accepted 756-document Mac sweeps or
the scoped Linux gate. That is bounded evidence, not a universal stability claim.
Windows stack overflow (`0xC00000FD`) and exit teardown (`0xC0000005`) have documented
fixes; rerun their exact witnesses after rebuilding rather than reopening them as
unfixed bugs. The iOS black-first-frame and duplicate-Skia glyph-ID bugs were fixed
historically, but current engine/device coverage is absent. Mac Japanese IME,
press-and-hold and some editing interactions remain unverified. Whole-repository
terminal/live-PTY checks historically failed independently of DOCX; the Linux
termd test is now fixed, but no fresh all-platform `test/run.sh` pass is claimed.

## 4. Remaining fidelity gaps, ordered by impact

Impact describes affected documents/users, not a promised implementation estimate.
Owners marked “suggested” are recommendations, not newly assigned claims.

| Family / witnesses | Rough impact and present evidence | Owner / next step |
| --- | --- | --- |
| Mac squeeze/Latin edges: `e0ca7252`, `7b08d744`, `c5b5087b` | High for affected long documents: current Mac scores 70.64%, 70.95%, 26.73%. The accepted numeric rule leaves measured 20pt/Latin boundary misses. Broad cap/tolerance changes previously regressed other files. | Current Mac fidelity owner: coordinator order is pie labels, then `7b08`. Coordinate `c5b` with historical T218/lenovo-2 owner; fresh minimal Word controls and both-mode no-drop pairs. |
| Sub-twip grid / width arithmetic: `8d6f702e`, `5be7e156`, `f39e54b6` | Medium, occasionally cascading: `8d6` Windows 90.77%; `f39` 94.52% Windows / 94.59% Mac. Observed `8d` edge is 0.0072pt; other ties expose rounding/cancellation. No justified global epsilon or padding rule. | Suggested layout/engine owner; measure Word's arithmetic and preserve the rejected counterexamples. Do not widen tolerances to improve a score. |
| Pie labels / collisions / wrapping: `27a874b7`, `d62da4dd`, `61aaad09` | High in chart-heavy files. Current Windows 66.30%, 68.69%, 94.12%; Mac 67.39%, 67.68%, 90.79%. Inside-label placement, small-slice collision stacking and some 3-D label widths remain. | **Claimed:** Mac fidelity owner under current T205 follow-up; private Word controls only so far. Full pairs and browser drawing controls before landing. |
| Other chart geometry: `13d11e99`, `b8de3ae2` | Medium: title/plot/axis sizing. `13d` Windows 185/194, Mac 194/194. Opposite title offsets in witnesses reject a universal translation. | Suggested chart owner after T205; isolate font, bodyPr and plot-size effects in Word. |
| Broader drawing/text-box overflow | Medium/high for forms and templates. WordArt and corrected first-line clipping pass; across-line overflow, leading-space balance and unequal-inset rotated clips remain measured residuals. | Suggested drawing owner; retain upright/ruby/scale/tab exclusions and overlap witnesses. Do not revive rejected whole-frame or band-clipping rules. |
| Remaining low-score body/object/review cases | `015abfaf` 62.73% in both modes; Windows `WordWithAttachments` 73.68%; `delins` 74.58% Windows / 75.86% Mac. These need their existing ownership/evidence checked; score alone does not identify one cause. | Coordinator to reconcile historical owners before a fresh claim; isolate first concrete mismatch (objects, balloons/order, layout) with Word controls. |
| Mac residuals / reference integrity | `884c6e3e` 51.38% has a measured near-page-foot/scale boundary; `d5cc99a6` 71.03% remains a triage candidate. Three extremely low documented bad references distort ranking. | Suggested Mac fidelity/reference maintainer; distinguish real layout error from source/reference state before editing or reprinting. Never silently exclude low scores. |
| Automatic hyphenation | User decision still open. 29 Windows-corpus documents enable it; the app preserves the switch but does not hyphenate. Historically worth roughly 1–3 points in some witnesses, not a general corpus cure. | User/coordinator decides scope; then text-layout owner measures English break points against Word, including edit/save behavior. |
| Per-line mixed-face heights | Low aggregate yield, high architectural risk. Earlier scan found roughly 48 Windows / 69 Mac documents with potential mixed-height categories, many already ≥99%; many grid cases are intentionally held tall. **Shelved**, not solved. | Revisit only with a high-impact witness. Requires coordinated engine, pagination, selection/caret and painter work. |
| Math and script tails | Localized but material: multiline display-equation breaking (e.g. `db07d44e`), Arabic joining/ink tails and other non-CJK cases are not covered by the high zh mean. | Suggested math/text-shaping owners; separate text-position scoring from actual glyph drawing and add focused render/edit tests. |

## 5. Product gaps beyond imported-page fidelity

Current source has real typing/selection, undo, formatting, styles, tables,
pictures, headers/footers, navigation, find/replace, rich clipboard code and PDF
export. Do not repeat September's obsolete “merged cells/picture handles/style
editing absent” bullets as current facts. Conversely, a headless painter pass is
not proof these features work interactively on every host.

| Gap | Impact / evidence | Suggested next owner and acceptance step |
| --- | --- | --- |
| Review and reference **authoring** | High for collaborative/professional writing. Current `Ribbon._review` still says track changes, comments, footnotes, TOC, shapes/text boxes and drawing are not in this build. Import/render/preservation support exists for many of them; that does not supply creation/editing, accept/reject or field-management workflows. | Writer product/editor owner: capability audit, correct the overbroad UI wording, choose one complete authoring workflow with undo and DOCX roundtrip tests. |
| Edit → save → reopen fidelity at corpus scale | High data-integrity risk. Current three-fixture layout roundtrips and feature unit tests are green. Historical Word roundtrip receipts (121 clean opens; older 176/179 within 1% render result) are not a fresh full-corpus edited-document guarantee. `keptParts` preservation helps but rewritten content/anchors can still interact with it. | Format/release owner: classify passthrough versus editable content; edit representative complex files, save, reopen in Writer and Word, check repairs, retained relationships, fields/revisions/notes and PDF differences. |
| Interactive behavior across five platforms | High release-coverage gap: focus after ribbon actions, keyboard navigation, selection across pages/tables, clipboard flavors, drag/drop, print/dialogs, accessibility and touch need platform receipts. Old checklist mixes “code”, “pending” and dated on-screen results. | Each host owner plus editor owner: refresh `test/office-checklist.md` on actual release binaries; retain recordings/screenshots and failures. Linux headless success is not a DRM/GTK UI pass. |
| IME and multilingual authoring | High for Chinese/Japanese users. Mac Pinyin verified/default since October 13, plain fields since October 14. Japanese, dead keys/press-and-hold and pending-format behavior have open coverage; other hosts lack equivalent current receipts. | Text-input/host owners: composition, candidate positioning, cancellation, formatting, undo and save tests per host, including physical iOS devices. |
| Proofing parity | Medium/high for writing. `Spelling.swift` implements Cocoa's NSSpellChecker behind AppKit; equivalent active service coverage on Linux/Windows/iOS/web is not established. | Editor/host owners: define supported languages and supply/test a provider per platform or expose the limitation clearly. |
| Mobile layout, keyboard and file workflows | High for an iOS/iPhone claim. Historical iPhone desktop ribbon overflows; earlier keyboard/viewport reports have no fresh closure receipt here. Simulator typing does not certify physical-device selection, keyboard hide/show, local files or sharing. | UIKit and mobile-web owners: responsive/touch product pass, device regression set, large-document memory and save/reopen checks. Keep native iOS separate from Safari. |
| Browser save/recovery and loading | High for trust/usability. Native session recovery has WASI-specific exclusions; do not assume native recovery guarantees apply in a tab. Correctness after fonts settle does not establish acceptable cold-load time. | Web owner: verify supported save/download/reopen behavior, crash/reload recovery, denied file access, deferred-font failure/retry, cold/warm performance and cache upgrades in Chromium and WebKit. |
| Advanced workflows and unsupported formats | Medium/high for some professional users: mail merge, full field/form/content-control editing, macros, collaboration/sharing/versioning are not established by the DOCX renderer or this branch's gates. Encryption code exists, but unsupported schemes remain explicit failures; old “all encrypted files unsupported” claims are stale. | Product coordinator: publish an honest capability matrix and choose scoped milestones. Treat document-management/collaboration work as a separate product/service track. |

## 6. Release readiness and blockers

**Ready as engineering inputs:** the accepted Mac rendering candidate and its
full both-mode corpus evidence; current native/skwasm engine sources and Linux
private build; scoped Mac/Linux native-browser parity; the termd and browser
harness fixes. These can support a release candidate. They are not yet a signed,
packaged, five-platform release or authorization to change a live site.

**Before a desktop release:** choose an exact source/engine/font manifest, rerun
the current release unit suite, package that snapshot, and verify open/edit/save/
reopen/PDF plus platform UI behavior. macOS needs the validated toolchain. Linux
needs the tested private artifacts intentionally packaged rather than accidentally
using its older shared outputs. Windows needs current engine/app builds, crash
witnesses, installed-font and parity checks. iOS needs a modern engine/app build
and physical-device validation before a native mobile release claim.

**Before web redeploy:** follow the prepared
[Office web redeploy checklist](office-web-redeploy-checklist.md). The old browser
layout blocker is resolved under the corrected readiness gate. Remaining gates are
an exact reviewed release merge/package preserving main's loading/cache optimizations,
production compression and manifests, example/open/edit/save/PDF checks, cold/warm
and stale-cache behavior, deferred fonts, and WebKit/mobile coverage. A newer source
than the tested snapshot requires its own relevant gates; Linux `cd963220` evidence
does not automatically validate `d6e61adf`. Publishing still requires the user's
explicit yes. **No live deployment was performed for this report or Linux validation.**

Residual fidelity families need not all be zero before a scoped preview release,
but known data loss, crashes, missing runtime patches, unverified supported platforms
and failing required gates must not be hidden behind a corpus mean. Product scope
and the hyphenation decision remain the coordinator/user's choices.

## 7. Evidence and reproducibility

Repository sources: [board](word-gaps-tasks.md), [prior snapshot](word-fidelity-status-2026-10-27.md),
[layout history](office.md), [editor plan](office-editor.md),
[interactive checklist](../../test/office-checklist.md),
[layout gate](../../test/office-layout.sh),
[font policy](../../apps/OfficeApp/Sources/OfficeApp/OfficeFonts.swift),
[review UI](../../apps/OfficeApp/Sources/OfficeApp/Ribbon.swift),
[DOCX preservation](../../apps/OfficeApp/Sources/OfficeApp/Docx.swift),
[spelling provider](../../apps/OfficeApp/Sources/OfficeApp/Spelling.swift), and
[build instructions](../BUILDING.md).

Mac evidence root: `~/starling-doc-check-starling-word-fidelity-codex/`:

- `mac-opener-paired--mac-number-gap-exact.json`, SHA256
  `462385b1d398a8ade7849c384cf7a112417d22543eda2b924738748f7a1553d8`: all 756 rows/mode; recompute mean
  as `100 * candidate_matched / reference_lines`, zero for a zero-line reference,
  grouping keys by `zh-` prefix. All four means/counts above were recomputed from it.
- `wmac-number-gap/match.txt`, `wpmac-number-gap/match.txt`,
  `nmac-number-gap/match.txt`, `npmac-number-gap/match.txt`;
  `mac-number-gap-{windows,mac}.log` and `mac-number-gap-provenance.json`.
- `grid-punctuation-next/number-gap-browser-layout.log` and
  `number-gap-browser-regression.log`; prior mask/opener exact audits and controls.
- Full native mask suite: `/tmp/starling-mask-full-release/`; its 530-test result
  belongs to that frozen source, not an inferred rerun of today's tip.

Linux evidence root: `/home/starling/office-validation-20261028/`:

- `engine-result.json`, `patches.log`, `platform-build-details.json`, build logs and
  `shared-output-hashes.json` identify private outputs and patch/compiler provenance.
- `office-tip-cd963220/office-result.json`, SHA256
  `47113137e1552575ba1953d2510d90fb0a916e509467f56767f644e7059c5b1c`, and
  `office-layout.log`: final scoped pass. Native executable SHA256
  `3c69b5583e8b3b62074493aed94eb70755082ec9be54f4a94006bc618498af12`;
  WASM `619dc2b8097a577f362fc85d4a4cbe053e3e9fb93348b32783bf93a09c97ff5b`.
- `font-audit/`: all 57 shared base-font hashes match; five minimal package-preserving
  controls; original DOCX at 8s versus 38s. `font-ready-gate/` and
  `readiness-timeout/` preserve the corrected gate and negative timeout controls.
- `failing-bf92ed4b/` preserves the old binary, matching Swift library/resources
  and WASM. Local receipt mirror: `/tmp/starling-linux-validation/receipts/`.

No new corpus conversion, Word automation, shared-engine mutation or production
source change was needed: the accepted same-engine sweeps were fresh and complete.
Windows-current and iOS-current results remain explicitly unverified.
