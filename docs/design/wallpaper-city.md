# Wallpaper city reconstruction

Branch: `feature/wallpaper-city`. Reference: `shell/Resources/Wallpapers/city-sunset.png`.

This is an independent geometry/composition study, not a replacement desktop world.
The installed city and its app placement are unchanged. The generator reuses the
existing GLB exporter and material library, with its own architecture, terrain,
landmarks, actor placement and street lights. Hidden surfaces are interpretations
of the single reference image.

## Reproduce

From the repository root, with Python, numpy, Pillow and the built roomtest:

```sh
python3 build/tools/wallpaper-city.py --out /tmp/wallpaper-city
ROOMTEST_SUN=0.65,0.23,0.72 \
ROOMTEST_SUN_COLOUR=1,0.69,0.38 \
ROOMTEST_SUN_LUX=12000 ROOMTEST_IBL_LUX=6500 \
ROOMTEST_EXPOSURE=8,0.0166667,100 \
.build-shared/roomtest \
  /tmp/wallpaper-city/room.glb \
  /tmp/wallpaper-city/room_ibl.ktx \
  /tmp/wallpaper-city/room_skybox.ktx \
  /tmp/wallpaper-city/view.ppm 1672 941 0 40 18 0 7.5
pnmtopng /tmp/wallpaper-city/view.ppm > /tmp/wallpaper-city/view.png
```

The fixed camera is recorded in `reference-camera.json`. Generation verifies finite
geometry, unit normals and index bounds. Existing city motion tests cover the shared
exporter's default behavior. No desktop configuration is emitted deliberately:
walking/collision, workspace placement and multiple display integration have not
been implemented for this layout.

## Current assessment

Reconstructed: enclosed descending cobblestone street, paired tracks, stepped
Victorian rows with projecting windows, stoops, planting and lamps, a dense
waterfront, long terminal and clock face, an island, right-offset suspension
bridge and inhabited headlands. Ferry and trolley have closed animation tracks.

This is a blockout, not a close visual match yet. Remaining work before integration:

- Match the street crest and trolley size/position; adjust the island's depth.
- Replace repetitive elevations with reference-specific bay windows, cornices,
  arched terminal openings and roof shapes.
- Rebuild the warm sky, clouds and atmospheric depth; the prototype currently
  borrows the old city's sky/IBL, with the sun outside the reference view.
- Add reflective water shading and a stronger sunset reflection.
- Improve distant terrain and foliage silhouettes, then measure performance.

The prototype has more geometry than the existing city. It has been rendered on
the GPU, but this is not a performance acceptance result or a release gate pass.
Generated GLB/previews remain in the output directory until the composition is
settled; the committed generator is deterministic.
