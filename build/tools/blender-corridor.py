#!/usr/bin/env python3
"""Sci-fi modular corridor kit, built in Blender as editable native meshes.

Run from the repo root:
  /snap/bin/blender --factory-startup -b --python build/tools/blender-corridor.py -- --out design/blender/corridor

Kit parts (one mesh each, instanced as linked duplicates): floor, ceiling,
wall panel, wall with window, separator rib, handrail, ceiling fan, door frame
and two door leaves. Units are metres, Z up, the corridor runs along +Y and a
module is MOD_L deep. The assembly is `Corridor • assembly`; every part also
sits once in `Kit • parts` (render-hidden) for inspection and export.
"""
import bpy, math, argparse, sys
from pathlib import Path
from mathutils import Vector, Matrix, Euler

p = argparse.ArgumentParser()
p.add_argument('--out', type=Path, required=True)
p.add_argument('--modules', type=int, default=5)
p.add_argument('--samples', type=int, default=64)
p.add_argument('--width', type=int, default=1400)
p.add_argument('--no-render', action='store_true')
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
a.out.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------- dimensions
MOD_L = 2.0     # module depth along Y
W = 3.2         # interior width at the floor
H = 3.0         # interior height at the ceiling
CH = 0.6        # chamfer run: wall stops at H-CH and slopes in CH to the ceiling
SKIN = 0.12     # panel thickness
DOOR_W, DOOR_H = 1.6, 2.4

# ---------------------------------------------------------------- scene reset
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections): bpy.data.collections.remove(c)
for block in (bpy.data.meshes, bpy.data.materials, bpy.data.lights, bpy.data.cameras):
    for d in list(block): block.remove(d)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'; scene.unit_settings.scale_length = 1
collections = {}
def group(name):
    if name not in collections:
        c = bpy.data.collections.new(name); scene.collection.children.link(c); collections[name] = c
    return collections[name]

# ---------------------------------------------------------------- materials
def srgb(c): return tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in c)
def material(name, color, rough=.5, metal=0.0, emission=0.0, emit_color=None):
    m = bpy.data.materials.new(name); m.use_nodes = True; m.diffuse_color = (*srgb(color), 1)
    s = m.node_tree.nodes['Principled BSDF']
    s.inputs['Base Color'].default_value = (*srgb(color), 1)
    s.inputs['Roughness'].default_value = rough; s.inputs['Metallic'].default_value = metal
    if emission:
        s.inputs['Emission Color'].default_value = (*(emit_color or color), 1)
        s.inputs['Emission Strength'].default_value = emission
    return m
PANEL   = material('Painted panel • off-white', (.80, .82, .83), .42, .15)
PANEL2  = material('Painted panel • warm grey', (.58, .60, .61), .48, .15)
GUN     = material('Gunmetal frame', (.13, .14, .16), .38, .85)
DARK    = material('Rubber trim', (.035, .035, .04), .75, 0)
GRATE   = material('Floor grating', (.10, .105, .11), .55, .8)
DECK    = material('Deck plate', (.30, .31, .33), .5, .6)
CYAN    = material('Light strip • cyan', (.35, .85, 1.0), .2, 0, emission=14)
WARM    = material('Light strip • warm white', (1.0, .93, .82), .2, 0, emission=10)
ORANGE  = material('Indicator • orange', (1.0, .45, .10), .3, 0, emission=6)
GREEN   = material('Indicator • green', (.25, 1.0, .35), .3, 0, emission=8)
HAZARD  = material('Hazard yellow', (.95, .66, .08), .5, 0)
GLASS   = material('Viewport glass', (.02, .04, .08), .05, 0, emission=.6, emit_color=(.02, .05, .12))
STAR    = material('Starfield backdrop', (0, 0, 0), .5, 0, emission=1, emit_color=(.004, .006, .012))
_n, _l = STAR.node_tree.nodes, STAR.node_tree.links
_co = _n.new('ShaderNodeTexCoord'); _vo = _n.new('ShaderNodeTexVoronoi'); _vo.inputs['Scale'].default_value = 90
_lt = _n.new('ShaderNodeMath'); _lt.operation = 'LESS_THAN'; _lt.inputs[1].default_value = .045
_mul = _n.new('ShaderNodeMath'); _mul.operation = 'MULTIPLY'; _mul.inputs[1].default_value = 6
_add = _n.new('ShaderNodeMath'); _add.operation = 'ADD'; _add.inputs[1].default_value = .35
_l.new(_co.outputs['Object'], _vo.inputs['Vector']); _l.new(_vo.outputs['Distance'], _lt.inputs[0])
_l.new(_lt.outputs[0], _mul.inputs[0]); _l.new(_mul.outputs[0], _add.inputs[0])
_l.new(_add.outputs[0], _n['Principled BSDF'].inputs['Emission Strength'])
_n['Principled BSDF'].inputs['Emission Color'].default_value = (.7, .8, 1, 1)

