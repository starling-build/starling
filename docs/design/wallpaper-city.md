# Wallpaper city reconstruction

Branch: `feature/wallpaper-city`. Reference: `shell/Resources/Wallpapers/city-sunset.png`.

This is an independent geometry/composition study, not a replacement desktop world.
The installed city and its app placement are unchanged. Hidden surfaces are
interpretations of the single reference image.

## Reproduce

From the repository root, with Python, numpy, Pillow, Filament cmgen and roomtest:

```sh
python3 build/tools/wallpaper-city.py --out /tmp/wallpaper-city --render
```

`--cmgen PATH` overrides the default `~/dev/filament/gles/bin/cmgen`.
`--no-sky` reuses the previous bake in the output directory during geometry work.
`--reflections` opts into experimental screen-space reflections. They remain
disabled in the normal preview because their GPU cost depends strongly on view.
`--sky-audit` adds four compass headings and two pole views from the bay to
the rendered comparison page. These help reveal seams outside the main view.
`--walk-audit` adds six eye-height checkpoints from the hill to the terminal.
These are fixed camera renders, not an interactive walk or collision test.
Build roomtest with `build/build-room.sh --test` if it is not available.

Outputs include the GLB, sky/IBL, generated wave normal map, `view.png`,
`architecture.png`, `waterfront.png`, three motion checkpoints and `comparison.html`. Open the HTML locally to compare the wallpaper and actual GPU
render, side by side or stacked. `reference-camera.json` records the fixed camera
and light settings. The preview is 1672 × 941, at position (0,40,18), yaw 0 and
pitch 7.5 degrees. No desktop configuration is emitted: walking/collision,
workspace placement and multiple display integration remain unimplemented here.

## Continuous camera preview

After generating the world and building roomtest:

```sh
python3 build/tools/wallpaper-walk.py --world /tmp/wallpaper-city --out /tmp/wallpaper-city/walk.mp4
```

This records a 100-second, 960 × 600, 24 fps scripted route along the sidewalk,
through the shop passage, up the quay stairs, and along the terminal, ending with
a look at the tower. It samples animations at the camera timestamps. The CSV
camera path and renderer log are saved beside the MP4. FFmpeg is required;
recording uses about 4 GB of temporary raw frames, deleted after encoding.
`--fps` may be reduced for a quick route review. A subsequent comparison render
embeds `walk.mp4` if it is present in the world output directory.

`ROOMTEST_PATH` is the renderer's optional camera CSV input, with six columns:
`seconds,x,y,z,yaw_degrees,pitch_degrees`. Timestamps must increase. In this mode
the output is upright RGB24 frames instead of a PPM. Camera-path GPU checks
verify invalid-input rejection, exact first- and last-frame agreement with independent still renders,
frame layout, and visible camera movement. The encoder workflow also decodes
three checkpoints and rejects an apparently frozen result. The route is authored against known
surfaces and eases stair height changes; it is not interactive navigation or a
collision/physics implementation. The installed desktop is unchanged.

## Current reconstruction

- Descending cobblestone street with a curved crest, rails, retaining walls,
  planting and framed lanterns with slender posts, caps and finials. Preview
  point lights are centered in ten street lanterns and four terminal arcade bays.
- Stepped Victorian rows, projecting windows, cornices, stoops and smaller leaf
  voxels; ten foreground houses now use three-sided bay windows, recessed
  sashes and curtains, paneled doors, continuous stair rails, cornice brackets,
  and three roof styles. Uphill-facing elevations also have projecting window
  bays; modeled clapboard laps and basement joints add surface relief. Cream
  and rose houses frame the right side, with lighter warm limestone trim.
- Trees have separate overlapping crowns and exposed branches. The nearest
  left tree sits farther from the road to reveal more of the blue house.
- A red cable car with framed windows, roof tiers and round lamps, plus a ferry.
  The trolley samples the curved street and changes pitch; the ferry turns along
  its route. Translation and normalized rotation tracks are exported together.
- Arched terminal facade, an open belfry and lantern above the clock, roof
  skylights, quay railings, bollards and wooden finger piers.
- A passage through the waterfront shops connects the descending sidewalk to
  the terminal quay via ten 13.2 cm risers and continuous handrails. The quay
  railing leaves the stair exit open.
- Waterfront shops have framed windows on their exposed side walls. An
  L-shaped near shore opens a wider basin in front of the terminal, with benches
  and planters along the promenade. The downhill right-hand house row bends
  away from the road to reduce occlusion, and the terminal arcade is warmly lit. The island and bridge remain separate distant landmarks.
