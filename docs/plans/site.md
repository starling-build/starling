# A site from a repository

**Current priority: the writer's journey (2026-10-22).** Judge the product by
whether an author can bring an existing manuscript, review it, edit it, share
it, and revise it later. The default journey is **Word document or blank →
local draft → reader preview → publish → update at the same link**. Hosting
and Git are supporting setup exposed at publishing time. Additional hosting
infrastructure is not the next product milestone by itself.

**Direction: writing ahead of publication.** The next author workflow is a
manuscript whose saved draft can advance while readers retain an earlier
released version. Build around the questions “What changed?” and “Which
version did readers receive?” Keep saved, uploaded, and verified-live evidence
distinct. A local save must never silently publish an edit.

Sequence the work:

1. Compare saved revisions with the last recorded upload, including corrections,
   removed passages and changes outside paragraph text. This increment is
   described below.
2. Explicit release inclusion and draft retention now cover the next revision
   of an already uploaded chapter and new unpublished chapters, as described
   below. New chapter titles and documents have separate local records; private
   navigation changes for already included chapters remain future work.
   The publisher commits source and generated output together: hiding a page
   from navigation or export alone would not make its source private.
3. A local release overview now covers chapter, website destination, public
   audience, planned date and matching upload snapshot, as described below.
   Scheduled, uploaded, verified live and manually
   recorded releases must remain distinct; dates alone are not a scheduler.
4. Make publishing to the author's own site dependable, then evaluate one
   external destination with active writers and supported publishing access.
   Do not promise automated Royal Road/Ream/Substack distribution based on
   undocumented endpoints.

Validate the product hypothesis with 5–10 active serial writers completing a
release and a later correction. Record time, formatting repairs, missed updates,
remaining chapter buffer and tools they need to retain. Test use alongside an
existing editor before requiring migration. Advanced lore management,
multi-platform automation and payment tiers remain later work, not prerequisites
for this first release-management workflow. These interviews have not happened;
the market discussion is a hypothesis, not demand evidence.

**See writing in reserve (2026-10-22):** Release plan now shows saved document
and word totals for active unpublished chapters, held revisions and chapters
set aside, alongside the included website pages. Each chapter shows separate
saved, included and last-upload word counts when those versions are available.
Holding a revised chapter does not increase the unpublished chapter count;
its full draft word count is not presented as newly written words. Including
a draft moves it into the included totals without claiming an upload occurred.
Removed pages retain their recorded upload count but leave the included totals.

Counts use Writer's existing document word counter, including its East Asian
character rules. Navigation titles are excluded. Empty drafts count as documents
with zero words; no matching upload evidence remains unknown rather than zero.
These are saved review snapshots: save in Writer and refresh the plan to see
later edits. Reading the overview changes no source, release plan or upload
receipt. It does not measure daily writing, editorial readiness or scheduled
release coverage. No new storage format or publishing behavior is introduced.

Validation: native macOS build passes. All 33 focused review, release-plan and
reviewed-publication cases passed across the main run and one retry after a
temporary disk-space failure. Four new cases cover reserve groups and inclusion,
held/saved/included/uploaded versions, removed pages and missing receipts, and
Writer's counting rules. The native walkthrough confirmed the reserve overview
and chapter counts while scrolling: a held revision showed 15 saved words while
its included and uploaded versions both stayed at six. This increment is native
author code under `!os(WASI)`; browser, mobile, Linux/Windows and production
hosting were not exercised.

**Publish the reviewed version (2026-10-21):** Continue to publish now carries
the exact saved publication shown in review into one native publishing attempt.
Review shows the website address and publishing branch. Changes to included
documents, titles, navigation, publication details, source files, local HEAD,
branch, destination or output selection require another review. Private draft
writing and planned dates do not invalidate an unchanged included publication.
After hosting setup or a retry, the native flow returns to review before upload.

The builder captures its configuration and documents once, then produces reading
pages, search, Word and PDF exports from those bytes. It no longer reopens each
document during rendering. Standalone builds and CLI publishing use the same
capture; the CLI captures at invocation rather than requiring an interactive
review. Publication source uses regular files; symbolic links are rejected.

Publishing checks the reviewed input before building, before saving history and
before upload. It compares raw source bytes with the index and committed tree,
checks the prepared publication paths against the saved commit, and verifies
that the commit has the expected parent and no changes outside publication
paths. This catches concurrent saves and Git hooks that replace the prepared
content or add unrelated files. Failed checks do not reset local writing or
rewrite history: a prepared build or local commit may remain, but the remote and
upload receipt are unchanged. If a hook inserted unintended content into local
history, inspect and recover that history before a later upload. Clean filters
that transform source bytes must also be resolved before proceeding.
The capture includes configured pages and other source files Git would upload;
ignored, untracked scratch files are excluded. Already tracked files stay in
the review checks even when a later ignore rule matches them.

Upload pins both the commit and the resolved destination. If origin changes
during the transfer, a successful upload is reported as sent with local setup
needing attention; the old receipt is retained rather than describing the new
origin. A successful upload still needs the separate live-website check.
This is review of included author content, not a sandbox for Git hooks or an
audit of earlier repository history and web-runtime assets.

Validation: native macOS and optimized WebAssembly builds pass. All 26 focused
Swift tests pass, including ten new snapshot/publishing cases. These exercise
stale content/settings/history, immutable build inputs, private drafts, ignored
scratch files, commit-hook changes, preserved receipts and successful re-review.
The full site-build check and all 36 publishing integration tests pass, including
commit-hook source changes and destination changes during upload.
A native scripted walkthrough saved a new title after review, observed the
blocked upload with unchanged output/receipt/remote, refreshed review, and sent
the reviewed revision to an isolated local bare repository. The unpublished
chapter stayed local. No production hosting, mobile/IME or Linux/Windows builds
were exercised.

**Plan chapter releases (2026-10-21):** Publication review now opens Release plan.
The overview combines unpublished chapters, included pages, held next drafts,
chapters set aside and pending removals. It shows the configured website and
public audience. Upload evidence comes from the same validated receipt/artifacts
as publication review: an included page is not assumed uploaded, and a local
commit cannot substitute for the recorded upload. The displayed revision is the
upload snapshot containing that chapter, not its last edit or a live-deployment
claim. Live checking remains a separate action in preview.

Authors can save, change and clear one planned calendar day per chapter. Dated
entries sort first by date. These are local intentions: they do not schedule,
delay or include anything. Publishing continues to upload all included pages,
including pages with future dates. Dates persist through rename, set-aside,
restore, inclusion and upload until explicitly changed/cleared. A removed or
otherwise unavailable chapter retains a visible old date that can be cleared.

A versioned `starling-release-plan.json` record lives in the checkout's Git
metadata. Dates use strict Gregorian YYYY-MM-DD validation without an invented
time/zone. Writes use the shared draft lock, full-snapshot comparison, a rotating
identity and atomic replacement. Stale windows cannot overwrite another date
edit or clear/re-add cycle. Corrupt/unsupported records and redirected storage
are rejected without overwriting; a broken plan does not block publishing.
The publisher never consumes this metadata. Whole-folder backups including Git
metadata remain necessary. There are no automatic reminders, timed releases,
manual external-release records, subscriber access controls or synchronization.

Validation: the native macOS build and 19 focused Swift tests pass (eight new
release-plan cases and eleven publication-review regressions). They cover date
validation, stale edits, corrupt/symlinked storage, chapter transitions, missing
chapters and matching upload evidence. A native scripted walkthrough verified
invalid-date feedback, saving, reopening, changing, cancelling and clearing a
date, then returning to publication review. Manuscripts, configuration, public
output and the upload receipt stayed byte-identical throughout. The full
site-build suite and all 34 publishing integration tests pass. The new test
checks every reachable remote blob for private dates/draft content and verifies
that future dates never delay included pages, past dates never publish drafts,
and a damaged plan never blocks a correction. All remote writes target temporary
local bare repositories. This increment is native author UI/model code under
`!os(WASI)`; the public browser reader is
unchanged. Mobile/IME, Linux/Windows builds and production hosting were not
exercised.

**Set aside and restore unpublished chapters (2026-10-21):** Publication review
now offers Set aside on an unpublished chapter. It disappears from the author's
working contents and search while its complete title and document remain in
local draft storage. Set aside for later lists these chapters with Restore as
draft. Restoration returns an unpublished chapter; inclusion and upload remain
separate choices. Returning from review after setting aside the current chapter
opens the publication home and refreshes any active search instead of leaving a
missing-page preview or stale search hit.

Both operations atomically replace the local record under the shared draft lock
and compare the complete reviewed snapshot. Each transition rotates its storage
identity, so an editor or Word update opened before set-aside/restore cannot
silently overwrite the restored draft. The address stays reserved for both new
drafts and legacy imports. Build and upload checks continue inspecting all local
records, including chapters set aside; release-file conflicts and staged or
committed source cannot be hidden by this action. An interrupted inclusion must
be resolved before setting its chapter aside.

The record upgrades to version 2 when using these actions, with an explicit
set-aside state. Version 1 active records remain readable; a version 2 record
without its state is rejected. Older builds reject the new version instead of
silently treating a chapter as active. No draft bytes are deleted, and no source,
public navigation, output, upload receipt or remote is changed by either action.
Whole-folder backups including Git metadata are still required. This applies
to never-included chapters only: withdrawing included content, discarding held
revisions, permanent deletion, draft-save history and multi-device sync remain
separate work.

