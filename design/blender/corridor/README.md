# Sci-fi modular corridor — Blender kit

A modular base kit in the mood of the Nostromo: dark, grimy, cold. Kit
parts: wall panel, wall with window, wall with a side door (closed, and an
ajar variant with a lit cabin behind it), floor, ceiling with duct and
conduits, separator rib, caged fluorescent tube (working, dying, dead),
handrail, ceiling fan, warning beacon, CRT wall terminal, a square junction
hub, and a bulkhead door in three parts (frame plus two sliding leaves).
Props: crate stack, drums, lockers, extinguisher, valve wheel, hanging
cables, floor stencil. Everything is native, editable mesh; units are metres,
Z up, the main run goes along +Y and one module is 2 m deep.

The assembly is a small base: a five-module main run with side doors, a
junction hub with a red emergency lamp, two-module branches east and west
ending in bulkhead doors, and the main bulkhead door beyond the hub with a
cold light beaming back through its gap. Corridor haze and a steam leak are
volume boxes in the `Atmosphere` collection.

Open `corridor.blend` in Blender 5.2 or later. `Kit • parts` holds one object
of each part (render-hidden); `Corridor • assembly` is built from linked
duplicates of those meshes, so editing a kit mesh updates every module. The
door leaves slide along X — move `Door • leaf L/R` apart to open them.

`corridor-camera.png` is the Cycles render down the main run,
`corridor-hub.png` looks from the hub down the east branch, and
`corridor-kit.png` is the parts laid out.

Rebuild the asset and both renders from the repository root:

```sh
/snap/bin/blender --factory-startup -b --threads 16 --python build/tools/blender-corridor.py -- \
  --out design/blender/corridor --samples 64 --width 1400
```

`--modules N` sets the corridor length, `--no-render` just writes the .blend.
Rebuilding overwrites the saved `.blend`; save manual edits under a new name.