- Taller inhabited hills with irregular building footprints, lit windows and
  groves; a rounded island shoreline with rocks, planting, a lighthouse and jetty.
- A generated sky with puffy peach cloud banks, clear blue gaps, a small
  analytic sun on the right, and
  cooler blue water with deterministic wave normals. The 1024-pixel normal map
  combines 96 wave components over a 144-metre tile to reduce obvious repetition
  while retaining visible waves at the reference distance.
- Optional height-based haze that starts 160 metres from the preview camera,
  softening the bay while preserving the foreground and skybox.

The sunset preview balances 22,000 lux of warm direct sunlight with 5,000 lux
of environment illumination. Compared with the earlier 12,000/6,500 setting,
this gives the cornices and foliage stronger edge light while retaining
environment illumination in the shadows. Amber window emission and local lights down the street and
under the terminal canopy preserve warmth in shaded areas. These are art-directed
preview settings; they have not been accepted for the installed desktop.

The sky is a raster environment; all city geometry remains 3D. Source images and
exact generation/edit prompts are in
`../../shell/Resources/Worlds/wallpaper-city/materials/README.md`. The bake remaps
latitude and longitude to fit more cloud banks into the reference view,
and uses warmer indirect light for the architecture. The v4 source reduces wraparound mismatch; the bake then enforces matching
edge samples and uniform pole caps. A sampling regression test covers deliberately
mismatched input. The six-direction GPU audit includes the formerly visible seam
and zenith; the downward view shows the water. Continuous movement still needs
review. Outside 45 degrees from the reference heading, compressed cloud detail
blends into the source's clear edge gradient; at 105 degrees and beyond the sky
is clear. This preserves the main sunset composition and avoids stretched rear
cloud bands. The transition is smooth and uses linear-light color blending.

## Validation and limits

Generation checks finite geometry, unit normals and valid indices. The focused
material-options test verifies embedded repeating normals, triangle preservation,
and isolation of prototype overrides from default exports. It also covers an
exporter edge case where every face is assigned a custom material. Nine existing
city tests pass against the shipped world. The prototype renders on the GPU. The final export also passed buffer-bound,
outward-winding, non-degenerate-triangle and closed-motion-track checks.
Three waterfront tests verify outward face winding, open basin/solid shore
samples, and the quay connection's riser heights and open exit. The facade test also verifies outward winding and road clearance for both street
sides and all three roof styles. Three motion tests cover closed loops, ferry heading, trolley wheel clearance,
rotation-channel export and rejection of invalid rotation samples. The additional
detail camera is at (-5,34,1),
yaw -40, pitch -5 degrees.

The renderer exposes `sr_room_set_animation_time` for reproducible previews;
negative values restore real time. `ROOMTEST_TIME` selects a preview time, with
0 used for the comparison images and 20/40/60 for the checkpoint slider. The
slider displays still renders, not continuous playback.

The optional `sr_room_set_reflections` API and `ROOMTEST_REFLECTIONS=1` preview
setting enable screen-space reflections with a 120-metre ray limit. They can
reflect visible objects, but cannot recover off-screen geometry; shoreline
artifacts and full-resolution performance still need evaluation. New rooms and
the normal prototype preview leave this effect disabled. The GPU smoke check
compares default/disabled/enabled images and verifies a water change while the
sky stays stable:

```sh
python3 test/city/reflections-render-test.py --world /tmp/wallpaper-city
```

The renderer now exposes `sr_room_set_fog`; new rooms keep fog disabled. The
preview opts in using `ROOMTEST_FOG=density,start,height,falloff,opacity,r,g,b`.
The installed renderer and running desktop have not been updated. Rebuild the
local preview tool after pulling this change with `build/build-room.sh --test`.
The GPU regression check is:

```sh
python3 test/city/fog-render-test.py --world /tmp/wallpaper-city
```

It compares fog disabled/default/enabled, checking that distant terrain changes
while selected sky and foreground regions remain unchanged. These are smoke
checks at the reference camera with normal effects enabled, not a complete
performance or all-camera test. The additional waterfront camera is (90,16,-107),
yaw -64 and pitch 7 degrees. Export validation covers buffer bounds, unit normals, outward winding and
closed actor tracks. The denser background increases geometry and still needs
performance acceptance before desktop integration.

This is still not a close visual match. Remaining work before integration:

- Match the individual foreground houses more closely, including proportions
  and ornament; extend the detailed architecture into the waterfront.
- Less repetitive trees and buildings; better correspondence to specific houses.
- Refine the waterfront's depth and shore silhouettes.
- Improve water reflections and sky resolution; refine haze across more views.
- Review full continuous motion and collision along longer walking routes.
- Establish walking/collision and app placement, then measure frame performance.