Validation: 36 focused Swift cases pass (35 draft/review cases plus the final
missing-state regression). They cover exact content retention, stale snapshots,
stale editors/imports across a set-aside/restore round trip, reserved addresses,
source conflicts and committed content. Native macOS and optimized WebAssembly
builds pass. Native UI scripting verified setting aside the open chapter,
refreshing its search results, falling back to home, restoring the exact saved
chapter, and resuming editing in Writer without changing release files or the
upload receipt. The scripted input driver does not exercise native IME/mobile
input. The full site-build suite and all 33 publishing integration tests pass,
including checks of every reachable remote blob for unpublished content and
preservation of output and receipts when source/history guards block publishing.
Production hosting and Linux/Windows builds were not exercised.

**Write unpublished chapters (2026-10-21):** Native New draft and Add a Word
draft now create local-only chapters, including their titles. A versioned record
under Git metadata supplies an author-only manifest overlay; the public
configuration, source files, build navigation, search and exports exclude them.
The initial publication/home document remains included. Existing source pages
and the legacy CLI import without `--draft` retain their release behavior.

Authors can create, edit and review inclusion before their first upload or
hosting setup. First-time hosting setup follows Continue to publish. Save,
rename, search, preview and Update from Word use the local record. Publication
review separates Not included chapters from Included pages. Include chapter in
next publication checks the reviewed snapshot and adds its exact document and
title to the end of the release contents. It does not build, commit or upload.
The home page stays unchanged. Chapter ordering/home changes become available
after inclusion; local drafts currently sort by address. Shared links and remote
history are unavailable for unpublished chapters.

New chapter addresses avoid release pages, other drafts, reserved web assets,
existing source files and tracked history. Build/upload reject a private chapter
that also appears in release files; upload also checks staged and historical
source paths, including committed then deleted content. Inclusion retains its
record until both source and navigation writes succeed. A partial inclusion
blocks publishing and can be retried through publication review without
silently replacing unrelated content. Writer and import saves retain storage
identity, so a window opened before inclusion cannot silently write into the
release afterward. Draft mutations share the existing process/file lock.

Storage is local to this checkout under `.git/starling-unpublished/`, with the
same whole-folder backup requirement as held revisions. This is not encrypted
storage, multi-device sync or a history of draft saves. The later set-aside
workflow above retains and restores unpublished chapters. Undoing inclusion,
private reordering, permanent deletion and scheduling remain open. No claim is made to
hide text an author has copied into other tracked files or already uploaded.

Validation: 47 distinct focused Swift tests pass across the main 45-case run
and added shared-link and merged-history regressions. The seven unpublished
chapter cases were rerun after moving author-manifest loading off the UI thread;
that change fixes a native startup crash found during the walkthrough. Native
macOS and optimized WebAssembly builds pass. The full site-build suite passes,
including 31 publishing integration cases; the two new release/recovery cases
passed again after the final history check. Integration tests inspect every
reachable remote blob for both unpublished text and title. A merged side branch
that added then removed chapter source also blocks uploading.

Native scripted UI checks cover New draft, writing/saving, local preview,
review before hosting setup, explicit inclusion, and retrying an interrupted
inclusion. The release output and upload receipt stay unchanged during these
local actions. The headless Chrome home-passage test passes with the rebuilt
reader, including stable passage links after changing the home page and
rejecting ambiguous paragraph identities. Remote writes in tests use local bare
repositories. No production hosting, mobile input or Linux/Windows builds were
exercised; this does not replace validation with active authors.

**Keep a chapter's next draft local (2026-10-20):** An unchanged uploaded page
now offers Start next draft in publication review. Its working revision is
stored atomically in a versioned record under this checkout's Git metadata,
outside the tracked source and generated output. Reader preview, Writer saves,
local search and Update from Word use that working revision; builds use the
unchanged released source. The author preview and review explicitly identify
held drafts. Compare saved changes compares their working text with the last
upload. Include draft in next publication copies the reviewed working revision
into the release source without building or uploading. A stale review cannot
include a newer draft.

The first implementation requires an unchanged source page, a matching upload
receipt and HEAD equal to that uploaded revision when starting a draft. It
does not move existing unpublished edits out of history or claim to make
previously committed text private. Source equality is checked at build time;
upload checks also reject a changed destination or intervening commits that
altered a held chapter, including a change later reverted. A malformed,
missing-source or unsupported draft record prevents build/upload rather than
silently releasing newer content. A failed inclusion leaves the draft record
intact and the same inclusion can be retried after the source write.

Local draft transitions are serialized; macOS/Linux use a file lock between
processes as well. Writer saves and prepared Word updates retain a storage
identity, so an editor left open across another window's release choice cannot
silently save into release files. Such edits remain open with recovery guidance.
Copying a published page/passage link from a held-draft preview is rejected;
Open website still opens the previously checked website. Deletion of a held
page is blocked until its draft is explicitly included.

This holds document content only. Page titles, navigation and publication
details still belong to the release. The later unpublished-chapter workflow
above changes the default for new pages; existing release pages stay included.
Draft records are local to this checkout, not cloned, synchronized, encrypted
or archived after every save. Backups must include the whole publication
folder and its Git metadata. Never present this as a private multi-device
workspace or a complete serial scheduling system. Private author navigation,
draft history and discard/recovery UI remain next.

Validation: the native macOS build and 38 focused Swift tests pass. The full
site-build suite passes, including 29 publication integration tests. After the
final storage-identity and locking changes, the two affected integration cases
passed again: publishing another chapter while retaining a draft, explicit
inclusion and release, and refusing an externally changed release source.
The tests inspect every reachable remote blob for unpublished draft text and
verify that a competing process cannot include a locked draft. All remote writes
target temporary local bare repositories.

A native UI walkthrough started a draft, edited and saved it in Writer,
compared it with the upload, and included it for the next publication. Source,
generated output and upload receipt were checked at each transition; inclusion
changed only the source and removed the draft record. This did not exercise
mobile input, production hosting or Linux/Windows builds. The new implementation
is native-only; the public WebAssembly reader was unchanged and was not rebuilt
for this change.

**Compare saved changes (2026-10-20):** Updated and added pages in publication
review now open a read-only comparison of the saved draft and the exact page
artifact in the last matching upload. Removed pages retain Review removed text
even after their working source and local build output are deleted. A later
local commit or rebuild cannot replace the upload baseline. Without a usable
matching record, comparison is unavailable rather than inventing an unpublished
state.

The comparison shows complete before/after paragraph text, additions, removals,
paragraph-detail changes, relative paragraph reordering, page layout and
document-level changes. Matching uses unique persistent identities, with unique
exact text as a fallback after imports. It does not guess relationships between
unidentified edited passages. Paragraph details include links, formatting,
bookmarks and embedded content; this is not a visual layout or character-level
diff. Ten changes are displayed at a time. Show in saved draft selects a uniquely
identified current passage and carries that selection through Edit document.
Comparison retains the review snapshot; refresh review after external changes.
It does not restore files, upload, or claim the uploaded version is live.

Validation: 33 focused comparison/review/shared-link/live-marker tests pass,
including a 10,000-paragraph manuscript, duplicate/missing identities, empty
legacy documents, formatting-only changes, deleted source/output and unsent
local commits/rebuilds. Native walkthroughs verify before/after text, selecting
the changed passage in preview and Writer, pagination and returning to review;
saved source, configuration, uploaded files and the receipt stay unchanged.
The native build passes. These changes are native author UI/model code behind
`!os(WASI)`; the public reader is unchanged. No production host was contacted.
This is scripted desktop validation, not external author or mobile testing.

The current pass starts a publication directly from a Word document, keeps
the original untouched, puts document editing and reading previews first,
and moves hosting into Publish. This is an initial usability correction,
not proof that onboarding is finished: Git installation/identity/authentication
and external hosting setup still create friction. A successful publication
needs a verified live link; the app now checks the public build marker before
offering the website link, as described below.

Next acceptance exercise: give a writer a real manuscript and a revision.
Observe opening, editing/saving, returning to the preview, reopening the
publication later, first publishing and updating. Record points where help is
needed and whether the author understands local versus published state.
Prioritize those failures before more configuration features. Pending author
needs include simpler first-publish setup and real-author validation of the share-link workflow. Do not label an entire local
publication a private/unpublished draft if it may already have a live version.

Validation of this initial pass: seven creation tests and three focused
publishing workflow tests pass, including manuscript import, revision and
rebuild. The native UI walkthrough selected a real Word file, created its
publication, edited and saved in Writer, and returned to a preview containing
the edit; the original Word bytes stayed unchanged. The walkthrough exposed
and fixed a debug-build stack overflow in background Word decoding. It used
the app's scripted input with native IME disabled, so it does not validate
IME or phone input. Native tests/build and the optimized WebAssembly build
pass (the final worker-stack fix is native-only). No live publication or
deployment verification was performed.

**Edit the reviewed passage (2026-10-20):** Edit document now carries the
preview's selection into hosted Writer and reveals it after layout. This
completes the reference-correction path: Review → Show in document → Edit
document → correct the link → Save → Back to preview → Review. A newer caret
move or edit takes precedence over the initial reveal. Hosted documents with
no requested selection keep their existing behavior.

Validation: a native walkthrough selected a flagged reference, opened Writer,
changed its destination through the Link field, saved and reopened publication
review. The notice count dropped from three to two. Assertions checked that all
paragraph text and identities, other link targets, configuration and upload
receipt were unchanged. Merely opening the selected passage did not dirty the
document. Native and optimized Wasm builds pass. This walkthrough used the
in-app fallback key driver, not native IME composition or a phone.

