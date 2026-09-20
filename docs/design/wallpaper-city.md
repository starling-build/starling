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
Build roomtest with `build/build-room.sh --test` if it is not available.

Outputs include the GLB, sky/IBL, generated wave normal map, `view.png`,
`architecture.png`, `waterfront.png`, three motion checkpoints and `comparison.html`. Open the HTML locally to compare the wallpaper and actual GPU
render, side by side or stacked. `reference-camera.json` records the fixed camera
and light settings. The preview is 1672 × 941, at position (0,40,18), yaw 0 and
pitch 7.5 degrees. No desktop configuration is emitted: walking/collision,
workspace placement and multiple display integration remain unimplemented here.

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
review, particularly the stretched clouds on the rear side of the angular warp.

## Validation and limits

Generation checks finite geometry, unit normals and valid indices. The focused
material-options test verifies embedded repeating normals, triangle preservation,
and isolation of prototype overrides from default exports. It also covers an
exporter edge case where every face is assigned a custom material. Nine existing
city tests pass against the shipped world. The prototype renders on the GPU. The final export also passed buffer-bound,
outward-winding, non-degenerate-triangle and closed-motion-track checks.
Two waterfront tests verify outward face winding and open basin/solid shore
samples. The facade test also verifies outward winding and road clearance for both street
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
