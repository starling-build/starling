# Wallpaper city — Blender study

Open `wallpaper-city.blend` in Blender 5.0 or later. The scene contains native,
editable mesh components grouped by street, Victorian houses, trees, waterfront,
cable car, landscape, bridge, and ferry. Units are metres; Z is up and +Y runs
downhill. This is a new composition study, not an import of the previous city.

The active camera includes the original wallpaper as a packed background image
at 35% opacity for alignment in the viewport. It does not appear in rendered
images. The sunset environment image is also packed, so the Blender file can
be opened without external image paths.

`camera-study.png` is the Cycles render. The scene is an early composition and
material study: architecture, landscape detail, exact reference alignment, and
runtime lighting still need refinement. The live desktop world is unchanged.
Blender's procedural water bump and lighting need baking or equivalent engine
settings before this can become a replacement desktop world. A `.blend` file
is the source; it cannot be loaded directly by the desktop renderer.

Recreate the initial editable asset and render from the repository root:

```sh
blender --factory-startup -b --threads 8 --python build/tools/blender-wallpaper-city.py -- \
  --out "$PWD/design/blender" --samples 64 --width 1200
```

The reproducible builder seeds the study. Further modelling can happen directly
in Blender; rebuilding overwrites the saved `.blend`, so save manual variants
under a new filename first.

Validation: reopened the saved file in a fresh Blender process; confirmed the
comparison camera, 849 objects, 80,655 base mesh vertices, Cycles rendering,
and two packed reference/environment images. Blender lighting, procedural
materials, and the atmospheric volume have not been matched in the runtime.
