# Starling Desktop website

`index.html` is a regular web page at `starling.build/desktop/`. It covers the
native foundation, everyday applications and tools, agent workspaces, 2D and 3D
views, the captioned desktop film, and installation. The 3D city is one feature
within the broader desktop. Text and links remain usable without JavaScript.

Serve `ui/` and open `/desktop/`. This page shares `../styles.css`, `../img/`, and
`../video/` with the main Starling site. `build/landing-pages.sh` includes Desktop
in the main site's static package; `ui/deploy.sh` publishes it with that site.

Existing decks and slide-player files are retained as presentation samples, but
are not referenced or packaged by the website. Regenerating those samples with
`build/tools/desktop-landing.py` is optional and does not update this web page.