Generated GLB and preview files remain in the output directory while the
composition evolves. Source assets and the deterministic generator are committed.
This study has not passed desktop integration or release performance gates.

### Interactive pedestrian preview

`build/tools/wallpaper-preview.py --world /home/starling/tmp/wallpaper-city-v2`
serves a local preview at `http://127.0.0.1:8766`. Build the renderer first with
`build/build-room.sh --test`. Requires Python with NumPy and Pillow (also used
by the world generator), plus the existing EGL/GBM renderer dependencies.

WASD walks, Shift increases speed, arrows or dragging the picture change the
view, and Home returns to the hillside. Follow the right sidewalk downhill,
shift left into the shop passage, climb the steps, then turn right along the
terminal promenade. The camera follows the terrain and eases stair risers.
Movement is confined to a conservative pedestrian corridor with lamp clearance;
this is not general mesh collision or full-city navigation. Side streets,
buildings, piers and water remain outside the route.

The browser sends input to one local Python controller. A persistent Filament
process accepts camera/time CSV rows through `ROOMTEST_STREAM` on stdin and
returns one upright RGB frame per row through its output path; the controller
encodes JPEG for the browser. It uses the prototype's existing scene and lighting.
This single-viewer tool does not install a world or change the desktop. It is a
navigation review tool, not the final desktop input or rendering pipeline.

Checks: `test/city/wallpaper-navigation-test.py` exercises the full route,
water/building/lamp exclusion and delayed input. `test/city/camera-path-render-test.py
--world DIR` compares streamed frames with the deterministic camera-path output.

The generator now exports `navigation.json`: versioned walkable rectangles,
circular lamp exclusions, pavement surface rectangles, and an initial camera.
Street geometry and navigation share the same strip coordinates. Waterfront
heights come directly from the quay generator's stone, sidewalk and limestone
boxes, including stair treads and the quay lip. The hillside corridor stays on
the sidewalk, then widens at its foot to allow the turn into the shop passage.

The preview reads this file when present. The desktop's `WorldNavigation` reads
the same sidecar for worlds with `world.json`, applies the exported spawn on
Home, follows its pavement heights and sweeps keyboard movement against its
bounds. Worlds without the sidecar retain their existing behavior. An opt-in desktop profile can now export the world manifest; see the preparation
command below. A live desktop integration review remains necessary before
promoting this prototype to the installed desktop.

`python3 test/city/navigation-parity-test.py` compiles the standalone Swift
navigation code and compares 1,350 swept moves and resulting floor heights with
Python. The pedestrian test also checks the full route, all street-strip
midpoints, and 441 samples across the actual quay stairs and exit.

### Workspace placement audit

`build/tools/wallpaper-workspace.py --world DIR --out AUDIT` renders four labeled
application fixtures with the same Filament pane API used by desktop windows.
`ROOMTEST_PANES` accepts a CSV of x, y, z, yaw degrees, width, height, focus, and
P6 texture path. It preserves the supplied camera and supports up to 16 panes.
Fixture textures are visibly labeled; these are not captures of running apps.

The sidewalk spawn hid the right-hand rail and switcher pane behind the nearest
tree. The initial workspace is now at (0, 1) in the clear center of the upper
street, facing downhill with a five-degree downward pitch. A short cross-street
walking area connects it to the existing right-side sidewalk. The proposed rail
is 17 m ahead and 2 m above eye height, clearing the foreground trolley as well
as the trees. The audit uses the existing desktop switcher radius/spacing and
records the proposed rail configuration in `placement.json`; this is still a
study. The separate desktop-profile tool exports an opt-in manifest using this layout.

`test/city/workspace-clearance-test.py --world DIR --audit AUDIT` compares every
rail pane's interior with a control rendered without city geometry. All four
panes fit inside the viewport, with under 0.1% of interior pixels differing by
more than 12/255 at the audited initial actor time. This is a fixed-view smoke
check, not a guarantee for all actor positions or camera movement. The expanded
navigation route passes 1,500 Python/Swift movement comparisons and includes a
walking test from the new workspace to the sidewalk.


### Opt-in desktop profile

Prepare a separate profile after generating the scene:

```sh
python3 build/tools/wallpaper-desktop.py \
  --source /home/starling/tmp/wallpaper-city-v2 \
  --out /home/starling/tmp/wallpaper-desktop
```

The profile links the generated GLB, sky, IBL and frame texture, and writes
`world.json` and `navigation.json`. It includes the reviewed app rail, sunset
exposure and sunlight, distance fog, ambient actor animation, and a fallback
height map for window placement. Rerun preparation after changing the generated
scene or navigation. This command does not install files or restart the desktop.

