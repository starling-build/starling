# Sci-fi modular corridor — Blender kit

A modular corridor kit in the spirit of the low-poly "Sci-Fi Modular Corridor
with Door" packs: wall panel, wall with window, floor, ceiling, separator rib,
handrail, ceiling fan, and a door in three parts (frame plus two sliding
leaves). Everything is native, editable mesh; units are metres, Z up, the
corridor runs along +Y and one module is 2 m deep.

Open `corridor.blend` in Blender 5.2 or later. `Kit • parts` holds one object
of each part (render-hidden); `Corridor • assembly` is built from linked
duplicates of those meshes, so editing a kit mesh updates every module. The
door leaves slide along X — move `Door • leaf L/R` apart to open them.

`corridor-camera.png` is the Cycles render down the corridor;
`corridor-kit.png` is the parts laid out.

Rebuild the asset and both renders from the repository root:

```sh
/snap/bin/blender --factory-startup -b --threads 16 --python build/tools/blender-corridor.py -- \
  --out design/blender/corridor --samples 64 --width 1400
```

`--modules N` sets the corridor length, `--no-render` just writes the .blend.
Rebuilding overwrites the saved `.blend`; save manual edits under a new name.
