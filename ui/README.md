# Starling desktop showcase

A single-page, static site for `starling.build`, focused on the 2D and 3D desktop.
No build step, framework, remote fonts, or runtime dependencies.

- `index.html`: introduction, desktop preview, narrated film, app workspace, Ubuntu installation instructions, project links.
- `styles.css`: responsive layout and reduced-motion support.
- `main.js`: 2D/3D screenshot toggle, video play control, chapter navigation.
- `img/`: actual desktop captures and the Starling mark.
- `video/starling-desktop.mp4`: 2:50 narrated demo, H.264 1080p with AAC stereo audio, embedded chapters and optional English subtitles (about 28 MB).
- `video/narration.vtt`: narration captions for the web player.

The video uses `preload="none"` and a WebP poster. Its audio starts only after a
visitor chooses playback. Native player controls remain available without JavaScript.
The desktop toggle previews real screenshots; it does not simulate a running desktop.

## Preview

```sh
python3 -m http.server --directory ui 8000
```

For full video seeking, use a static server that supports HTTP byte ranges.
The development machine also serves this folder at `http://192.168.68.61:8081/`
through the `starling-site-preview` user service.

## Publish

`ui/deploy.sh` publishes only the page, stylesheet, script, CNAME, images, and video
to the existing `starling-build/www` site repository. It removes the previous
multi-page site from the deployment target. Run it only when publishing is intended.

The existing Cloudflare analytics beacon is loaded only on `starling.build` and
`www.starling.build`; local previews make no analytics requests.

## Media provenance

Screenshots and footage come from the running Starling desktop. The narrated demo
was prepared in `/home/starling/Videos/starling-city-demo-v4/`. The desktop footage
is live; the website's 2D/3D switch uses still captures from that footage.

The demo contains original instrumental music and AI-generated English narration.
The sample film is the Big Buck Bunny trailer, © 2008 Blender Foundation,
https://www.bigbuckbunny.org/, CC BY 3.0, https://creativecommons.org/licenses/by/3.0/,
resized to 720p for playback. Attribution appears on the page and in the film.

The old guide, SDK, terminal, Windows, getting-started and comparison pages have been removed, along with media no longer used by the site or documentation.
Older media still referenced by release notes and performance reports is retained.
Project information is linked directly on GitHub.