For a development desktop launch, set `STARLING_ROOM_DIR` to the profile and
`STARLING_ROOM_LIB` to this checkout's `.build-shared/libstarling_room.so`, and
use the newly built shell. The older installed shell does not understand this
navigation profile or its fog. The existing desktop world remains the default.

In navigation-enabled worlds, newly opened apps appear at reading distance.
Selecting a distant app brings it to the current viewer rather than gliding the
camera off the corridor. The existing switcher selection path is preserved.
These changes are conditional on a valid navigation sidecar, so older worlds
keep their previous app-placement behavior.

`python3 test/city/desktop-profile-test.py` compiles the actual `World3D` parser
with the navigation type, checks the profile's rail, camera ground, lighting and
fog, rejects malformed fog, and checks legacy height-map indexing. This covers
configuration loading; it is not a live multi-app or multi-display acceptance test.


### Live hardware smoke test — 2026-09-20

The feature shell and renderer are now installed on the development laptop,
with `/home/starling/tmp/wallpaper-desktop` selected by the session launcher.
The previous binaries and launcher are preserved under
`/home/starling/tmp/wallpaper-host-rollback-20260920`; `sudo ./restore.sh` from
that directory restores them and restarts GDM.

Confirmed on the actual AMD desktop with both displays: the generated world
loads, Chrome/Files/Terminal/Video Player open, Alt+Tab displays their live
textures, terminal input executes, and the 100-second walkthrough plays inside
the video app. Broker snapshots confirm four real app panes. Moving each
camera independently leaves the other camera unchanged; both returned home.
Evidence is under `~/Pictures/Starling/wallpaper-host-*.png` and
`wallpaper-host-check.json`.

The live run exposed clipped title bars when opening full-size apps from the
five-degree downhill view. Navigation-enabled worlds now level the camera when
bringing an app to reading distance. Position and yaw are retained. This was
rebuilt and verified on the running desktop. The screenshot harness also now
detects a replaced screenshot filename after a shell restart.

Remaining findings: a transient large black rectangle appeared after the
cross-display camera/switcher exercise and cleared during subsequent app
interaction; its cause is not yet isolated. This smoke test is not performance
or release acceptance. The earlier 3 GB test VM was OOM-killed when returning
to 3D with four apps, so low-memory behavior still needs investigation. The VM
is stopped; live validation moved to hardware at the user's request.


### Rendering artifact investigation — 2026-09-20

Reproduced on the real desktop after a fresh session, with zero app panes.
Moving the pointer off an app brings back the rectangle; app interaction can
clear it. It also reproduces with `workspaceRail` temporarily empty, excluding
rail previews and the exit control. The profile was restored afterward.
A temporary Filament RenderTarget readback contained the same rectangle as
the final desktop capture. Thus this is not just a Flutter window overlay.
The temporary capture code was removed and the normal renderer reinstalled.

A standalone native test rendered two scenes alternately at 3840x2160 and
2560x1600 using the same shared engine, without the rectangle. This narrows
the next investigation to live integration, but does not yet identify a root
cause or prove that multi-output rendering is fault-free.

Evidence: `~/Pictures/Starling/black-restarted.png`,
`black-no-controls2.png`, and `~/tmp/scene-only.png` (the temporary readback
image is vertically inverted); the standalone comparison is
`~/tmp/dual-scene.png`, with its temporary harness `~/tmp/room-dual-test.cpp`.

The host screenshot helper now selects numbered primary-output captures.
Previously it could select `/tmp/drm_screenshot_eDP-1.ppm` when the secondary
finished first, making apparently clear captures misleading. Verified the
selection against live captures and checked Python compilation. The black
rectangle remains unresolved; no rendering fix is claimed.


### Blender source scene — 2026-09-20

At the user's request, modelling now has a native Blender source study in
`design/blender/wallpaper-city.blend`, with a camera render alongside it.
The scene was built in Blender from separate editable meshes, not imported
from the earlier generated GLB. It includes a packed wallpaper camera overlay,
terraced houses with bay-window components, street paving/rails, the cable car,
waterfront/clock tower, a continuous island and hills, suspension bridge and ferry.
`build/tools/blender-wallpaper-city.py` reproduces the initial study.

This remains a composition study: the architecture, vegetation and reference
alignment need further work. Cycles lighting, procedural surfaces and the bay
volume are Blender features that need baking or matching for the runtime.
The study has not replaced the installed world or its navigation. The separate
live renderer black-rectangle issue remains open.