# ---------------------------------------------------------------- mesh batching
class Batch:
    """Accumulates boxes/prisms into one mesh with per-face materials."""
    def __init__(self, name): self.name = name; self.v = []; self.f = []; self.mi = []; self.m = []
    def box(self, c, s, m, rot=(0, 0, 0)):
        R = Euler(rot).to_matrix(); n = len(self.v); u, v, w = [q / 2 for q in s]
        for dx, dy, dz in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:
            self.v.append(tuple(Vector(c) + R @ Vector((dx*u, dy*v, dz*w))))
        self.f += [tuple(n+i for i in f) for f in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]]
        if m not in self.m: self.m.append(m)
        self.mi += [self.m.index(m)] * 6
    def cyl(self, c, r, depth, m, axis='Y', n=16):
        b = len(self.v); ring = []
        for i in range(n):
            t = 2*math.pi*i/n; ring.append((r*math.cos(t), r*math.sin(t)))
        for h in (-depth/2, depth/2):
            for x, y in ring:
                local = {'Y': (x, h, y), 'Z': (x, y, h), 'X': (h, x, y)}[axis]
                self.v.append(tuple(Vector(c) + Vector(local)))
        for i in range(n):
            j = (i+1) % n; self.f.append((b+i, b+j, b+n+j, b+n+i))
        self.f.append(tuple(b+i for i in range(n))); self.f.append(tuple(b+n+i for i in reversed(range(n))))
        if m not in self.m: self.m.append(m)
        self.mi += [self.m.index(m)] * (n+2)
    def finish(self, bevel=.006):
        mesh = bpy.data.meshes.new(self.name); mesh.from_pydata(self.v, [], self.f); mesh.update()
        for m in self.m: mesh.materials.append(m)
        for poly, i in zip(mesh.polygons, self.mi): poly.material_index = i
        mesh['bevel'] = bevel
        return mesh

def place(mesh, name, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), coll='Corridor • assembly'):
    o = bpy.data.objects.new(name, mesh); group(coll).objects.link(o)
    o.location = loc; o.rotation_euler = rot; o.scale = scale
    if mesh.get('bevel'):
        mod = o.modifiers.new('Edge highlight', 'BEVEL'); mod.width = mesh['bevel']; mod.segments = 2; mod.limit_method = 'ANGLE'
    return o

# ---------------------------------------------------------------- kit parts
# Every part is modelled for the LEFT side / in module-local space: x across,
# y from 0 to MOD_L, z up from the walking surface.
def part_floor():
    b = Batch('Kit • Floor')
    b.box((0, MOD_L/2, -.10), (W + 2*SKIN, MOD_L, .10), GUN)              # base slab
    b.box((0, MOD_L/2, -.02), (1.9, MOD_L - .04, .06), DECK)              # central walkway
    for s in (-1, 1):                                                       # side grating channels
        b.box((s*1.30, MOD_L/2, -.045), (.70, MOD_L - .04, .02), DARK)
        for i in range(9):
            b.box((s*1.30, .11 + i*(MOD_L-.22)/8, -.035), (.66, .05, .02), GRATE)
        b.box((s*0.975, MOD_L/2, -.005), (.05, MOD_L - .04, .04), GUN)     # walkway kerb
    for i in range(4):                                                      # tread grooves
        b.box((0, .25 + i*.5, .012), (1.6, .03, .01), DARK)
    return b.finish()

