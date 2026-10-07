# Starling software factory

The static landing page at `starling.build` introduces Starling as an open,
free software factory. A six-slide presentation covers the mission, Terminal,
Office, Desktop, the shared SDK, and the open-source project. Terminal, Office,
and Desktop each have their own product slide and direct action links. Office
also links directly to the live Writer, Slides, and Sheets applications.

The presentation uses semantic HTML and CSS illustrations. Text and product
links remain native browser elements. No framework, build step, web fonts, or
WebAssembly runtime is required. This shares the Office landing page's visual
and navigation style, while keeping the main site lightweight.

- `index.html`: presentation, product links, desktop film and installation dialogs.
- `styles.css`: responsive layouts, keyboard focus, and reduced-motion support.
- `main.js`: hash navigation, buttons, keyboard and touch navigation, dialogs,
  desktop preview toggle, and video controls.
- `img/`: Starling mark, social preview, and actual desktop captures.
- `video/`: the existing 2:50 narrated desktop demo and English captions.

All six slides remain readable as a regular page with JavaScript disabled.
The film and installation guide also have direct fallback links. With
JavaScript enabled, the selected slide is shareable by its hash (`#terminal`,
`#office`, `#desktop`, `#sdk`, or `#open`). The old `#film`, `#install`, and
`#perspectives` links still lead to the desktop content.

## Preview

```sh
python3 -m http.server --directory ui --bind 0.0.0.0 8011
```

For full video seeking, use a static server with HTTP byte-range support.
The video uses `preload="none"`; sound starts only when the visitor chooses
playback. Closing the film pauses it. Native player controls remain available.

## Publish

The existing public GitHub Pages repository is `starling-build/www`, serving
`main` from its root with the custom domain `starling.build`. `ui/deploy.sh`
publishes the page, stylesheet, script, CNAME, images, and video. It replaces
the deployment repository's site content; use it only for an intended release.
Keep stylesheet and script references versioned when packaging a deployment,
so cached browsers load the matching presentation controller and layout.

The Cloudflare analytics beacon loads only on `starling.build` and
`www.starling.build`; local previews make no analytics requests.

## Product and media provenance

Terminal links to the published `terminal-v0.2.0` release, which includes remote
workspaces and persistent sessions. Its panel is a command-line illustration,
not a captured benchmark. Office links to `openoffice.starling.build` and the
three live application domains. Desktop installation retains the published
0.5.0 Ubuntu and WSL2 instructions. The SDK links to the repository's `office`
branch, where the Office web platform work is available.

Desktop screenshots and footage come from the running Starling desktop.
The 2D/3D toggle switches between those still captures. The demo has original
instrumental music and AI-generated English narration. The sample film is the
Big Buck Bunny trailer, © 2008 Blender Foundation,
https://www.bigbuckbunny.org/, CC BY 3.0,
https://creativecommons.org/licenses/by/3.0/, resized for playback. Attribution
is retained in the film dialog and in the film.
