# Starling Desktop presentation

The dedicated page at https://starling.build/desktop/ is an editable six-slide
PPTX presentation rendered by Starling Slides, using the same browser runtime
and navigation as the Office landing page. The main Starling page links here.

Slides cover the native architecture, Linux app compatibility and built-in
tools, dedicated agent workspaces, 2D and 3D views, and installation. 3D is one
feature in the broader desktop. Footer actions link to the SDK, source,
installation instructions and film. Keyboard, phone navigation, portrait decks,
accessible descriptions and downloadable editable PPTXs are supported.

Regenerate the decks from the repository root:

```sh
python3 build/tools/desktop-landing.py
```

The generator reuses the Office PPTX package structure, replacing its slide
content with editable Desktop text and shapes. Copy the runtime selected by
`ui/openoffice/runtime.json` into `ui/desktop/`, retaining the same relative
runtime path and manifest. Browser runtime files are ignored build outputs.
Serve `ui/` locally, then capture fallback images from the actual Slides canvas:

```sh
node build/tools/desktop-landing-posters.mjs http://127.0.0.1:8011/desktop/
```

Publish this directory, including the selected runtime, under `desktop/` in
`starling-build/www`. Keep the existing root CNAME (`starling.build`). Version
styles.css and slides.js in the published HTML to refresh cached assets.