def part_wall(window=False):
    b = Batch('Kit • Wall with window' if window else 'Kit • Wall panel')
    x0 = -W/2 - SKIN/2                                                      # skin centre line
    zt = H - CH                                                             # top of the vertical wall
    if not window:
        b.box((x0, MOD_L/2, zt/2), (SKIN, MOD_L, zt), PANEL)
        b.box((x0 + SKIN/2 + .02, MOD_L/2, 1.45), (.04, MOD_L - .30, .75), PANEL2)   # inset upper panel
        b.box((x0 + SKIN/2 + .015, MOD_L/2, .60), (.03, MOD_L - .30, .30), PANEL2)   # inset lower panel
    else:
        wz0, wz1, wy0, wy1 = .95, 1.95, .35, MOD_L - .35
        b.box((x0, MOD_L/2, wz0/2), (SKIN, MOD_L, wz0), PANEL)
        b.box((x0, MOD_L/2, (wz1+zt)/2), (SKIN, MOD_L, zt - wz1), PANEL)
        b.box((x0, wy0/2, (wz0+wz1)/2), (SKIN, wy0, wz1 - wz0), PANEL)
        b.box((x0, (wy1+MOD_L)/2, (wz0+wz1)/2), (SKIN, MOD_L - wy1, wz1 - wz0), PANEL)
        b.box((x0 + .03, MOD_L/2, (wz0+wz1)/2), (.06, wy1 - wy0 + .12, wz1 - wz0 + .12), GUN)   # frame
        b.box((x0 + .03, MOD_L/2, (wz0+wz1)/2), (.02, wy1 - wy0, wz1 - wz0), GLASS)
        b.box((x0 - .6, MOD_L/2, (wz0+wz1)/2), (.02, wy1 - wy0 + 2, wz1 - wz0 + 2), STAR)     # backdrop
    b.box((x0 + SKIN/2 + .03, MOD_L/2, .18), (.06, MOD_L, .26), DARK)     # kick plate
    b.box((x0 + SKIN/2 + .025, MOD_L/2, 1.02), (.05, MOD_L, .05), GUN)    # strip housing
    b.box((x0 + SKIN/2 + .05, MOD_L/2, 1.02), (.01, MOD_L - .06, .025), CYAN)
    # chamfer panel from (−W/2, zt) up to (−W/2+CH, H)
    cx, cz = -W/2 + CH/2, zt + CH/2; run = math.hypot(CH, CH)
    b.box((cx - SKIN/2*math.cos(math.pi/4), MOD_L/2, cz + SKIN/2*math.sin(math.pi/4)), (run, MOD_L, SKIN), PANEL, rot=(0, -math.radians(45), 0))
    b.box((cx + .02, MOD_L/2, cz - .02), (run - .3, MOD_L - .30, .03), PANEL2, rot=(0, -math.radians(45), 0))
    return b.finish()

def part_ceiling():
    b = Batch('Kit • Ceiling'); cw = W - 2*CH
    b.box((0, MOD_L/2, H + SKIN/2), (cw + .05, MOD_L, SKIN), PANEL)
    b.box((0, MOD_L/2, H - .02), (.9, MOD_L - .25, .05), GUN)             # light trough
    for s in (-1, 1):
        b.box((s*.36, MOD_L/2, H - .045), (.10, MOD_L - .30, .012), WARM)
        b.cyl((s*(cw/2 - .18), MOD_L/2, H - .16), .055, MOD_L, GUN)        # corner conduits
        b.cyl((s*(cw/2 - .32), MOD_L/2, H - .10), .03, MOD_L, DARK)
    b.box((0, MOD_L/2, H - .03), (.5, MOD_L - .3, .02), PANEL2)
    return b.finish()

def part_separator():
    """The rib at a module joint: an octagonal frame following the section,
    standing PROUD metres inside the finished surfaces all the way round."""
    b = Batch('Kit • Separator rib'); d, t, PROUD = .22, .16, .10
    zt = H - CH
    b.box((0, 0, -.16 + (t + .19)/2), (W + 2*SKIN + 2*t, d, t + .19), GUN)  # sill (top 0.03 above deck)
    for s in (-1, 1):
        x = s*(W/2 - PROUD + t/2)
        b.box((x, 0, zt/2 + .05), (t, d, zt + .1), GUN)                     # post, through the skin
        b.box((s*(W/2 - PROUD - .005), 0, 1.02), (.02, d - .06, .05), CYAN)
        b.box((s*(W/2 - PROUD - .005), 0, 2.0), (.02, d - .06, .05), CYAN)
        # chamfer beam: centre on the chamfer line, pushed in so it stands PROUD
        inward = Vector((s*-1, 0, -1)).normalized()
        c = Vector((s*(W/2 - CH/2), 0, zt + CH/2)) + inward*(PROUD - t/2)
        b.box(tuple(c), (math.hypot(CH, CH) + .28, d, t), GUN, rot=(0, s*math.radians(45), 0))
    b.box((0, 0, H - PROUD + t/2), (W - 2*CH + .5, d, t), GUN)                # lintel, 0.10 below the ceiling
    return b.finish()

def part_rail():
    b = Batch('Kit • Handrail'); x = -W/2 + .10
    b.cyl((x, MOD_L/2, .95), .028, MOD_L, GUN)
    for y in (.3, MOD_L - .3):
        b.box((x + .03 - .05, y, .95), (.10, .04, .04), DARK)
    return b.finish()

