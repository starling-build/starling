# Waterfront material study

Branch: `feature/city-materials`. These original albedo assets were made with
the built-in image generation tool. The source PNGs are committed here and
embedded in `../room.glb` by `build/tools/city-materials.py`; generation is not
needed to rebuild the world. No downloaded photographic textures are used.

The material pass replaces stretched pixel tiles on painted walls, limestone
trim, foundations and sidewalks. A new limestone terrace distinguishes the
overlook from the asphalt street. Textures repeat every two world metres with
linear magnification and trilinear mipmapping. Paint colors use glTF linear
base-color factors; bronze, patinated copper and glass have separate roughness
and metallic settings. Images contain surface detail only, not scene shadows.
These are albedo-only materials, not scanned PBR sets or normal maps.

Window sills and inner jambs have extra geometry. Sun/ambient intensities are
10000/16000 lux to give the existing shadow pass more contrast. The blue bay,
actors, navigation, app placement and independent display cameras are retained.
Trees, clouds, distant buildings and silhouettes remain intentionally blocky;
this first pass does not claim to reconstruct the wallpaper.

## Generation prompts

`lime-plaster.png`:

> Use case: photorealistic-natural. Asset type: seamless tileable base-color
> texture for a real-time 3D waterfront city, square 1024x1024. Primary request:
> warm ivory painted lime plaster, subtle fine mineral grain, delicate irregular
> trowel variation and tiny pores, well-maintained historic coastal architecture.
> Straight-on orthographic full-frame material surface only. Uniform diffuse
> neutral illumination, no shadows, no highlights, no ambient occlusion, no
> vignette, no perspective. Nearly uniform warm off-white color so it can be
> tinted sage, rose and cream in a PBR material. Sophisticated understated
> surface, low contrast, no large cracks, no peeling, no objects, no text, no
> borders. Must tile seamlessly on all four edges. This is the actual albedo
> texture, not a material preview sphere or scene.

`limestone.png`:

> Use case: photorealistic-natural. Asset type: seamless tileable square albedo
> texture for PBR stone in a real-time historic waterfront city. Create a
> full-frame straight-on orthographic scan-like surface of warm pale grey
> limestone, finely honed but gently weathered, subtle mineral flecks, faint
> natural veins and tiny pores. One continuous stone surface, NOT a grid of tiles
> or bricks: geometry supplies joints. Low contrast, sophisticated restrained
> tactile detail. Flat uniform diffuse lighting with no directional shadows, no
> highlights, no vignette or ambient occlusion. Seamless all edges. No text, no
> borders, no objects, no perspective, no preview sphere. Useful as both
> architectural limestone trim and broad pavement slabs, should read as natural
> stone rather than pixel noise.

The tool returned 1254×1254 PNGs. They are preserved at their original resolution.

## Rebuild and checks

Run `python3 build/tools/voxel-world.py --no-sky`, then
`python3 test/city/motion-test.py`. In addition to animation and navigation
checks, the suite verifies that splitting the city into materials preserves
every triangle exactly once and that architecture UVs retain physical scale.
Review a GPU render from the home viewpoint and a close facade viewpoint;
automated geometry checks cannot establish visual quality.
