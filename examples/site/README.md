# A site from this folder

To start your own publication in Writer, use **File → Home → New
publication…**. Choose a Word document or **Start blank**, then name the
publication. For a Word document, **Open draft** shows its reader preview;
the document becomes the first page and your original file stays unchanged.
For a blank publication, **Start writing** opens Writer directly with an empty
document and the caret ready. Nothing is uploaded.

After opening a publication, **File → Home → Continue publishing** remembers
it and the last page you visited, including after restarting Writer. **Close
publication** returns to Home. If a folder is unavailable, its entry stays in
the list; use **Open publication** to find its new location. A removed page
falls back to the publication’s first page.

Use **Edit document** to write, then **Save → Back to preview** to review the saved changes. Compare
**Page preview** with **Reading view**, and use **Add a Word document** for
more material. **New page +** asks for a title, then opens that page in Writer
ready to type. **Back to preview** offers Save, Don't Save or Cancel when you
have unsaved edits. Save writes back to the publication without asking for a
new file name. Saving is local; publishing remains a separate action.
**Page options** holds rename, ordering and deletion.

The preview shows the status of your saved publication:

- **Saved locally; no matching publish record**: this checkout has no usable
  record of sending this version. It may already exist online; that is unknown.
- **Saved changes need publishing**: publication files differ from the last
  successfully sent version, even if the changes have been committed locally.
- **Saved version sent to hosting**: the saved files match that upload.
  This does not confirm that the website has deployed it.

Status refreshes when you open a page, return from editing, change publication
settings, or finish publishing. After changing files outside Writer, use
**Publish → Check publication status**. This check is local and does not
contact the website. A failed upload keeps the previous successful record.

After a successful publish, choose **Check live website**. When the website
returns the build marker for your last successful upload, **Open website** and
**Copy website link** appear. Open it to review, then share the link with readers.
The check shows its time; it confirms the uploaded version's marker, not every
page's rendering. Any newer saved changes still need publishing.

If hosting is still updating, wait and check again. Older publications need
one new publish to add the version marker. Changing the website address needs
a fresh publish before checking that address. Checks are not saved between
sessions and do not create a hosting service or enable GitHub Pages for you.

When ready, choose **Publish**. If your publication has no website details,
the app opens the setup guide automatically:

1. **Choose a home:** open GitHub's repository creation page, create an empty
   repository, and paste its address. Leave Website address blank to use the
   GitHub Pages address, or enter a custom HTTPS address. **Save and connect**
   saves the details and connects locally. It preserves matching existing
   remotes and refuses to replace a different destination.
2. **Set your publishing name:** enter your name and email, then **Save author**.
   These appear in change history and apply only to this publication. The app
   links to your GitHub email settings to find a no-reply address, and to sign-in
   help. Saving an author does not authenticate your GitHub account.
3. **Publish and enable the website:** **Continue to publish** is enabled when
   local checks pass and form changes are saved. Publish, then use **Open
   website settings on GitHub** to enable Pages. The guide shows your actual
   publishing branch and /docs. A custom output folder needs a deployment
   workflow. Return to the preview to check the live website and share its link.

Creating the repository, signing in and enabling Pages are still external steps.
The generated `PUBLISHING.md` also describes this workflow.

Publish checks local setup before building and sets the branch's upstream on
the first push. It sends only the current commit to the configured origin
branch, regardless of unrelated Git push defaults. A rejected push retains
the local commit for retry. Remote changes, credentials and live deployment
are not verified by the local checks.

While publishing, the preview shows whether it is checking setup, preparing
the website, saving history or uploading. If publishing fails, recovery advice
stays beside the controls and your change description stays available for retry:

- **Hosting access needs attention:** check the repository address and sign-in;
  the app provides GitHub sign-in help.
- **The online publication has other changes:** review and merge the remote
  work in Git before publishing again. The app never force-pushes or merges
  automatically.
- **Hosting rejected this update:** review the repository's rules and limits.
- **The upload could not be confirmed:** check the connection and hosting,
  then retry. A connection failure can happen after the server receives data.

Your saved writing and committed publication remain local after a failed upload.
The previous successful-upload record is retained. **Try publishing again**
rebuilds from your current saved files; it does not discard your writing. An
upload that succeeds but cannot save its local record is reported separately.
Git's raw upload errors are not displayed because they may include credentials
or server-provided text. Git terminal credential prompts are disabled during
upload; credential managers and SSH still use the computer's existing setup.

The equivalent command creates a new folder under an existing parent:

    OfficeApp --site-create /path/to/parent "Product handbook" [--from manuscript.docx]

Or copy this example folder into a new Git repository to explore a site
whose pages are Writer documents.

    site.json          the site's title, its address, its pages in order
    pages/<slug>.json  one page each, as the document model
    docs/              the build — what GitHub Pages serves (made by Publish)

Edit it with Starling Office on the clone: in Writer, File → Home →
"Open publication…" and pick the clone's `site.json` ("Close publication" brings Home
back), or from a terminal:

    OfficeApp --site <clone>

The reader opens on the first page. Edit is the whole Writer on the page;
Save writes the page file. New page and Add a Word document add material;
Page options contains Rename, Delete and Move up/down. Publish builds `docs/`, commits with your
message and pushes. From a terminal:

    OfficeApp --site-import <clone> manual.docx --title "Manual" [--under slug]
    OfficeApp --site-update <clone> <slug> revised-manual.docx
    OfficeApp --site-update <clone> <slug> revised-manual.docx --apply
    OfficeApp --site-move <clone> <slug> up|down
    OfficeApp --site-build <clone> [--base /repo/] [--web <stage>]
    OfficeApp --site-status <clone> [--out <dir>]
    OfficeApp --site-publish <clone> -m "message"

To keep writing in Word, select the existing page and choose **Update from
Word…**. Inspect the revised document, switch to **View current** to compare,
then **Apply update**. Cancel leaves the saved document untouched. The
command-line update previews the paragraph counts unless `--apply` is set.
Updating replaces the page's content, including local Writer edits, but
keeps its title, tree position and public URL; Publish is a separate step.

Paragraph links survive when the revision keeps Word's paragraph IDs, or
when an exact, nonempty paragraph text occurs only once in each document.
Ambiguous or changed paragraphs without an identity get fresh IDs; the
preview reports removed/unmatched references. This is replacement, not
merging edits from two authors. Page setup and formatting come from the
revised document. A page changed on disk since preview must be reviewed again.

Builds replace their generated output only after generation succeeds, so
deleted pages and old exports disappear from the current site. Keep custom
files outside `docs/`; its `CNAME` is preserved for custom domains. Publish
commits only `site.json`, `pages/` and the output folder, leaving unrelated
staged files alone. A successful push is reported as deployment unverified;
check the hosting service and public URL before announcing the update.

Then, on GitHub, Settings → Pages → deploy from branch `main`, folder
`/docs`. For a project site (`https://<user>.github.io/<repo>/`) set
`"base": "/<repo>/"` in `site.json` first; set `"url"` for a sitemap and
`"repository"` for the reader's History link.

The web build the publish ships comes from `build/web-app.sh OfficeApp
--package apps/OfficeApp` in the Starling repository, found through
`--web`, `STARLING_WEB_STAGE`, or `.stage-web-OfficeApp` in the working
directory.
