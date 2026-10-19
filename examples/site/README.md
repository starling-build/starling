# A site from this folder

Copy this folder into a new git repository and you have a site whose
pages are Writer documents.

    site.json          the site's title, its address, its pages in order
    pages/<slug>.json  one page each, as the document model
    docs/              the build — what GitHub Pages serves (made by Publish)

Edit it with Starling Office on the clone:

    OfficeApp --site <clone>

The reader opens on the first page. Edit is the whole Writer on the page;
Save writes the page file. New page, Import .docx…, Rename, Delete, Move
up/down change the tree. Publish builds `docs/`, commits with your
message and pushes. From a terminal:

    OfficeApp --site-import <clone> manual.docx --title "Manual" [--under slug]
    OfficeApp --site-move <clone> <slug> up|down
    OfficeApp --site-build <clone> [--base /repo/] [--web <stage>]
    OfficeApp --site-publish <clone> -m "message"

Then, on GitHub, Settings → Pages → deploy from branch `main`, folder
`/docs`. For a project site (`https://<user>.github.io/<repo>/`) set
`"base": "/<repo>/"` in `site.json` first; set `"url"` for a sitemap and
`"repository"` for the reader's History link.

The web build the publish ships comes from `build/web-app.sh OfficeApp
--package apps/OfficeApp` in the Starling repository, found through
`--web`, `STARLING_WEB_STAGE`, or `.stage-web-OfficeApp` in the working
directory.