def part_fan():
    b = Batch('Kit • Ceiling fan'); z = H - .02
    b.cyl((0, MOD_L/2, z), .55, .10, GUN, axis='Z', n=32)                 # housing ring
    b.cyl((0, MOD_L/2, z + .06), .48, .01, ORANGE, axis='Z', n=32)         # backlight
    b.cyl((0, MOD_L/2, z - .02), .09, .12, DARK, axis='Z', n=16)           # hub
    for i in range(5):
        t = 2*math.pi*i/5
        b.box((.27*math.cos(t), MOD_L/2 + .27*math.sin(t), z - .01), (.36, .12, .015), GUN, rot=(math.radians(25), 0, t))
    for i in range(4):                                                      # grille bars
        t = math.pi*i/4
        b.box((0, MOD_L/2, z - .08), (1.0, .03, .02), DARK, rot=(0, 0, t))
    return b.finish()

def part_door_frame():
    """End wall with the door opening; y=0 is the wall plane."""
    b = Batch('Kit • Door frame'); zt = H - CH; t = .30
    for s in (-1, 1):                                                       # wall either side of the opening
        xa, xb = s*DOOR_W/2, s*(W/2 + SKIN)
        b.box(((xa+xb)/2, t/2, zt/2), (abs(xb-xa), t, zt), PANEL2)
    b.box((0, t/2, (DOOR_H + H + SKIN)/2), (W + 2*SKIN, t, H + SKIN - DOOR_H), PANEL2)   # header
    b.box((0, .05, DOOR_H + .12), (DOOR_W + .5, .12, .24), GUN)                            # door lintel
    for s in (-1, 1):
        b.box((s*(DOOR_W/2 + .12), .05, DOOR_H/2), (.24, .12, DOOR_H), GUN)                # jambs
        for k in range(6):                                                                 # hazard chevrons
            b.box((s*(DOOR_W/2 + .12), -.015, .25 + k*.4), (.16, .02, .12), HAZARD)
        b.box((s*(DOOR_W/2 + .55), -.01, 1.25), (.22, .02, .34), GUN)                      # control panel
        b.box((s*(DOOR_W/2 + .55), -.025, 1.32), (.14, .01, .08), GREEN if s > 0 else ORANGE)
    b.box((0, -.01, DOOR_H + .12), (.9, .02, .06), CYAN)                                   # sign light
    return b.finish()

def part_door_leaf():
    b = Batch('Kit • Door leaf'); w = DOOR_W/2 + .02
    b.box((-w/2, .10, DOOR_H/2), (w, .10, DOOR_H), PANEL)
    b.box((-w/2, .045, DOOR_H/2 + .25), (w - .18, .02, DOOR_H - .7), PANEL2)      # inset
    b.box((-w/2, .04, 1.05), (w, .02, .12), HAZARD); b.box((-w/2, .035, 1.05), (w, .02, .04), DARK)
    b.box((-.02, .10, DOOR_H/2), (.04, .11, DOOR_H), DARK)                        # meeting-edge seal
    return b.finish()

K = dict(floor=part_floor(), wall=part_wall(), window=part_wall(window=True), ceiling=part_ceiling(),
         rib=part_separator(), rail=part_rail(), fan=part_fan(), frame=part_door_frame(), leaf=part_door_leaf())

