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
Build roomtest with `build/build-room.sh --test` if it is not available.

Outputs include the GLB, sky/IBL, generated wave normal map, `view.png` and
`comparison.html`. Open the HTML locally to compare the wallpaper and actual GPU
render, side by side or stacked. `reference-camera.json` records the fixed camera
and light settings. The preview is 1672 × 941, at position (0,40,18), yaw 0 and
pitch 7.5 degrees. No desktop configuration is emitted: walking/collision,
workspace placement and multiple display integration remain unimplemented here.

## Current reconstruction

- Descending cobblestone street with a curved crest, rails, retaining walls,
  planting and street lamps.
- Stepped Victorian rows, projecting windows, cornices, stoops and smaller leaf
  voxels; more foreground detail than the first blockout.
- A red cable car with framed windows, roof tiers and round lamps, plus a ferry.
- Dedicated arched terminal facade, clock tower, island and right-offset bridge.
- Continuous shoreline surfaces tapering into water, with scattered distant windows.
- A generated sunset environment, a small analytic sun on the right, and
  reflective water with deterministic periodic wave normals.

The sky is a raster environment; all city geometry remains 3D. Source images and
exact generation/edit prompts are in
`../../shell/Resources/Worlds/wallpaper-city/materials/README.md`. The bake remaps
latitude to fit the reference camera, moves the source seam behind that view,
and uses warmer indirect light for the architecture. The image is not guaranteed
seamless over a complete 360-degree walk; that needs another environment pass.

## Validation and limits

Generation checks finite geometry, unit normals and valid indices. The focused
material-options test verifies embedded repeating normals, triangle preservation,
and isolation of prototype overrides from default exports. It also covers an
exporter edge case where every face is assigned a custom material. Nine existing
city tests pass against the shipped world. The prototype renders on the GPU. The final export also passed buffer-bound,
outward-winding, non-degenerate-triangle and closed-motion-track checks
(355,876 total triangles, including actors).

This is still not a close visual match. Remaining work before integration:

- More varied bay-window shapes, detailed doors, stairs and roofs.
- Less repetitive trees and buildings; better correspondence to specific houses.
- Refine the waterfront's depth and shore silhouettes.
- Improve water reflections, sky resolution and atmospheric haze.
- Refine actor contact with the curved slope and inspect animated motion.
- Establish walking/collision and app placement, then measure frame performance.

Generated GLB and preview files remain in the output directory while the
composition evolves. Source assets and the deterministic generator are committed.
This study has not passed desktop integration or release performance gates.
