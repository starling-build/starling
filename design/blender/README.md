# Wallpaper city — Blender study

Open `wallpaper-city.blend` in Blender 5.2 or later. The scene contains native,
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
/snap/bin/blender --factory-startup -b --threads 8 --python build/tools/blender-wallpaper-city.py -- \
  --out "$PWD/design/blender" --samples 64 --width 1400
```

The reproducible builder seeds the study. Further modelling can happen directly
in Blender; rebuilding overwrites the saved `.blend`, so save manual variants
under a new filename first.

The preview uses Blender 5.2.2 LTS with OpenImageDenoise. On this development
machine `/snap/bin/blender` provides that build; `/usr/bin/blender` 5.0 has no
usable Cycles denoiser. The builder explicitly selects OpenImageDenoise.

The second pass adds deep street-facing bays, entry stairs and planters,
stepped foliage, a larger fully framed cable car, and a lower-street connection.
Palette swatches are converted from sRGB to scene-linear shader colors. The
sunlight direction matches the visible sun, and distant houses follow the
hillside height rather than floating in a line above it.

Validation reopens the saved project with Blender 5.2 and checks its packed
reference/environment images, finite mesh coordinates, active denoiser, and
that all cable-car geometry fits within the comparison camera. Procedural
materials, atmospheric volume and lighting still need runtime counterparts.

The waterfront pass adds clock-face markers, belfry recesses and a pyramidal
roof, stone quay coping and moorings, and a ferry in the open bay with a tapered
bow, deck railings, funnel and broken wake. Stepped woodland follows the terrain
surface on the island and both headlands; rocks articulate the island shoreline.
These are editable study meshes. The ferry and wake are static in this source.

The architecture and sunset pass varies window brightness, adds siding and bay
apron panels, and mixes hipped roofs with roof railings. A broad warm area light
above the distant bay and two scales of water bump are Blender lighting studies;
the reflection depends on camera position and is not painted into a texture.

The landmark pass gives the ferry terminal two rows of arched glazing,
pilasters, floor cornices and a parapet. The cable car now has curved main and
clerestory roofs, window mullions, inset lower panels, wheels, running boards,
platform rails and mesh destination lettering. These details are native meshes;
the roof thickness uses editable Solidify modifiers.
The complete cable-car assembly is pitched to the street's local slope; it is
no longer a level vehicle intersecting the rising front of the road.
