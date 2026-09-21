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

The composition pass reduces the distant bridge and hillside silhouettes,
places the island farther into the bay, lowers the eastern houses, and moves
the ferry into the exposed water. The comparison camera stays fixed so the
landmark changes can be compared directly with the earlier renders.

The atmosphere pass adds twelve editable volumetric cloud banks in the
`10 • Volumetric clouds` collection. Their density comes from a seeded billow
pattern and a soft boundary mask; boxes display as wireframes while editing.
Use Cycles rendering to see the clouds. Four volume bounces and a warm cloud
fill light are used in the preview. Camera and reflection rays see a sunset
gradient; the packed environment supplies diffuse illumination. The bay haze
is warmer and slightly denser. These volume shaders need a separate runtime
representation or baking before export to the desktop world.

The framing pass brings the study closer to the reference wallpaper: a
larger sun disc sits just above the eastern ridge with a warmer orange
horizon gradient, two tall voxel trees frame the near corners of the view,
a small tripod radio mast stands on the Marin ridge shoulder, the ridge
carries denser lit houses, and a low fog bank hugs the far shore under the
bridge (`Shoreline fog bank`, a wire-display volume box). Lanterns glow
brighter, and the cable car and bridge are redder. The street-detail pass
(`build/tools/blender-street-detail.py`) adds coursed retaining walls,
planted sidewalk beds and worn, damp cobbles, and is applied by the builder.

The sky-and-corners pass thickens the cumulus into two layers lit by a warm
fill and an orange under-light from the sun side, adds an azimuthal sun glow
to the visible sky gradient behind a saturated sun disc, lightens and polishes the bay water so it mirrors the sunset, and
replaces the nearest house row with stepped stone garden terraces (three
tiers with planted tops and cubic shrubs) so the bottom corners of the frame
read like the reference. The comparison camera is unchanged.

The saturation pass deepens the horizon gradient stops, thins and warms the
bay haze so it no longer greys the horizon, gives the cumulus a warm scatter
colour plus a little absorption for purple-grey shadow sides under a stronger
orange under-light, carpets the Marin ridge with 1500 small lit houses, and
lifts exposure slightly. AgX Punchy was tried and rejected: it muddied the
street; the study stays on Medium High Contrast.

The ferry-and-stacks pass gives the ferry a dusk-lit white superstructure,
amber windows all round and a brighter wake, and adds six large sculpted
cumulus stacks nearer the camera. Clouds must sit between roughly 90 and
170 m at 700–1000 m out to be inside the comparison camera's frame; the
first attempt put them above the top edge.

The bridge-and-trees pass thickens the bridge's tower legs, braces, main
cables and hangers, adds portal braces, deck railings and a row of warm deck
lamps, and gives the vermilion a faint self-light so the haze no longer
washes it pink. Tree canopies gain three more lobes, a flattened ellipsoid
test and chunkier cubes for the rounder stepped look of the reference.

The facade-and-lamps pass adds bracketed window hoods with pediment blocks
on the street-facing bays, cornice brackets under the dentil course, a roof
balustrade and an entry stoop to every house; each lantern now carries a
warm point light so it pools on the cobbles rather than only glowing; and
the top of the sky gradient is a touch deeper.

The wet-street pass lowers the cobble roughness range in the street-detail
pass so lamps and sky reflect in the stones, scatters 700 lit houses over
the eastern headland (reshaped with it), and broadens the sun's shimmer on
the bay with slightly rougher water.