**Author reference review (2026-10-20):** Review your publication now identifies
references that cannot be followed in the text view: missing or ambiguous
bookmark targets, references to other source files, unsupported address types
and formatting damage that prevents a link from being preserved. Each affected
page has Show references with a paragraph excerpt, target and repair guidance.
Show in document opens the identified passage in the author preview when it
has a unique saved identity. Otherwise the page preview remains available.
These notices do not block publishing.

The inspection uses saved source bytes and does not edit, upload or fetch any
document. Refreshing review after a correction removes resolved notices.
Repeated formatting runs for one target in a paragraph produce one notice.
Diagnostic targets are local author-review data, not extra fields in the
public text payload. This does not change which source files Git publishing
uploads. It is not a live URL availability check.

This work also rejects ambiguous passage identity consistently: generated
HTML, bookmark links, the reader's passage navigation and new copied links
must not silently choose the first of several matching paragraphs. A normal
page link remains available when a passage cannot be identified uniquely.

Validation: 25 reader-text/review/published-link unit tests pass. They cover
issue classification, grouping, unchanged source/receipt state, corrected
references, unique passage targets and ambiguous bookmark/paragraph identity.
A native walkthrough expanded the issue list and selected the intended passage
through Show in document without modifying the source, configuration or receipt.
Chrome checks the normal text reader, bookmark navigation, a saved passage after
home changes and refusal to select an ambiguous passage. Native and optimized
Wasm builds pass. No configured hosting service was contacted.

**References in text view (2026-10-20):** Generated text and the live reader's
text layer now share a structured document representation. HTTP(S) and email
references remain real links. Known document bookmarks resolve to the
document's paragraph IDs; their links include the page's own route so a
chapter reference does not resolve against the publication root. Paragraph
IDs also supply HTML anchors for shared passage links. Unknown bookmarks
and unmapped relative file references retain readable text.

Text and link attributes are escaped in generated HTML. The live host creates
DOM nodes from versioned JSON using text nodes, never document-authored HTML.
Executable/file URL schemes are not made clickable. Duplicate or absent
paragraph IDs do not create conflicting anchors. Invalid formatting runs fall
back to the paragraph's complete text, including surrogate pairs, instead of
losing content. This still does not reconstruct list/table/image semantics;
those and real screen-reader testing remain pending.

Validation: 19 focused reader-text/address/details unit tests pass, including
Unicode boundaries, malformed runs, escaped text, link schemes, bookmark
mapping and duplicate IDs. Native and optimized Wasm builds pass (20.72 MB
Wasm, 6.31 MB Brotli). The site-build suite and all 27 publishing regressions
pass. Chrome verifies references and anchors with five runtime/script failure
cases, the healthy reader, keyboard focus and bookmark activation on a nested
chapter while retaining text view. The copied-home-passage regression also
passes. Screenshot inspection confirms the text view. The final preference
adjustment changes native-generated host markup only.

**Public page addresses (2026-10-20):** Published shell pages now carry a
canonical address and matching `og:url` when a website address is configured.
The root home page and its slug alias identify the same canonical page.
Sitemaps and robots.txt use the same address construction: the saved website
origin plus the build's route, including an explicit `--base` override. A
project path is never appended twice. Changing home updates root/alias
metadata together; clearing the website address removes prior metadata and
sitemap artifacts on rebuild.

Local publications do not invent a public address. Credentials, queries,
fragments and unsupported URL schemes are rejected for metadata generation.
The generated missing-page shell has `noindex` and never claims the home page
as its canonical address. Date and preview-image metadata remain pending;
the build timestamp is not treated as an author's publication date.

Validation: 13 address/details unit tests pass. `test/site-build.sh` passes
its build/import/move/local-push checks and all 27 publishing integration
tests. Coverage includes root/project/custom-origin URLs, Unicode routes,
explicit base overrides, home changes, removal of obsolete metadata and
omission of credential-bearing addresses. Native build passes; this change
does not alter Wasm application code or contact the configured website.

**Readable publication fallback (2026-10-20):** Generated publication pages
show their text immediately, before the interactive reader loads. Navigation,
publication details and PDF/Word links work with scripts disabled and with
failed app, renderer or font requests. Empty documents retain their navigation
and downloads; the generated missing-page screen offers publication links.

Readers can choose Keep reading text while loading, or Read text after the
reader opens. Following links in text view carries that preference. Interacting
with or scrolling the text while loading prevents an automatic switch away
from it. Known startup/runtime failures return to text without replacing the
publication title with an error title or exposing a stack trace in the page.
The generic app host still reports errors to the developer console.

This uses generated HTML and a small host adapter, with the application still
implemented in Swift/Wasm. Paragraph/reference support is described above;
list/table/image semantics and full assistive technology testing remain
pending. It does not claim visual equivalence with
the document layout. Downloads provide the original page-oriented output.

Validation: all 25 publishing integration tests and seven publication-details
unit tests pass. `test/site-fallback-web.py` drives isolated Chrome instances
with failed host module, application, renderer and font requests, and scripts
disabled. It follows page links and fetches valid PDF/Word files, tests empty
and missing-page output, switches a healthy reader between views, simulates a
runtime error and checks keyboard focus on visible links. The existing copied
home-passage regression still passes. Native builds pass; the browser uses the
previously validated optimized Wasm application with the updated host. These
changes affect native HTML generation and host glue, not Wasm Swift code.
Manual screenshot inspection covers the text view; Safari/Firefox and real
assistive technology testing remain pending.

**Publication details (2026-10-20):** Authors can add an optional byline/publisher,
short description, edition label, language code and rights statement through
Publication details in the preview. Saving patches the local configuration,
preserves unrelated keys and rejects a form whose configuration changed
elsewhere. It neither edits document bytes nor uploads, signs in, or copies a
Git identity into the public byline. Empty fields remove the corresponding
values. Details have their own versioned schema; legacy publications with no
details remain readable and unsupported versions fail before build output is
replaced.

Byline and edition appear in the reader header. About publication shows all
provided details. Generated HTML carries escaped author, edition and rights
metadata and an accessible/fallback description of the publication. A supplied
language code updates the shell's language; a short description overrides the
home page's link-preview description while other pages keep their own summaries.
The generated manifest carries the same information for the Swift/Wasm reader.
Changing details appears in publication review and prevents a new page-share
link from claiming those unsent details are already published.

An edition label is descriptive text, not an archived release or immutable
citation. This implements publication metadata only: page-level draft exclusion,
archived editions, and changing document contents/styles from these fields
remain outside this increment.

Validation: 21 details/review/published-link unit tests and all 25 publishing
integration tests pass. They cover old schemas, clearing fields, validation,
stale writes, unknown-key preservation, escaped HTML, failed builds, and
publication details reaching the manifest and shell without modifying source
documents. A native walkthrough saved all fields and displayed the byline and
edition; fixed-height inputs prevent movement as empty fields become filled.
Headless Chrome opened the generated Swift/Wasm reader and About view and
checked language, author metadata and fallback detail text. Native and optimized
WebAssembly builds pass; the final input-height adjustment is native-only.
All hosting used local fixtures; no production publication was made.

**Share a published page or passage (2026-10-20):** After Check live website
confirms the uploaded marker, the native author preview offers Copy page link.
Link to paragraph now copies a full published URL too, rather than displaying
a local relative route. Before a successful check it directs the author to
Check live website. Both links use the stable slug alias under the website's
project path. The native read-only reader also copies a full passage URL without
duplicating a project path.

Before copying from a local publication, the app rechecks the recorded upload
and website address, finds the page in that upload's manifest and compares its
saved bytes, page title and publication title. Unsent pages/edits and missing
paragraph IDs require publishing and checking the website first. Other pages
may have pending edits without preventing a link to an unchanged uploaded page.
These links describe the previously checked published version, not a new
deployment check on every click. A later change at the host remains possible.

Validation: six new page-link tests and the six live-marker tests pass, covering
project-path URLs, stable passage links, unsent content/title changes, new and
removed pages, missing paragraphs, stale verification, and escaping sources.
A native walkthrough verified the instruction to check live before copying.
Native build passes. This increment is native-only; the preceding optimized
web build and browser passage-link regression remain applicable. Successful
native copying against a production host has not been exercised.

**Stable home and passage links (2026-10-20):** Home-page choice is independent
of contents order. New publications store `home`; older configurations infer
their original first page on read and pin that choice on the next configuration
save. Merely opening a publication does not rewrite it. Reordering and renaming
through the app preserve its home. A manual reorder of a legacy JSON file
before this migration still follows the old first-page rule.

Page options offers Make home page with an explanation of how the main website
address changes after publication. Any included page, including a nested one,
can be home without moving it in the contents. Deleting home requires selecting
another home first. Invalid explicit home values fail build/review before
replacing output. An obsolete home-change prompt is rejected if another edit
changed the home meanwhile; navigating to another page clears pending rename,
delete and home prompts.

New paragraph links always use the page's existing `/<slug>/#p=…` route, including
home, rather than its root alias. They survive subsequent home selection and
ordering changes as long as the page slug and paragraph ID remain. Existing
root links still follow home; there is no retrospective redirect or promise
that removed/unmatched paragraphs survive a Word reimport. The builder continues
to emit the slug route for every page as well as the root home route.