# ---------------------------------------------------------------- kit row (for inspection)
kit = group('Kit • parts'); kit.hide_render = True
for i, (k, mesh) in enumerate(K.items()):
    place(mesh, f'Kit {i+1:02d} • {k}', loc=(-40 + (i % 3)*5.5, -(i // 3)*5.5, 0), coll='Kit • parts')

# ---------------------------------------------------------------- assembly
N = a.modules
for i in range(N):
    y = i*MOD_L; tag = f'{i+1:02d}'
    place(K['floor'], f'Module {tag} • floor', (0, y, 0))
    place(K['ceiling'], f'Module {tag} • ceiling', (0, y, 0))
    left = K['window'] if i == 1 else K['wall']
    right = K['window'] if i == 2 else K['wall']
    place(left, f'Module {tag} • wall L', (0, y, 0))
    place(right, f'Module {tag} • wall R', (0, y, 0), scale=(-1, 1, 1))
    place(K['rib'], f'Joint {tag} • separator', (0, y, 0))
    if i in (0, 1, 4): place(K['rail'], f'Module {tag} • handrail L', (0, y, 0))
    if i == 1: place(K['fan'], f'Module {tag} • ceiling fan', (0, y, 0))
place(K['rib'], f'Joint {N+1:02d} • separator', (0, N*MOD_L, 0))
place(K['frame'], 'Door • frame', (0, N*MOD_L, 0))
OPEN = 0.0   # metres each leaf is slid into the wall; animate this for the door
place(K['leaf'], 'Door • leaf L', (-OPEN, N*MOD_L, 0))
place(K['leaf'], 'Door • leaf R', (OPEN, N*MOD_L, 0), scale=(-1, 1, 1))
# a short stub behind the camera so the near end is not open to the void
place(K['floor'], 'Module 00 • floor', (0, -MOD_L, 0)); place(K['ceiling'], 'Module 00 • ceiling', (0, -MOD_L, 0))
place(K['wall'], 'Module 00 • wall L', (0, -MOD_L, 0)); place(K['wall'], 'Module 00 • wall R', (0, -MOD_L, 0), scale=(-1, 1, 1))

# ---------------------------------------------------------------- lighting, cameras
def light(name, kind, loc, energy, color=(1, 1, 1), size=1, aim=None):
    d = bpy.data.lights.new(name, kind); d.energy = energy; d.color = color
    if kind == 'AREA': d.size = size
    o = bpy.data.objects.new(name, d); group('Lighting').objects.link(o); o.location = loc
    if aim: o.rotation_euler = (Vector(aim) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return o
for i in range(-1, N):
    light(f'Trough fill {i+1:02d}', 'AREA', (0, i*MOD_L + MOD_L/2, H - .06), 45, (1, .95, .87), 1.0, aim=(0, i*MOD_L + MOD_L/2, 0))
light('Door key', 'AREA', (0, N*MOD_L - .9, 2.4), 60, (.7, .9, 1), .8, aim=(0, N*MOD_L, 1.2))

def camera(name, loc, aim, lens):
    d = bpy.data.cameras.new(name); d.lens = lens; d.clip_end = 200
    o = bpy.data.objects.new(name, d); group('Lighting').objects.link(o); o.location = loc
    o.rotation_euler = (Vector(aim) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler(); return o
cam = camera('Corridor camera', (-.55, -.9, 1.55), (0.15, N*MOD_L, 1.35), 28)
kitcam = camera('Kit camera', (-34.5, -24, 14), (-34.5, -5, 1.0), 40)
kitsun = light('Kit sun', 'SUN', (-34, -15, 20), 3, (1, .97, .92), aim=(-30, -5, 0)); kitsun.hide_render = True
scene.camera = cam

world = bpy.data.worlds.new('Dark hull'); scene.world = world; world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (.002, .003, .005, 1)

# ---------------------------------------------------------------- render settings
scene.render.engine = 'CYCLES'; scene.cycles.samples = a.samples; scene.cycles.use_denoising = True
try: scene.cycles.denoiser = 'OPENIMAGEDENOISE'
except TypeError: pass
scene.cycles.max_bounces = 6
scene.render.resolution_x = a.width; scene.render.resolution_y = round(a.width * 9/16); scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'AgX'; scene.view_settings.look = 'AgX - Medium High Contrast'; scene.view_settings.exposure = .3
scene.render.image_settings.file_format = 'PNG'
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            area.spaces.active.region_3d.view_perspective = 'CAMERA'
            area.spaces.active.shading.type = 'RENDERED'      # opens rendering live through the camera
scene.cycles.preview_samples = 24; scene.cycles.use_preview_denoising = True
notes = bpy.data.texts.new('START HERE')
notes.write('Sci-fi modular corridor kit\nMetres, Z up, corridor along +Y, one module = 2 m.\n'
            'Kit • parts holds one of each part; the assembly is linked duplicates of those meshes,\n'
            'so editing a kit mesh updates every module. Door leaves slide along X (see OPEN in the builder).\n'
            'Rebuild: build/tools/blender-corridor.py\n')
bpy.ops.wm.save_as_mainfile(filepath=str(a.out / 'corridor.blend'))
if not a.no_render:
    scene.render.filepath = str(a.out / 'corridor-camera.png'); bpy.ops.render.render(write_still=True)
    scene.camera = kitcam; kit.hide_render = False; kitsun.hide_render = False
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.18, .19, .21, 1)
    for c in ('Corridor • assembly',): group(c).hide_render = True
    scene.render.filepath = str(a.out / 'corridor-kit.png'); bpy.ops.render.render(write_still=True)
    kit.hide_render = True; kitsun.hide_render = True; group('Corridor • assembly').hide_render = False; scene.camera = cam
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.002, .003, .005, 1)
print('CORRIDOR_COMPLETE', a.out, flush=True)
