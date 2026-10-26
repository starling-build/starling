# Starling Office product website

`office.starling.build` is a task-oriented entry to the existing Swift/WASM
editors. The project landing page remains `openoffice.starling.build`.
The homepage accepts DOCX, XLSX, and PPTX files; `/writer/`, `/sheets/`, and
`/slides/` give each task a useful, crawlable entry page. Each offers opening
a local file, creating a blank file, and editing a bundled example.

The start screen introduces the suite with a short heading, one sentence, and
three benefits (free and open source, no account, no cloud uploads), followed
immediately by the file controls. It uses an app sidebar, a local-file opener, blank-file cards,
and compact example rows. Help is collapsed. There are no promotional hero,
feature, or screenshot sections; the OpenOffice site provides that introduction.
The HTML/CSS entry pages require no editor download until an action is chosen.
The small JavaScript launcher passes a local file through an in-memory blob URL
to the existing `initialFiles` bridge. It does not upload or persist documents.
The editor, renderer, and fonts are hosted on the same origin. The editor keeps
its existing file picker, Save behavior, and unsaved-change warning. Only DOCX,
XLSX, and PPTX are advertised; opening does not promise lossless compatibility.

## Package and preview

Use a tested deployment checkout or a compatible `build/web-app.sh` stage:

```sh
python3 build/office-product.py --runtime /path/to/writer-deployment --out /tmp/office-product
python3 -m http.server 8152 --bind 0.0.0.0 --directory /tmp/office-product
```

The output must be new. It includes all four pages, local assets, examples,
robots.txt, sitemap.xml, CNAME, and one shared runtime. The runtime directory
is content-addressed, including its JS imports and fonts. A build-info.json
retains deployment provenance when available. Font URLs are rewritten for
deep entry pages. Existing app and landing deployments are not modified.

`?start=new` and `?start=example` are supported on the three app pages. Each
canonical URL excludes these launch parameters. The page source contains
the headings, features, navigation, and FAQs without running JavaScript.

## Publication

Publish the package root to a separate static host, with the custom domain
`office.starling.build`. Configure DNS for that host and HTTPS before sharing
the production URL. Do not publish over the `openoffice` deployment repo.
Verify all three examples open and save using `test/office-examples-web.py`
with the new URLs ending in `?start=example`, and check the local file workflow.
For the product page's file picker, run:

```sh
python3 test/writer-local-file-web.py --entry-page --url http://127.0.0.1:8152/writer/ --out /tmp/product-file-check --load-ms 25000
```

Then verify the domain in Google Search Console and submit `/sitemap.xml`.
Packaging alone neither creates DNS records nor submits pages to Google.

Product names are Writer, Slides, and Sheets. Microsoft names appear only in
file-compatibility descriptions. Only `/writer/`, `/slides/`, and `/sheets/`
are published as app entry pages and included in the sitemap. The former
`/word/`, `/excel/`, and `/powerpoint/` addresses are removed, with no redirects.