Validation: home/review/hosting/recent-publication unit tests pass, including
seven focused home tests. All 23 publishing integration tests pass, including
reordering a legacy publication, rendering a new explicit home, retaining slug
aliases and refusing a missing home without replacing previous output. A native
walkthrough selected a new home and reordered it without uploading. The
headless Chrome regression `test/site-home-web.py` copied a home-page paragraph
link, rebuilt with a different home and reopened the saved link at the same
paragraph. Native and optimized WebAssembly builds pass.

**Review before publishing (2026-10-19):** Publish now opens a review of the
whole publication before the change-description/upload form. First-time hosting
setup now follows review (updated by the unpublished-chapter workflow above).
The review lists every included website
page, its route and home-page status, with a Preview page action. It explains
that all these pages and their Word/PDF editions are included, and that a public
hosting repository also exposes committed source files and history. This is a
website-page inventory, not an audit of all files in Git history.

Where a matching upload receipt and complete old public files exist, the review
labels added, updated and unchanged pages and lists removed pages separately.
It compares saved source with the generated pages in the recorded upload,
not a later local commit or failed build. Title/content/route changes count as
page updates; publication settings and navigation changes have a separate
notice. Changed routes show the previous address. Missing or incompatible
history yields “Included,” never a claim that every page is new or unpublished.
The comparison says what was last sent from this checkout, not what is live.

Continue to publish returns to the publishing form without uploading. Preview
page returns to that page for inspection/editing. Review can be refreshed or
reopened from the form. It describes saved files at review time; publication
still rebuilds current saved files, so external edits are not frozen by this
screen. Review and build share source-page validation and reject missing,
invalid, duplicate, reserved or escaping page paths. This does not implement
draft exclusion, a full content diff, redirects or automatic withdrawal of
previous downloads/caches/history.

Validation: seven review tests and all 21 publishing integration tests pass.
Coverage includes initial/unknown history, nested pages, changed source despite
a later local commit, addition/removal, title edits, home/base URL changes,
changed destinations, incomplete/corrupt old builds and invalid source paths.
A macOS scripted walkthrough inspected a three-page review with one addition,
one update and one removal, continued without uploading, opened a different
page from the review, and retained the change description when reopening it.
Source/output files, the Git index and the upload receipt stayed unchanged.
This used isolated local fixtures and fallback input; it did not exercise a
real host or phone input.
An additional walkthrough added a page externally while the review was open:
Refresh showed four pages, and Continue reloaded the sidebar and upload form
to the same count. Native and optimized WebAssembly builds pass; the final
return-path refresh is native-only and was rebuilt and exercised natively.

**Publishing progress and recovery (2026-10-19):** The author preview shows
setup, website generation, saving history, uploading, and recording the upload
as separate progress messages. Failure advice stays next to the publishing
controls, with the change description retained for retry. Missing setup links
back to its form; access failures link to sign-in help. Remote changes require
manual review/merge, hosting restrictions require reviewing repository rules,
and connection/unknown failures say the upload is unconfirmed. No automatic
merge or force push is introduced. Retry rebuilds current saved files.

Recovery uses structured issues shared by the UI and CLI. Raw Git push, staging
and commit output is not echoed into author-facing messages. Known push output
is classified conservatively, with a generic unconfirmed fallback. A successful
push followed by a local bookkeeping failure remains explicitly “sent.” Failed
pushes retain the previous successful receipt and the local commit. The push
uses C locale and disables Git's terminal credential prompt with closed stdin;
external credential helpers/SSH can still use their configured interaction.
During uploading, **Stop upload** stops the local Git process and its transport
and helper children. Uploads also stop after five minutes. Both outcomes report
the remote result as unconfirmed: the server may already have received data.
Saved writing, local history and the previous successful receipt remain intact,
and the change description remains available for retry. Website generation and
saving local history are not cancellable.

The native upload runner owns a separate process group, sends termination,
then kills the group after a short grace period. Output capture is bounded and
nonblocking, so noisy output or an inherited pipe cannot prevent the deadline
from being checked. A completed Git exit observed before cancellation wins the
race and follows the usual success/failure path. The UI stays responsive while
the worker stops the upload.

The native walkthrough exposed a pre-existing stack overflow while generating
a site on a default Dispatch worker. Publishing now runs on a named thread
with an 8 MiB stack, as manuscript import already does. UI progress and completion
remain dispatched to the main thread. The change-description input is disabled
during publishing, so a completed attempt cannot clear text typed mid-upload.

Validation: five recovery-message tests and all 21 publishing integration tests
pass. The integration suite checks a real non-fast-forward rejection against a
local bare repository, preserving both histories and the previous receipt, and
ensures server-provided credentials are absent from rejection messages. A native
scripted walkthrough reproduced the worker-stack crash, then verified the fix:
rejection, retained change description, retry, and a receipt matching the sent
revision. The walkthrough used isolated app/Git state and a test Git wrapper
that redirected only the push transport to a local bare repository. No external
repository, GitHub credentials, or production website was used. Native and
optimized WebAssembly builds pass; the shared header was split into smaller
layout expressions to satisfy the optimized web compiler.

Upload-stop validation: eight additional native tests cover pre-launch
cancellation, descendants that ignore termination, closed output, continuous
output, inherited pipes, exit status, launch failure and conservative recovery
messages. A macOS scripted walkthrough stopped an upload blocked in a local
receive hook, confirmed the previous receipt was unchanged, then retried
successfully and matched the new receipt to the bare repository's revision.
The change description stayed visible throughout. This used the same isolated
local transport wrapper; real hosting, Linux process handling and phone input
were not exercised.

**First-publish setup (2026-10-19):** Publish opens the setup guide automatically
when repository or website details are missing. The guide follows three author
steps: choose a home, set the publishing name, then publish and enable the site.
It opens GitHub's repository creation and Pages settings in the browser; leaving
the website address blank derives the usual GitHub Pages address. Save and
connect combines the two local operations while preserving existing remotes.
Continue to publish requires saved form values and passing local checks.

Author name and email can now be saved from the app for this publication only.
Git's config lock protects the update, both fields are installed together, and
unrelated configuration is preserved. Changed author values, existing locks,
linked config files, and overriding included settings are handled without
silently overwriting someone else's author settings. Connecting a repository
while the form is open does not make the author form stale. Global settings are
never written. The app explains commit attribution and links to GitHub's
no-reply email settings; this does not authenticate the user's account.

The Pages instructions use the actual publication target branch. Custom output
folders require a deployment workflow, rather than instructions to select a
folder GitHub's branch deployment does not support. Creating the remote,
GitHub authentication, and enabling Pages remain external steps. End-to-end
first-publish validation with a real author and host remains outstanding.

Validation: all 16 hosting/identity tests pass. A native scripted walkthrough
opened setup from Publish, entered repository and author details, saved the
connection with a derived website URL, saved the author, and reached the ready
state. Reopening preserved the author; Continue to publish returned to the
preview without committing or uploading. Three focused publishing regression
tests also pass. The walkthrough used a temporary publication, isolated Git/app settings, and fallback
keyboard input; no GitHub request or upload was made. Native and optimized
WebAssembly builds pass.

**Check and share the website (2026-10-19):** After publishing, the author can
choose **Check live website** in the preview. A matching public build marker
reveals **Open website** and **Copy website link**, with the time of the check.
The marker is generated inside the staged build and installed with its files;
the expected marker is read from the exact successfully sent commit, never
from a newer local build. Pending saved changes remain pending even when the
last uploaded version is confirmed online.

The request uses the configured HTTPS website base, bypasses local caches,
adds a cache-busting query, and has a bounded timeout. Missing/old/malformed
markers, HTTP errors, network failures and responses from a different address
remain unconfirmed. Recheck after changing a website address or destination;
old publications without a marker need one new publish. Navigation, settings,
and publishing invalidate the displayed check. An in-flight response is
ignored if the receipt or destination changes. Open/copy revalidate the local
receipt and address. Verification is a point-in-time marker match, not proof
that every asset or page renders correctly, and is not persisted across sessions.

Six focused tests cover matching/stale/error HTTP responses with an intercepted
session, plus immutable sent-revision lookup and changed publication settings.
Publishing integration coverage also checks that a failed retry cannot replace
the marker associated with the last successful upload. No production website
is contacted by these tests. All six focused tests and all 19 publishing
integration tests pass. A native scripted walkthrough confirmed the new
button and the first-publish instruction for a publication without a receipt.
The walkthrough used isolated app state and did not test a live deployment.
Native and optimized WebAssembly builds pass.

**Returning to work (2026-10-19):** Home now has Continue publishing,
with the last visited page restored on reopening a local publication.
Close publication returns to Home. History is local application state,
outside the publication repository, and respects the isolated recovery
folder used by test drivers. Missing folders remain visible as unavailable;
removed pages fall back to the first page. This does not track scroll
position or unsaved edits.

Five focused persistence tests pass: last-page restore, canonical-path
identity and ordering, renamed/deleted pages, unavailable folders, and a
bounded/corrupt history file. A native scripted walkthrough confirmed Home
→ recent publication → last page → Close publication → Home across app
restarts, plus the unsaved-document prompt and unavailable-folder state.
The walkthrough used an isolated recovery directory and fallback key input;
it did not modify the user's history or publication content. The native
build and optimized WebAssembly build pass.

**Saved publication status (2026-10-19):** The author preview now shows
unknown local publishing history, saved changes needing publication, or saved
files matching a successful upload. A private receipt in the checkout's Git
metadata records the exact sent revision, destination, target branch and
output folder. Only a successful push writes it. Push pins that revision;
first-publish branch tracking is still configured automatically. The receipt
is not included in the published files and is not inherited by a fresh clone.

