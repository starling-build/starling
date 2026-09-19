# The 3D desktop's city

The world the Filament renderer walks you into when the 3D desktop is on.
Its composition follows `Wallpapers/city-night.png`: Victorian
houses frame a downhill street, the Ferry Building and clock tower sit at
the waterfront, and a red suspension bridge crosses the bay in front of
layered headlands. This is real, walkable geometry, not a projected image.
It interprets the wallpaper rather than claiming an exact reconstruction.
`build/tools/city-night.py` authors the layout; `voxel-world.py` supplies
the mesh, atlas, animation and sky exporters. Lighting now evokes early
evening, around sunset: low warm sunlight, a peach-to-blue sky, brighter
ambient fill and restrained window/lantern emission. It is an art-directed
lighting preset, not a geographic or seasonal simulation of 6 pm. The
matching 2D wallpaper is `Wallpapers/city-sunset.png`; the original dark
version remains available as an alternate asset.

The refinement pass adds inward-facing multi-storey bays, transoms,
layered cornices and dentils, parapets, chimneys, planted window boxes,
iron garden rails, staggered paving and geometric stone arcade arches.
Broken low-luminance reflection trails sit on the bay surface. The
headlands have smoother stepped silhouettes, scattered settlement lights
and restrained distance-color emission; these are stylized atmospheric
cues, not volumetric fog or physically traced reflections. The animated
clouds use smaller overlapping volumes instead of three broad slabs.

The central brick pile and storefront prototype have been replaced by a
low bronze rail with warm stone supports. `world.json` supplies the rail's
card origin and maximum size. Only running apps appear, centered along the
curve; at most five cards are visible. Scroll over the exposed rail or use
Previous/Next beside the launcher to reveal more apps. A range indicator
shows the current slice; closing apps clamps it to the remaining cards.
Multiple windows share one app card with a count badge. Alt+Tab includes
offscreen and minimized windows and reveals the selected app on the rail.
Each card shows an aspect-preserving live copy of
its most recent window, with an app name beneath it.
These previews only select apps: client input belongs to the full-size
window brought forward. Alt+Tab retains the ring and brings the selection
forward without moving the camera. A bottom-center launcher opens the app
grid. Its cream enamel button has a bronze rim and four inset city-colored
squares, with warm hover and pressed feedback. The flat desktop's launcher
is unchanged. Closing an app removes its card. The center is an open overlook.

In 3D the launcher opens a centered cream app-directory panel with bronze
trim, matching search and close controls, and muted enamel app tiles.
The city remains visible around it. Installed third-party icons retain
their original artwork. The grid scrolls within the panel; search, Enter
to launch, and Escape to clear/close retain their existing behavior.
This world-specific panel is used with either shell style, while each
style's normal launcher is preserved on the flat desktop.

Native apps follow the same presentation through `StarlingPalette.city` in
the SDK. The existing desktop-3D socket message selects it at launch and
repaints running apps when the mode changes, without changing the saved
2D style or dark-mode preference. Settings, Files (including the picker),
Calculator, Text Editor, Image Viewer, App Store and Task Manager use warm
opaque surfaces and sage accents. Terminal tabs and video controls match
the trim while terminal output, media pixels and document formatting keep
their original colors. The rendering diagnostic app is intentionally not
recolored, nor are third-party applications.

The window ring retains its original coordinates; the live clock moves
with the Ferry Building to the waterfront. The
entrance camera stands 13 m back with a 3.5 m elevated viewing offset and
a slight downward pitch to show the descending street and bay together;
selected windows are centered at reading distance with thin bronze frames.
Window title bars use cream enamel with dark lettering, a fine bronze edge,
and muted terracotta/ochre/sage controls with always-visible action glyphs.
The scene texture and interactive title bar share the same painters; button
hit targets, dragging, double-click maximize and depth scrolling are unchanged.
Trees and lamps sit outside the window ring. Buildings remain decorative,
without collision geometry; the fractional height map supplies the walking surface.
The bridge cables and trolley rails are oriented beams; the buildings
use architectural boxes in the same atlas material. Six nearby lanterns
are actual glTF punctual lights, registered alongside the renderables.

Everything here is **generated**, not authored: `build/tools/
voxel-world.py` writes the glTF (`room.glb`), the block atlas and the
frame tile, `world.json` (where the square, the pool, the clock and the
camera's home are), and — through Filament's `cmgen` — the sky's two
KTX files. Regenerate with

    python3 build/tools/voxel-world.py             # includes the sunset sky
    python3 build/tools/voxel-world.py --no-sky     # geometry-only iteration

and commit what it writes; `--no-sky` skips `cmgen`, which is only on a
box with a Filament build. The sky is procedural (a sunset gradient and sun),
so nothing here is anyone else's.

`build/stage.sh` installs this directory as `share/starling/worlds/city`,
and the shell chooses the Filament renderer whenever that world and
`libstarling_room.so` are both beside it (`STARLING_ROOM=gl` forces the
shell's own GL room; `STARLING_ROOM_DIR` points at a world elsewhere).

### Ambient motion

Ambient life is built into the glTF: five drifting voxel clouds, a gently
bobbing bay ferry, and a double-ended red-and-cream cable car descending
the street with pauses at its two stops. All tracks loop continuously and stay behind the app
interaction plane. The renderer samples independent glTF animation clips
on one shared monotonic clock, so motion agrees across displays.

`ambient_animation` in `world.json` enables a 20 Hz scene-only refresh.
It does not rebuild the shell or app widgets. Refresh is skipped while
locked or showing the screensaver, and cancelled when the environment is
released. Worlds without this flag remain event-driven. Regenerating the
city also regenerates the actors and their tracks; `test/city/motion-test.py`
checks the shipped animation buffers, closed loops and route boundaries.

### Multiple displays

Physical displays share one city, camera, lighting pass, and scene texture.
The virtual desktop's logical bounds determine the texture's aspect ratio;
each output shows its own crop. The off-axis lens stays centred on the
primary output, so adding a monitor extends the view rather than shrinking
the main plaza or creating a second vanishing point. Mixed-DPI outputs use
logical coordinates for projection and input, and the render target is
capped at 8192 pixels per side.

Each output retains one active app pane at its own interaction centre.
Launching a new app from that display's city launcher places it there.
The running-app rail and Alt+Tab remain shared. Walking and camera glides
move the whole view continuously; crossing a monitor boundary never loads
another world. Window hit testing and attached menus use the same global
projection, translated into each output's local coordinates.

`test/displays/scene-lens-test.swift` covers single/mixed-DPI bounds,
negative layout origins and a secondary primary. The broker's
`desktop_3d query=true` includes output rectangles, the global pointer and
shown-pane ownership for live multi-display checks.