Comparison includes site.json, pages/ and the generated output, including
new/ignored files and deletions, but excludes unrelated notes. A local commit
cannot turn pending edits into sent content. A changed destination, missing
commit, corrupt receipt or unavailable Git history gives an unknown state.
The status checks no remote state and never claims deployment is live.
Returning from editing, page navigation, settings and publish completion
refresh the status; Publish → Check publication status covers external edits.
No filesystem watcher is implemented. Live version checks are separate from
this local saved-file status.

All 18 publishing integration tests pass, using local bare Git remotes. They
cover pending changes after a local commit, rejection/retry, ignored new
pages and deletions, unrelated staged notes, changed destinations and target
branches, corrupt receipts, fresh clones, first-publish tracking, and a local
commit made by a pre-push hook while uploading the pinned revision.
The configured nondefault target branch also passes an explicit publish and
status check. A native scripted walkthrough started from a successfully sent
publication, edited and saved a paragraph in Writer, and returned to the
preview showing pending changes. The successful-upload receipt stayed
unchanged. This used a temporary local remote and isolated app history;
no external hosting or live deployment was tested. Native and optimized
WebAssembly builds pass.

The live-marker check above completes the next status step. First-publish
setup remains too technical for an author and needs further simplification;
validation against a real hosting deployment remains outstanding.

**Starting to write (2026-10-19):** Start blank → Start writing now opens
Writer directly with an empty document and focus ready for text. The
publication title stays in the publication metadata; it is not inserted into
the document body. Word imports continue to open in the reader preview.
New page also opens its new blank document directly for editing. This is a
one-time transition, so returning to the preview does not reopen the editor.
Publication editing now labels its return action Back to preview, with the
existing unsaved-changes protection. Saving remains local; publishing is a
separate action. Other hosted documents retain their existing return labels.

The walkthrough exposed a hosted-document save bug: the unsaved-changes
prompt offered Save As because the document had no ordinary file path.
Hosted documents now save through their owner and only run the pending
navigation after a successful save of the current edits. A failed save returns
to the editor with the unsaved text intact and a short message asking the author to check the publication folder. Discarding hosted edits also leaves the unrelated untitled-file
recovery copy alone; hosted documents do not create that copy.

Validation: seven creation tests and the two blank/manuscript build checks
pass. Native scripted walkthroughs covered immediate typing after Start
writing, saving and returning to preview, adding a chapter, saving through
the return prompt, and discarding edits. Making the test publication folder
unwritable confirmed that a failed save keeps the text in the editor and
does not change the saved file. Discarding hosted edits left an unrelated
recovery-file sentinel untouched. These checks used isolated app history and
fallback keyboard input, not native IME or phone input. Temporary test data
was moved out of Documents after the checks. Native and optimized WebAssembly
builds pass.

Status: **MVP built 2026-10-18, made a document reader 2026-10-19** — see "Where it stands". A content
site whose pages are Writer documents in a git repository, published as a
static folder that GitHub Pages serves. No server, no sign-in: editing is
local, in the native app on a clone, and Publish is a commit and a push.

**Product priority: document publishing.** Help authors and organizations
publish their Word-based documents for readers on the web, preserving the
document's layout while adding navigation, search and shareable references.
Git and static hosting are the delivery mechanism. The publishing product,
its first customers, and the remaining work are set out in
[Publishing product plan and review](#publishing-product-plan-and-review).

The user's framing (2026-10-18): "the real MVP would be to use GitHub as
repo to host all the content for a site, no backend needed", and then
"assume the GitHub repo is cloned locally, you run a local app or server
to modify local files, once done, commit push to remote repo". The
earlier idea of signing in with GitHub and committing from the browser is
parked (it needs a token-exchange function, Decap-style; see the wiki plan's
discussion); the wiki server (`docs/plans/wiki.md`) stays as the
enterprise tier and is untouched by this.

## What a site is

```
site.json          { "title": "…", "base": "/", "pages": [ {slug, title, children?}… ] }
pages/<slug>.json  each page as the document model (RichDocumentEnvelope)
docs/              the build — what GitHub Pages serves (main branch, /docs)
```

The `home` slug in `site.json` selects the home page; legacy files fall back to
their first page until saved. Routes are `/<slug>/`
under the base; the home page is the base itself. Slugs are flat (a
child's route does not include its parent's).

`examples/site/` is a four-page site to start from.

## The pieces

- **`OfficeApp --site-build <repo> [--out <dir>] [--web <stage>] [--base /p/]`**
  (`apps/OfficeApp/Sources/OfficeApp/Site/SiteModel.swift`, `SiteBuilder`):
  copies the web build in, copies the pages, writes `manifest.json` (title,
  base, home, tree) and `search.json` (slug, title, text per page), and
  writes one shell page per route — the app's index.html with
  `<base href>`, the og/description meta tags from the page's title and
  first paragraphs, `args: ['--site', '<base>']`, and the page's text in
  `<noscript>` (text for crawlers and script-less readers, not layout).
  `index.html` is the home page's shell, `404.html` the app for unknown
  routes, `.nojekyll` keeps Pages from running Jekyll. It refuses to write
  into a folder that has files and no manifest.
- **The reader** (`Site/SiteShell.swift`, `SiteRoot`): the wiki's look — the
  tree, search over `search.json` with snippets, the page drawn by the
  Writer in read mode, the address bar following the page in a tab. Over a
  writable store it adds New page, Edit (the whole Writer on the page,
  `HostedDocument`, Save writes the file) and Publish (a commit message,
  then build into `docs/`, `git add -A`, `git commit`, `git push`).
  `OfficeApp --site-publish <repo> [-m msg] [--out] [--web]` runs the same
  from a terminal or a script.
- **Stores** (`Site/SiteStore.swift`): `StaticSiteStore` fetches the built
  files by URL (a tab on Pages; natively `--site https://…`);
  `LocalSiteStore` is the clone on disk (native `--site <dir>`), with the
  web build from `--web`, `STARLING_WEB_STAGE`, or `.stage-web-OfficeApp`
  in the working directory.
- **Gates**: `test/site-build.sh` (the build's output, a rebuild, the
  refusal, a `/demo/` base, an edit followed by a rebuild, and a publish
  to a local bare remote) and
  `test/site-web.sh` (the built site served as Pages would, headless
  Chrome opening a page by URL, reading its text, moving by the tree with
  the address bar following, a search hit, and the same under `/demo/`).

## Publishing to GitHub Pages

1. Create a repository from `examples/site`, commit, push.
2. Clone it; `OfficeApp --site <clone>`; edit; Publish.
3. In the repository's settings, Pages → deploy from branch `main`, folder
   `/docs`. For a project site (`https://<user>.github.io/<repo>/`) set
   `"base": "/<repo>/"` in `site.json` first.

The build is ~60 MB on disk (the app, fonts, skwasm); Pages serves it
gzipped: app.wasm is 7.8 MB over the wire, skwasm.wasm 1.6 MB.

**The demo: https://starling-build.github.io/site-demo/** (repository
starling-build/site-demo, made 2026-10-18 from examples/site with
`"base": "/site-demo/"`, published with `--site-publish`, Pages set to
main `/docs` through the API; the first deploy took 32 s and the site
answered 45 s after the push). Measured from a cold headless Chrome on the
dev Mac: app.wasm downloads in 1.3 s, the app is running before 3 s, the
tab is titled "Publishing — Starling Site demo", the page's text is
drawn, and a tree click moves to /site-demo/about/.

## The reader as a document reader (2026-10-19)

The focus the user chose: not web pages but published documents — what
HTML cannot do is the page. So a page that came from a paged file keeps
its page setup in the stored form (`RichDocumentEnvelope.pageSetup`,
written by `--page-json`, by Writer's Save over a hosted document, and
read back by `--page-docx`), and the reader shows it as **pages** on a
desktop (headers, footers, page numbers, "Page 8 of 24", a page wider
than its room drawn smaller, whole) and as **flow** on a phone, with a
Pages/Flow switch. **Contents** lists the headings with the page each
starts on (`RichLayout.pageNumber(ofParagraph:)` over a layout of the
page view's own making); a click scrolls there. **Link to paragraph**
puts `#p=<paragraph id>` in the address bar, and opening such a link
scrolls that paragraph to the top, selected (`SiteShellState._reveal`:
the caret at the paragraph's START with `pendingReveal = .top`; a
selection whose caret sits at the end is revealed by its end and lands
at the foot of the view). **PDF** downloads the same painter's pages
(24 pages with pictures take ~15 s in a tab). `starling.debug('view' |
'pages' | 'toc' | 'caret' | 'status')` answer scripts; `test/site-web.sh`
drives all of it on `sample-paper` (the BoringCrypto security policy from
the fixtures, 24 pages, footnotes).

**The stored form was 37 to 1 against gzip**, and seconds to decode: the
synthesized coding wrote all 85 fields of the two style structs for every
paragraph and run. `RichDocumentSparseCoding.swift` (generated from the
declarations) writes only what differs from the default and reads a
missing key as the default, so older pages still decode. A text page went
from 13 KB to 3 KB, the security policy from 1.8 MB to 1.0 MB; the 327
corpus documents still round-trip exactly. Still heavy: government
documents whose tables carry kept OOXML per cell (`CellRef`:
continuation paragraphs and XML, borders XML) — the 临沧 notice is 4.0 MB
(134 KB gzipped), the 浙江 credit rules 7.1 MB (192 KB gzipped), and a
same-as-previous-paragraph coding of `cell` would halve the latter. A
model change, left for when the measured load in a tab says so.

**Chinese in a tab.** The web build shipped no CJK face, so every
Chinese character drew as a box — document and UI alike. `web/fonts/
NotoSansSC-VariableFont_wght.ttf` (OFL, 18 MB) is in the font manifest
as `?!`: deferred AND a glyph fallback. On the web `OfficeFonts.substitute`
maps any Chinese face name (宋体, 仿宋, 黑体, Word's list, or any name
with CJK characters) to "Noto Sans SC"; the paragraph builder asks the
page for a family it lacks (`starling_host_request_font`), the loader
fetches it, registers it, and — new — adds it to the glyph-fallback
chain, so the sidebar's titles in Carlito draw too. A Latin-only page
never fetches it (checked: `about` loads 0 Noto resources, the notice 1).
One sans face stands in for 仿宋/宋体/黑体 alike; a serif (Noto Serif SC)
is the next step for the official look, and so is measuring the
pagination against Word's print of these documents with the web faces.
Live from Pages, cold: the notice's JSON 149 KB in 0.2 s, the font 11.4 MB
gzipped in 4.2 s, the page as 34 pages — the first Chinese page a visitor
opens costs those four seconds once.

**Trap, paid for twice tonight:** a NEW file under `sdk/` is not noticed by
an incremental `swift build` in either scratch (`apps/OfficeApp/.build`
and `.build-web-OfficeApp`): the build "completes" in a second, the app
keeps the synthesized coding, and the browser says "This page's content
cannot be read by this build" against pages the native build wrote. Delete
the scratch's `*.yaml` and `build.db` and build again (sdk/CLAUDE.md's
recipe) — then watch for the file in the compile log.

## Where it stands

**2026-10-19:** builder, reader (pages, contents with page numbers,
paragraph links, PDF), both stores, both gates, the demo live on GitHub
Pages with one published document (the BoringCrypto security policy, 24
pages with footnotes). **The user's direction, 2026-10-19: Western
customers** — the two Chinese demo documents were removed from the demo
(they proved the format work; `test/corpus/docx` still holds them), and
the build ships the Chinese font only with a site that has Chinese text
(`SiteBuilder.pruneFonts`), so a Western site's `docs/` never carries the
18 MB.

**Later the same day:** Find in the page (the Find button or Ctrl+F;
typing selects the first match, Next or Ctrl+G the next); Ctrl+C puts
the selection on the system clipboard in a tab (`WebClipboard` in
FlutterWeb behind `Clipboard.provider`, text and HTML through
`navigator.clipboard`; a read answers empty when the browser refuses); a
finger scrolls the document and a tap places the caret (RichEditable's
touch path, confirmed on the user's iPhone); the read-only status page
follows the view. Over a clone: Import .docx… (the file panel; the
document becomes a page under the open one, ids assigned, page setup
kept — `--site-import <repo> <file> [--title] [--under]` from a
terminal), Rename, Delete (children move up), Move up/down among
siblings (`--site-move <repo> <slug> up|down`). `test/site-web.sh`
drives find, the double-click selection, a stubbed clipboard write and
the touch drag; `test/site-build.sh` the import and the move.

**Western demo documents (2026-10-19):** two NIST works, public domain
(csrc.nist.gov, CMVP Module Processes): the FIPS 140-3 security policy
template (81 headings, a table of contents) and the CMVP revalidation
change document (778 table cells), imported with `--site-import` and
credited in the demo's README. Sources tried and dropped: GOV.UK's
Word attachments are forms, not manuals, and its one large report is a
legacy .doc that textutil turns to garbage; the corpus's non-Chinese
documents are bug-tracker attachments of unknown licence.

**A text layer for screen readers (2026-10-19):** the canvas is a picture
to a screen reader and a crawler alike, so the shell page carries the
document's paragraphs and headings as hidden HTML (`<main
id="starling-text" class="starling-sr">`, h1–h3 and p, clipped to a pixel;
shown plainly with scripts off), and the reader replaces it as it moves
between pages (`WebAccessibility.setDocumentText` →
`starling_host_set_document_text`). It is the document's text in reading
order, not its layout; the reader's own controls (the tree, the buttons)
are still only on the canvas, which is the next accessibility step.

**Crawlers (2026-10-19):** with `"url"` in `site.json` the build writes
`sitemap.xml` (every route) and `robots.txt`; the demo has
`https://starling-build.github.io/site-demo`.

**Word and History (2026-10-19):** the reader's Word button downloads the
page as .docx (the source document, for a reader who wants Word); with
`"repository"` in `site.json` a History button opens the page's commits
on GitHub in a new tab (`hostOpenURL` reaches the page through the new
`starling_host_open_url` import — before it, a cross-origin link went to
`pushState`, which only warned). The text layer opens with every page as
a real link, so crawlers reach the whole site from any page. Link to
paragraph now copies the whole address (`starling_host_copy_location`,
the tab's `location.href`) as well as putting `#p=<id>` in the bar.

**Static exports (2026-10-19):** the build writes every page as
`<slug>/<slug>.pdf` (the same painter, with the site's web faces) and
`<slug>/<slug>.docx` beside its shell, links both from the text layer
("Download as PDF · Download as Word", for crawlers, screen readers and
scripts-off readers alike), and the reader's PDF and Word buttons open
those files instead of rendering in the tab — instant where the in-tab
PDF of a 24-page document took 15 s. The manifest says `exports: true`;
over a clone the buttons still render locally.

**The text view and #p= links (2026-10-22):** the text view that stands
in before the interactive reader opens stayed on screen for every `#p=`
link — the browser's jump to the anchor counted as the reader's scrolling
and pinned it, so a paragraph link showed the page as HTML text, which the
no-HTML rule forbids. Only the reader's own input (a pointer, a wheel, a
key, a touch) pins the text view now; the interactive reader then reveals
the paragraph itself. `test/site-fallback-web.py` still passes.

**History in the text layer (2026-10-22):** the page's commits link
rides beside the downloads in the hidden layer, static and live
(`SiteReaderText.Downloads.history`), so a screen reader or a crawler
reaches a page's history without the canvas.

**Links in a page (2026-10-19, late):** a read-only document follows a
plain click on a link (editing keeps Word's ⌘-click); one of the site's
own routes opens in place, anything else in a new tab (`hostOpenURL`,
which on the web is `window.open` — before, a cross-origin link went to
`pushState` and only warned). A `#p=` link's reveal is asked again 150 ms
after the page loads: the editable lays the new document out on its next
frame, and a reveal before that has no layout to measure against and was
lost (the paragraph selected but not scrolled to).

**Where it stands, end of 2026-10-19:** the demo at
https://starling-build.github.io/site-demo/ has the welcome pitch and
three published documents; a visitor gets pages or flow, contents with
page numbers, find, paragraph links that copy, static PDF and Word
downloads, a History link into git, a hidden text layer with every page
as a link, a sitemap; an author on a clone gets the whole Writer, Import
.docx, New page, Rename, Delete, Move, Publish. Gates:
`test/site-build.sh`, `test/site-web.sh`, `test/wiki-web.sh`,
`test/wiki-codec.sh`, all green at commit 88cc0551.

**Authors (2026-10-19, late):** Writer's Backstage Home has "Open
site…" (pick the clone's site.json; the window becomes the reader, with
"Close site" to return), so an author needs no terminal; and
`build/macos-app.sh OfficeApp` puts the web build into the bundle's
Resources/web, where `SiteBuilder.defaultWebStage` finds it, so Publish
from the packaged Writer ships the app. Built and checked: `.stage-macos/
Starling-Office-0.1.0-macos-arm64.zip` (81 MB; verifies after a plain
unzip), and its executable run from another folder with no web stage
named builds a site with the app inside. Ad-hoc signed: a browser
download of it is quarantined and Gatekeeper refuses it (right-click →
Open, or a clone/scp/unzip from a terminal, launches it — see the
macos-app-zip memory); a Developer ID is the step before handing it to
anyone.

Not yet: a smaller stored form for table-heavy documents (above); the
reader's controls (buttons, tree) for screen readers — the text layer
covers the document and the page links; a phone layout for the Writer's
ribbon when editing; a signed and notarized macOS distribution for authors.
The packaged app with its web build exists, as recorded above; distribution
and first-run setup remain unfinished.

## Publishing product plan and review

Review date: **2026-10-19**, against `office2` at `b2230e59`. This is a
source and existing-test review, not a fresh execution of the gates.
The implementation findings below are observed in the code. Customer
segments, commercial options and numerical targets are **proposals to
validate**, not established demand or an approved pricing policy.

### Who this serves and what they get

The first proposed customer is a small organization or independent author
that already maintains substantial documents in Word and needs to publish
them: product manuals, technical reports, handbooks, policies or training
material. Start with public, English-language publications, consistent
with the Western-customer direction above. Select one of these use cases
after interviews rather than building separate products for all of them.

The promise: **bring a Word document, publish a readable web edition, and
update it without rebuilding the document as a website.** Readers retain
page layout and get a phone-friendly flow view, contents, search, links
to passages, and downloadable editions. Authors retain their source and
can move the generated site to another static host.

The first complete journey is: install Writer → create or open a
publication → import a real document → inspect desktop and phone previews
and import limitations → publish → open the verified public URL → revise
and publish again, with existing references still working. Measure that
whole journey; a successful build alone is not success for the author.

Initial scope is public document publishing. Keep the native Swift author
and Swift/Wasm reader, and static delivery. Enterprise Wiki, real-time
co-editing, paywalls, subscriptions for readers, book marketplaces and
EPUB are separate future decisions. They should not delay this journey.

### What the code already supports

`SiteModel.swift`, `SiteStore.swift` and `SiteShell.swift` below are in
`apps/OfficeApp/Sources/OfficeApp/Site/`.

| Capability | Evidence and practical limit |
| --- | --- |
| Local authoring and publication | `LocalSiteStore` saves model files and builds, commits and pushes; Writer's Open site opens a prepared clone. Repository creation, credentials and host setup are still external steps. |
| Document reading | `SiteShell` has pages/flow, contents, find, paragraph links and downloads. Existing `test/site-web.sh` covers selected browser interactions, not a full accessibility or browser compatibility audit. |
| Portable static output | `SiteBuilder` writes routes, model files, search, PDF and DOCX, plus sitemap/robots when configured. Every configured page and its exports are public output. |
| Discovery and accessible text | Shell HTML contains headings, paragraphs, navigation and download links. `SiteTextLayer.lines` does not encode table structure, image alternatives or full document semantics; canvas controls still need accessible interaction. |
| Regression coverage | `test/site-build.sh` covers build/rebuild, import, ordering, exports and a successful publish to a local bare Git remote. It does not demonstrate a host deployment or the failure cases below. |

### Findings to resolve before inviting publishing pilots

| Priority | Finding in current code | Planned change and acceptance evidence |
| --- | --- | --- |
| P0 | `SiteBuilder.build` writes into existing output without removing old page routes, JSON or exports. Deleting a source page can leave its previous publication reachable. | Build a complete staging directory, validate it, then replace only the owned output. A delete-and-rebuild test must find no removed page in routes, JSON, search, PDF or DOCX; a failed build must leave the last good output intact. Previously downloaded files and Git history cannot be recalled by deleting a current page. |
| P0 | `LocalSiteStore.publishNow` runs `git add -A` for the entire repository and commits the index. Unrelated work, including already staged files, can enter the publication commit. | Show the exact publish change set; commit only publication-owned paths. Preserve unrelated staged and unstaged work, and refuse ambiguous repository/output layouts. Test both kinds of unrelated changes and confirm neither is committed. |
| P0 | `SiteBuilder.build` substitutes `{}` when a configured page file is missing. Config slugs and output locations are used as file paths without a dedicated validation pass. | Fail with the affected page named when a source is missing; validate unique slugs, reserved route collisions, base/URL settings and containment of source/output paths, including symlinks. Test missing input, duplicate and traversal slugs, output overlapping source, and reserved names before any output mutation. |
| P0 | `SiteShell._publish` reports “Published.” as soon as `git push` succeeds. No deployment status or served revision is checked. | Distinguish saved, built, pushed, deploying, live and failed. Include a publication revision in output; only report live when the expected revision is served. If the host cannot be checked, report “Pushed; deployment unverified” with the URL. Test delayed and failed deployments. |
| P0 | The publisher has no explicit preflight/recovery workflow for remote changes, missing upstream, credentials or a rejected push. A build/commit may succeed before push fails. | Check repository state and destination before publication; preserve local work, never force-push, and offer a clear retry after reconciliation. Test offline/auth failure, remote advancement, retry after a local commit and a no-change retry. Keep raw diagnostics available without requiring authors to interpret them. |
| P1 | `SiteConfig` has title/base/URL/repository/pages; there is no draft or publication metadata model. All configured pages are exported. | Add schema-versioned, backward-compatible draft/publication state and metadata: author/publisher, summary, language, revision/date and rights statement. Preview a draft locally; verify it is absent from public routes, model files, search, text layers, sitemap and exports. Treat a public source repository as public too: draft exclusion is not access control. |
| P1 | The home route follows the first tree item; references use slugs and paragraph IDs. History opens GitHub commits, not a named reader edition. | Make home selection explicit, preserve URLs across reorder/title edits, and define migration for existing sites. Test paragraph-link survival across edit/save/rebuild. Add named editions and a reader-visible revision before promising durable citations across reimports; offer redirects or a clear archived/removed result when identifiers change. |
| P1 | The packaged app exists but the recorded macOS build is ad-hoc signed; opening a site assumes an existing clone and host configuration. | Ship a signed/notarized Mac pilot package and a guided Create/Open publication flow with destination checks and a local preview. A fresh tester must import and publish without building Starling or editing JSON. Track Windows/Linux author distribution separately; web readers remain cross-platform. |

### Delivery sequence and completion gates

These are ordered milestones, not date promises. Start customer discovery
alongside P0 work. Each milestone needs recorded evidence and an assigned
owner when implementation starts; none is marked completed by this review.

**P0 — reliable publication.** Complete the P0 rows above first. Extend
`test/site-build.sh` or focused Site tests with output replacement,
validation, staged-file isolation and Git failure recovery. Add a local
fake deployment endpoint for pending/live/failure states, plus a controlled
real-host smoke test. Done when a failed publish leaves a usable local
document and last good build, removed pages leave current output, and
the UI accurately says which revision is live. Pause concurrent source
mutations during publication or build from a consistent snapshot.

**P1 — a publisher can work independently.** Complete onboarding,
publication metadata/drafts and stable routes. Add publication identity
(name, logo, restrained colors), a useful document catalog, and author
preview with an explicit list of what will become public. Keep all changes
to branding outside document formatting. Provide update, withdrawal and
rollback instructions; rollback creates a new publication from a selected
revision without rewriting Git history. Done when three external pilot
authors can publish their own document and make a second update with no
developer intervention. Proposed target: first publication within 15
minutes once host credentials are available; record setup time separately.

**P2 — readers can depend on the publication.** In parallel with pilots:

- Expose navigation, search, contents, view switches and downloads to
  keyboard and screen readers, with visible focus. Extend the text layer
  with lists, tables and image alternatives; web/email links and document
  bookmark targets now work as described above. Test VoiceOver
  with Safari and NVDA with a supported Windows browser; a reader must
  find a passage, move to it, copy its link and obtain a download without
  using the canvas visually. Do not claim accessibility conformance from
  the current hidden text layer alone.
- The initial readable fallback is implemented (see 2026-10-20 above).
  Extend its document semantics and validate assistive technology behavior;
  keep failed module/font requests and scripts-off access in regression tests.
- Establish a small, licensed publishing corpus from pilot material:
  a manual, a report with footnotes, and a handbook with long tables and
  images. Compare desktop pages and exported PDF with Microsoft-rendered
  references; separately inspect phone flow for clipped or missing content.
  Record unsupported features at import/preview rather than promising
  exact fidelity for every document. Pin font/runtime versions per build
  and check that native exports and the web reader use compatible metrics.
- Measure cold first-readable time, download size, peak memory and page
  navigation on desktop and a real mid-range phone. Include a 100-page
  document and a 100-document catalog. Proposed starting budget: useful
  fallback text within 2 seconds and the interactive reader within 5
  seconds on a recorded 10 Mbps/100 ms profile; validate or revise after
  baseline measurement. Lazy-load/chunk search and document assets only
  where measurements justify it; record repeat-visit caching too.
- Add canonical URLs, publisher/date metadata and intentional preview
  images, and check base-path/custom-domain links. Test copy/open/back,
  PDF/DOCX downloads and broken routes in Safari, Chrome and Firefox,
  including iPhone Safari and Android Chrome.

Done when representative readers complete find/share/download tasks on
phone and desktop, including assistive technology, and the measured
limitations are documented for authors.

**P3 — repeatable adoption and a commercial decision.** Build this on pilot
evidence, with no new SaaS dependency in the public publishing core:

- Interview five prospective publishers about their existing Word-to-web
  process, update frequency, who owns publication, and where time is lost.
  Recruit three with real material and permission to demonstrate it. Use
  the results to choose the first customer segment and its launch example.
- Demonstrate one document from import through public reading and a later
  update, showing both the Word reference and the web edition. Build the
  publishing landing-page message around this complete workflow. Separate
  author installation from the reader demo and include a short setup guide.
- Measure invited → installed → imported → first verified publication →
  second publication within 30 days; track intervention time and reasons
  for abandonment. Use interviews and opt-in diagnostics first. Reader
  analytics are optional, publisher-controlled work; do not add tracking
  to every static site as a prerequisite.
- Keep the core software open and free, consistent with Starling's scope.
  Test willingness to pay for optional setup/migration, support, or managed
  hosting/deployment and custom-domain administration. Treat these as
  hypotheses; do not set prices or build billing before interviews and
  service-delivery costs establish a useful offer.
- Decision gate: three independent first publications, at least two
  repeat publishers within 30 days, and documented buyer feedback on an
  optional paid service. If readers like the demo but authors cannot ship
  updates, improve that workflow before expanding scope. If no paid need
  emerges, retain a useful free publishing product without assuming SaaS.

### Next implementation slice

The review above describes `b2230e59`; the implementation progress below
supersedes those findings where indicated. Continue with guided author
onboarding and accessible reader controls after the update/build gates pass.
Point-in-time deployment verification and explicit home selection are now
implemented as recorded above, as are optional publication details. Draft
exclusion and archived editions remain planned; a push alone must not be
described as live.

### Market evidence and the author-update workflow

Research checked 2026-10-19. Product documentation demonstrates available
workflows; it is not evidence of market share or demand for Starling.

- [WebWorks ePublisher](https://www.webworks.com/products/epublisher) is a
  direct comparison: authors can keep Word as their source and publish HTML,
  PDF and EPUB. [MadCap Flare's import workflow](https://help.madcapsoftware.com/flare2025r2/Content/Flare/Step1-Starting-Projects/Importing/Other-Apps-Files/Word/Importing-Word-Files.htm)
  documents cleanup and style mapping. Measure time spent repairing actual
  imports and updates, rather than claiming Word-to-web publishing is new.
- [Pressbooks](https://pressbooks.org/) already offers open-source webbooks
  and export formats. [CUNY's author guide](https://pressbooks.cuny.edu/cunypressbooksguide/chapter/cloning-and-importing/)
  describes familiar-tool authoring and formatting cleanup. Its older Google
  Docs advice is superseded by Pressbooks' [August 2026 importer announcement](https://pressbooks.community/t/the-google-docs-importer-is-now-live/4642).
- [InDesign Publish Online](https://helpx.adobe.com/indesign/desktop/save-export-and-publish/publish-work-online/publish-indesign-documents-online.html)
  preserves designed layouts and updates existing publications; it also
  supports an HTML5 package export. [Flipsnack](https://help.flipsnack.com/en/articles/1316657-converting-a-pdf-file-into-a-flipbook)
  publishes PDFs and supports replacement behind the same link. Compare
  Starling with these workflows when a customer already has a finished PDF.
- [Quarto](https://quarto.org/docs/books/) already produces searchable static
  books and multiple downloadable formats. Static hosting is a useful
  delivery choice, not a unique product advantage.
- One [science-advice publisher's account](https://www.reddit.com/r/selfhosted/comments/19ai6yz/)
  describes 30–200-page reports laid out in InDesign and distributed as PDFs,
  with a need for self-hosted web reading, footnotes and bibliographies.
  This is an older individual account, useful for interview recruitment and
  test cases, not a representative market survey.
- [GOV.UK publishing guidance](https://www.gov.uk/guidance/publishing-accessible-documents)
  prioritizes HTML and accessible reading. Treat accessible navigation and
  a useful fallback as pilot requirements, alongside visual fidelity.

**Product decision for this iteration:** an author may continue writing and
reviewing in Word. Starling supplies a publication workflow without requiring
an immediate editor migration. Import → preview → publish → receive revised
DOCX → compare with the saved page → apply → republish at the same URL.
An author choosing to edit in Starling can continue doing so; importing a
later external revision explicitly replaces those local edits, not merges them.

**Implemented in the working tree:** Update from Word previews the whole
revised document and lets the author switch to the saved version. It reports
retained paragraph links and changed/new/removed-or-unmatched paragraphs;
Cancel writes nothing, Apply checks the original bytes and saves locally.
The title, hierarchy and slug are unchanged. Word paragraph IDs survive;
unique exact text provides a fallback when IDs are lost. No position-based
or fuzzy matching is used. Unmatched references receive no automatic redirect.
`--site-update <repo> <slug> <file> [--apply]` exposes the same operation.

Builds now generate into staging and replace owned output after success,
preserving `CNAME`; missing sources, duplicate/reserved/invalid slugs and
source/output overlap fail before generation. Publish commits only publication
paths and reports push success as deployment unverified. Replacement uses
directory renames with rollback on installation error, not a crash-atomic
filesystem exchange; concurrent builds into the same destination remain
unsupported. Full remote-state preflight and deployment polling remain open.

Validation lives in `SiteRevisionTests` and `test/site-publishing.py` (run by
`test/site-build.sh`): real Word round trips, retained/missing identities,
stale previews, output cleanup, failed builds, scoped commits and push retry.
These are implementation regressions, not a substitute for customer trials.

**Next evidence to collect:** three licensed real publications (manual,
report with footnotes, handbook with tables) and a revised source for each.
Compare author time, import repairs, phone reading, accessible navigation,
and second-publication reliability against ePublisher, Pressbooks and a PDF
workflow. Record tool versions and original/reference files. External
publisher interviews and competitor trials have not yet been performed.

**Validation for this implementation (2026-10-19):** eight focused
`SiteRevisionTests` passed, including a real DOCX round trip;
`test/site-build.sh` passed its 63 existing checks and nine publication
regressions. Native scripted interaction verified the revised/current
views, Cancel, and Apply, with the applied text checked on disk.
The previous binary was also used to reproduce a deleted route remaining
in the build before the staging fix. Re-generated export metadata can
produce another commit on retry; retries preserve history rather than
requiring the commit hash to stay unchanged.

The native build and optimized WebAssembly build also passed.
`test/site-web.sh` passed all 34 checks: navigation, search, contents,
paragraph links, phone flow/touch scrolling, clipboard, static downloads,
and project-base routing. No production site was deployed by these checks.


### Author onboarding: local creation (2026-10-19)

Writer Home now has a publication entry point: **New publication** asks
for a title and parent folder, creates a starter page and independent local
Git repository, then opens the reader. **Open publication** reopens an
existing folder through its site.json. Both transitions protect unsaved
Writer documents. The Home content scrolls and its tiles wrap on smaller
windows. This is native Swift UI, not a new browser form.

Creation stages the complete scaffold beside the destination and installs
it only when ready. Existing files, folders and dangling links are never
replaced; nested Git repositories are rejected. The title becomes a safe
folder name, and errors leave the chosen parent intact. No remote is
configured, no commit is made and no content is uploaded.

`--site-create <parent-folder> <title>` uses the same path. The new folder
includes PUBLISHING.md with the remaining GitHub Pages setup, project-base
configuration, first upstream push and source/download visibility. The
Publish UI explains that pushing is distinct from verifying deployment.

This completes the local-creation slice of P1, **not** end-to-end hosted
onboarding: connecting hosting and editing site URL/base are still manual.
Next: an in-app hosting settings and readiness flow, followed by deployment
verification and the accessible reader controls already planned above.

Validation: five creation regressions cover readable configuration and source,
local-only Git state, existing paths, invalid destinations, title/path safety,
and cleanup after installation failure. The eight source-revision tests still
pass. `test/site-build.sh` passed its 63 existing checks and ten publication
workflow regressions, including creating and building a fresh publication
without a hand-written site.json. Native scripted interaction verified title
entry, folder selection, creation, reopening, the publish guidance, and the
unsaved-document prompt. Embedded Writer hides the standalone publication
entry points. Scripts use the existing in-app key driver with STARLING_IME=0;
this validates the fallback key path, not native IME composition.

The final native build and optimized WebAssembly build passed. The UI also
verified an existing-folder error without replacing its contents. Test
publications were moved out of Documents into temporary artifacts. No live
hosting was connected or deployed during this validation.


### Hosting settings and local publish checks (2026-10-19)

The native publication reader now has a **Hosting** form. Authors can edit
the publication title, GitHub repository and HTTPS website address without
editing JSON. The GitHub Pages helper derives project and user-site URLs;
the saved website path supplies the asset base. Custom HTTPS domains are
accepted, with DNS and CNAME setup still external. Config saves preserve the
page tree and unknown fields and reject a snapshot changed since opening.

The later writer-focused guide combines these local operations as **Save and
connect**: save the publication details, then add origin only when absent. It
accepts an existing matching HTTPS or SSH remote without replacing its
transport and refuses a different origin. If connection fails, the saved
publication details remain available for correction. Neither operation contacts
GitHub, creates a remote repository, commits or uploads files.

**Check saved setup** inspects local Git identity, branch/upstream, origin,
conflicts and in-progress Git operations, web-reader availability, and the
saved URL/base/repository relationship. UI Publish requires these local
checks before building; the CLI retains support for arbitrary Git origins
and checks local Git prerequisites before it changes build output or commits.
These checks do not establish remote access, remote branch freshness, valid
DNS, GitHub Pages configuration or a deployed revision.

Publishing now uses an explicit origin and branch refspec, preserving an
existing origin target branch and setting the upstream on first publish.
Unrelated remote.pushDefault, push.default and remote.origin.push settings
cannot redirect the operation or add other branches. Multiple origin push
URLs and an upstream on another remote require review instead of guessing.
Rejected pushes still preserve the local commit; no force push is used.

The later first-publish guide adds repository-local author identity setup in
the app. GitHub repository creation, Git authentication and enabling Pages
remain external steps. The live-marker check is also implemented; real hosting
validation and reader accessibility remain open. A successful local check or
push alone is never labeled "live".

Validation: nine `SiteHostingTests` cover project/user/custom URLs, unsafe
addresses, preserved unknown settings and page trees, stale saves, idempotent
local connection, matching SSH transport, conflicting remotes, readiness,
active Git operations and explicit push targets. The five creation and eight
revision tests also pass. `test/site-build.sh` passed 63 existing checks and
13 publication regressions. New integration cases exercise first push,
preflight failure without output/commit, and unrelated Git push defaults;
first push, blocked setup, explicit destination and rejected-push retry were
rerun against the final native binary. All remote writes in tests targeted
temporary local bare repositories.

Native UI scripting verified form entry and Tab navigation, automatic Pages
URL, local save, origin connection, and refusal to replace a conflicting
origin. Source bytes were unchanged, and no commit was created by form actions.
The existing in-app key driver used STARLING_IME=0; native IME composition
was not exercised. No production repository was contacted or deployed.

The final native and optimized WebAssembly builds passed. A future deployment
check should compare a unique build identifier at the saved public address;
HTTP success alone must not count as proof that the new revision is live.
