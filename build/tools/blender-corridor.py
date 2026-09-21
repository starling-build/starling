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
def material(name, color, rough=.5, metal=0.0, emission=0.0, emit_color=None, grime=None, wear=.5):
    """grime=(dirt colour, amount): a seeded noise mixes dirt into the base colour and
    roughens the surface, with vertical streaking; per-object variation via Object Info."""
    m = bpy.data.materials.new(name); m.use_nodes = True; m.diffuse_color = (*srgb(color), 1)
    n, l = m.node_tree.nodes, m.node_tree.links; s = n['Principled BSDF']
    s.inputs['Base Color'].default_value = (*srgb(color), 1)
    s.inputs['Roughness'].default_value = rough; s.inputs['Metallic'].default_value = metal
    if emission:
        s.inputs['Emission Color'].default_value = (*(emit_color or color), 1)
        s.inputs['Emission Strength'].default_value = emission
    if grime:
        dirt, amount = grime
        co = n.new('ShaderNodeTexCoord'); info = n.new('ShaderNodeObjectInfo')
        seed = n.new('ShaderNodeMath'); seed.operation = 'MULTIPLY'; seed.inputs[1].default_value = 37
        l.new(info.outputs['Random'], seed.inputs[0])
        streak = n.new('ShaderNodeMapping'); streak.inputs['Scale'].default_value = (1, 1, .22)   # stretch in Z
        l.new(co.outputs['Object'], streak.inputs['Vector'])
        big = n.new('ShaderNodeTexNoise'); big.noise_dimensions = '4D'; big.inputs['Scale'].default_value = 1.6
        big.inputs['Detail'].default_value = 8; big.inputs['Roughness'].default_value = .7
        l.new(streak.outputs[0], big.inputs['Vector']); l.new(seed.outputs[0], big.inputs['W'])
        fine = n.new('ShaderNodeTexNoise'); fine.noise_dimensions = '4D'; fine.inputs['Scale'].default_value = 14
        fine.inputs['Detail'].default_value = 4; l.new(co.outputs['Object'], fine.inputs['Vector']); l.new(seed.outputs[0], fine.inputs['W'])
        mixn = n.new('ShaderNodeMath'); mixn.operation = 'MULTIPLY_ADD'; mixn.inputs[1].default_value = .65; l.new(big.outputs['Fac'], mixn.inputs[0])
        fine_s = n.new('ShaderNodeMath'); fine_s.operation = 'MULTIPLY'; fine_s.inputs[1].default_value = .35
        l.new(fine.outputs['Fac'], fine_s.inputs[0]); l.new(fine_s.outputs[0], mixn.inputs[2])
        ramp = n.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].position = .42 - amount*.25; ramp.color_ramp.elements[1].position = .68
        l.new(mixn.outputs[0], ramp.inputs['Fac'])
        mix = n.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.inputs['A'].default_value = (*srgb(dirt), 1); mix.inputs['B'].default_value = (*srgb(color), 1)
        l.new(ramp.outputs['Color'], mix.inputs['Factor']); l.new(mix.outputs['Result'], s.inputs['Base Color'])
        rgh = n.new('ShaderNodeMapRange'); rgh.inputs['To Min'].default_value = min(1, rough + wear*.45); rgh.inputs['To Max'].default_value = rough
        l.new(ramp.outputs['Color'], rgh.inputs['Value']); l.new(rgh.outputs['Result'], s.inputs['Roughness'])
        bump = n.new('ShaderNodeBump'); bump.inputs['Strength'].default_value = .25; bump.inputs['Distance'].default_value = .02
        l.new(fine.outputs['Fac'], bump.inputs['Height']); l.new(bump.outputs['Normal'], s.inputs['Normal'])
    return m
DIRT = (.06, .065, .06)
PANEL   = material('Worn panel • bone',       (.52, .54, .50), .45, .30, grime=(DIRT, .55), wear=.6)
PANEL2  = material('Worn panel • grey-green', (.30, .33, .31), .5,  .30, grime=(DIRT, .6),  wear=.6)
GUN     = material('Cast iron frame',         (.075, .08, .085), .45, .9, grime=((.03, .03, .03), .5), wear=.4)
DARK    = material('Rubber trim',             (.03, .03, .032), .8, 0)
GRATE   = material('Wet floor grating',       (.07, .075, .08), .22, .85, grime=((.035, .04, .045), .5), wear=.7)
DECK    = material('Wet deck plate',          (.14, .15, .16), .25, .75, grime=((.05, .055, .06), .6), wear=.8)
PIPE    = material('Dull steel pipe',         (.22, .23, .24), .5, .9, grime=(DIRT, .6), wear=.5)
BRASS   = material('Tarnished brass',         (.45, .32, .14), .5, .9, grime=((.12, .08, .04), .7), wear=.5)
CYAN    = material('Indicator • cold blue',   (.55, .75, 1.0), .2, 0, emission=6)
COLD    = material('Fluorescent tube • on',   (.80, .90, 1.0), .2, 0, emission=40)
COLDDIM = material('Fluorescent tube • dying',(.80, .90, 1.0), .2, 0, emission=6)
COLDOFF = material('Fluorescent tube • dead', (.25, .27, .30), .3, 0)
ORANGE_DIM = material('Cage lamp • amber', (1.0, .55, .18), .3, 0, emission=2.5)
ORANGE  = material('Indicator • amber',       (1.0, .42, .08), .3, 0, emission=12)
RED     = material('Indicator • red',         (1.0, .12, .05), .3, 0, emission=10)
GREEN   = material('CRT phosphor green',      (.20, 1.0, .35), .3, 0, emission=3, emit_color=(.15, .9, .3))
HAZARD  = material('Hazard yellow • scuffed', (.72, .52, .07), .55, 0, grime=((.10, .08, .03), .75), wear=.6)
GLASS   = material('Viewport glass', (.02, .04, .08), .05, 0, emission=.6, emit_color=(.02, .05, .12))
STAR    = material('Starfield backdrop', (0, 0, 0), .5, 0, emission=1, emit_color=(.004, .006, .012))
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
    b.box((x0 + SKIN/2 + .03, MOD_L/2, .18), (.06, MOD_L, .26), GUN)      # kick plate
    for k in range(7):                                                      # vent grille on the lower inset
        b.box((x0 + SKIN/2 + .035, MOD_L/2, .50 + k*.035), (.02, .55, .012), DARK)
    for k, (dz, r, mat) in enumerate([(0, .045, PIPE), (.10, .045, PIPE), (.19, .03, BRASS), (.26, .02, DARK)]):
        b.cyl((x0 + SKIN/2 + .08 + r, MOD_L/2, .82 + dz), r, MOD_L, mat)  # cable/pipe bundle at hip height
    b.box((x0 + SKIN/2 + .10, MOD_L/2, .96), (.20, .06, .40), GUN)        # bundle clamp
    for k in range(3):                                                      # sparse amber lamps in cages
        yy = MOD_L/6 + k*MOD_L/3
        b.box((x0 + SKIN/2 + .03, yy, 1.42), (.06, .14, .07), GUN)
        b.box((x0 + SKIN/2 + .062, yy, 1.42), (.01, .10, .035), ORANGE_DIM)
        for dy in (-.045, 0, .045): b.box((x0 + SKIN/2 + .07, yy + dy, 1.42), (.006, .006, .06), DARK)
    # chamfer panel from (−W/2, zt) up to (−W/2+CH, H)
    cx, cz = -W/2 + CH/2, zt + CH/2; run = math.hypot(CH, CH)
    b.box((cx - SKIN/2*math.cos(math.pi/4), MOD_L/2, cz + SKIN/2*math.sin(math.pi/4)), (run, MOD_L, SKIN), PANEL, rot=(0, -math.radians(45), 0))
    b.box((cx + .02, MOD_L/2, cz - .02), (run - .3, MOD_L - .30, .03), PANEL2, rot=(0, -math.radians(45), 0))
    return b.finish()

def part_ceiling():
    b = Batch('Kit • Ceiling'); cw = W - 2*CH
    b.box((0, MOD_L/2, H + SKIN/2), (cw + .05, MOD_L, SKIN), PANEL2)
    b.box((0, MOD_L/2, H - .16), (.70, MOD_L, .30), GUN)                  # heavy central duct
    for k in range(4):                                                      # duct ribs
        b.box((0, .25 + k*.5, H - .16), (.74, .06, .34), DARK)
    for s in (-1, 1):
        b.cyl((s*(cw/2 - .16), MOD_L/2, H - .17), .07, MOD_L, PIPE)         # corner conduits
        b.cyl((s*(cw/2 - .34), MOD_L/2, H - .09), .035, MOD_L, DARK)
        b.cyl((s*(cw/2 - .42), MOD_L/2, H - .17), .025, MOD_L, BRASS)
    return b.finish()

def part_tube(mat):
    """A caged fluorescent fixture, hung under the ceiling beside the duct."""
    b = Batch('Kit • Tube fixture • ' + mat.name.split('• ')[-1]); z = H - .08; L = 1.3
    b.box((0, MOD_L/2, z + .03), (.16, L + .1, .04), GUN)                 # housing
    b.cyl((0, MOD_L/2, z - .02), .022, L, mat)                              # tube
    for k in range(5):                                                      # cage bars
        b.box((0, MOD_L/2 - L/2 + k*L/4, z - .02), (.14, .012, .09), DARK)
    for x in (-.065, .065): b.box((x, MOD_L/2, z - .02), (.008, L, .008), DARK)
    return b.finish()

def part_separator():
    """The rib at a module joint: an octagonal frame following the section,
    standing PROUD metres inside the finished surfaces all the way round."""
    b = Batch('Kit • Separator rib'); d, t, PROUD = .30, .22, .14
    zt = H - CH
    b.box((0, 0, -.16 + (t + .19)/2), (W + 2*SKIN + 2*t, d, t + .19), GUN)  # sill (top 0.03 above deck)
    for s in (-1, 1):
        x = s*(W/2 - PROUD + t/2)
        b.box((x, 0, zt/2 + .05), (t, d, zt + .1), GUN)                     # post, through the skin
        for z in (.45, 1.2, 1.95):                                          # bolt heads
            for dy in (-.09, .09): b.cyl((s*(W/2 - PROUD - .01), dy, z), .022, .03, GUN, axis='X', n=8)
        b.box((s*(W/2 - PROUD - .005), 0, 1.55), (.02, d - .10, .05), CYAN)
        # chamfer beam: centre on the chamfer line, pushed in so it stands PROUD
        inward = Vector((s*-1, 0, -1)).normalized()
        c = Vector((s*(W/2 - CH/2), 0, zt + CH/2)) + inward*(PROUD - t/2)
        b.box(tuple(c), (math.hypot(CH, CH) + .28, d, t), GUN, rot=(0, s*math.radians(45), 0))
    b.box((0, 0, H - PROUD + t/2), (W - 2*CH + .5, d, t), GUN)                # lintel, PROUD below the ceiling
    for k in range(-3, 4):                                                  # scuffed hazard chevrons on the sill
        b.box((k*.42, -d/2 - .005, -.02), (.18, .01, .09), HAZARD)
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

def part_beacon():
    b = Batch('Kit • Warning beacon'); x = -W/2 + .16; z = 2.25
    b.box((x - .04, MOD_L/2, z), (.12, .22, .16), GUN)
    b.cyl((x + .05, MOD_L/2, z), .06, .14, ORANGE, axis='X', n=12)
    b.box((x + .12, MOD_L/2, z), (.02, .16, .16), DARK)
    return b.finish()

def part_terminal():
    b = Batch('Kit • Wall terminal'); x = -W/2 + .12
    b.box((x, MOD_L/2, 1.35), (.24, .70, .55), GUN)                       # console body
    b.box((x + .125, MOD_L/2 - .10, 1.42), (.01, .40, .30), GREEN)          # CRT
    b.box((x + .125, MOD_L/2 + .22, 1.30), (.01, .18, .28), DARK)           # keypad
    for k in range(4): b.box((x + .13, MOD_L/2 + .22, 1.20 + k*.06), (.005, .14, .025), DARK if k % 2 else RED)
    b.box((x + .12, MOD_L/2, 1.02), (.02, .70, .04), HAZARD)
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
        b.box((s*(DOOR_W/2 + .55), -.025, 1.32), (.14, .01, .08), RED if s > 0 else ORANGE)
    b.box((0, -.01, DOOR_H + .12), (.9, .02, .06), RED)                                    # sign light
    return b.finish()

def part_door_leaf():
    b = Batch('Kit • Door leaf'); w = DOOR_W/2 + .02
    b.box((-w/2, .10, DOOR_H/2), (w, .10, DOOR_H), PANEL)
    b.box((-w/2, .045, DOOR_H/2 + .25), (w - .18, .02, DOOR_H - .7), PANEL2)      # inset
    b.box((-w/2, .04, 1.05), (w, .02, .12), HAZARD); b.box((-w/2, .035, 1.05), (w, .02, .04), DARK)
    b.box((-.02, .10, DOOR_H/2), (.04, .11, DOOR_H), DARK)                        # meeting-edge seal
    return b.finish()

K = dict(floor=part_floor(), wall=part_wall(), window=part_wall(window=True), ceiling=part_ceiling(),
         rib=part_separator(), rail=part_rail(), fan=part_fan(), frame=part_door_frame(), leaf=part_door_leaf(),
         tube_on=part_tube(COLD), tube_dim=part_tube(COLDDIM), tube_off=part_tube(COLDOFF),
         beacon=part_beacon(), terminal=part_terminal())

# ---------------------------------------------------------------- kit row (for inspection)
kit = group('Kit • parts'); kit.hide_render = True
for i, (k, mesh) in enumerate(K.items()):
    place(mesh, f'Kit {i+1:02d} • {k}', loc=(-40 + (i % 4)*5.5, -(i // 4)*5.5, 0), coll='Kit • parts')

# ---------------------------------------------------------------- assembly
import random
rng = random.Random(1979)
TUBES = [K['tube_on'], K['tube_on'], K['tube_dim'], K['tube_off']]   # most work, one dying, one dead
LIGHTS = []   # (position, energy) for the fixtures that are alive
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
    for s, side in ((-1, 'L'), (1, 'R')):
        tube = rng.choice(TUBES)
        place(tube, f'Module {tag} • tube {side}', (s*.62, y, 0))
        if tube is not K['tube_off']: LIGHTS.append(((s*.62, y + MOD_L/2, H - .12), 28 if tube is K['tube_on'] else 5))
    if i in (0, 1, 4): place(K['rail'], f'Module {tag} • handrail L', (0, y, 0))
    if i == 1: place(K['fan'], f'Module {tag} • ceiling fan', (0, y, 0))
    if i == 2: place(K['beacon'], f'Module {tag} • warning beacon L', (0, y, 0))
    if i == 3: place(K['terminal'], f'Module {tag} • wall terminal R', (0, y, 0), scale=(-1, 1, 1))
place(K['rib'], f'Joint {N+1:02d} • separator', (0, N*MOD_L, 0))
place(K['frame'], 'Door • frame', (0, N*MOD_L, 0))
OPEN = 0.16   # metres each leaf is slid into the wall; animate this for the door
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
for k, (pos, energy) in enumerate(LIGHTS):
    light(f'Tube light {k+1:02d}', 'AREA', pos, energy, (.78, .88, 1.0), .9, aim=(pos[0], pos[1], 0))
    bpy.data.lights[f'Tube light {k+1:02d}'].shape = 'RECTANGLE'; bpy.data.lights[f'Tube light {k+1:02d}'].size_y = .08
light('Near-end fill', 'AREA', (0, -.6, H - .2), 12, (.7, .82, 1.0), 1.5, aim=(0, .5, 0))
light('Beacon glow', 'POINT', (-W/2 + .30, 2*MOD_L + MOD_L/2, 2.25), 25, (1, .42, .08))
light('CRT glow', 'POINT', (W/2 - .30, 3*MOD_L + MOD_L/2, 1.42), 6, (.2, 1, .35))
# The cold light beyond the door: a spot aimed back down the corridor through the gap.
door_light = light('Beyond the door', 'SPOT', (0, N*MOD_L + 1.6, 1.9), 2500, (.62, .80, 1.0), aim=(0, -2, 1.1))
door_light.data.spot_size = math.radians(70); door_light.data.spot_blend = .4
light('Door sign spill', 'POINT', (0, N*MOD_L - .25, DOOR_H + .05), 4, (1, .12, .05))
# Fog: a single volume box the length of the corridor, so every light draws a beam.
fog = bpy.data.materials.new('Corridor haze'); fog.use_nodes = True; fn = fog.node_tree.nodes; fn.clear()
fout = fn.new('ShaderNodeOutputMaterial'); vol = fn.new('ShaderNodeVolumePrincipled')
vol.inputs['Density'].default_value = .028; vol.inputs['Color'].default_value = (.70, .82, .95, 1); vol.inputs['Anisotropy'].default_value = .45
fog.node_tree.links.new(vol.outputs['Volume'], fout.inputs['Volume'])
hz = Batch('Corridor haze volume'); hz.box((0, (N*MOD_L - MOD_L)/2, H/2), (W + .4, N*MOD_L + MOD_L + 4, H + .6), fog)
haze = place(hz.finish(bevel=0), 'Corridor haze', coll='Atmosphere'); haze.display_type = 'WIRE'
steam = bpy.data.materials.new('Steam leak'); steam.use_nodes = True; sn = steam.node_tree.nodes; sn.clear(); sl = steam.node_tree.links
sout = sn.new('ShaderNodeOutputMaterial'); svol = sn.new('ShaderNodeVolumePrincipled'); svol.inputs['Color'].default_value = (.85, .9, 1, 1); svol.inputs['Anisotropy'].default_value = .3
sco = sn.new('ShaderNodeTexCoord'); snoise = sn.new('ShaderNodeTexNoise'); snoise.inputs['Scale'].default_value = 4; snoise.inputs['Detail'].default_value = 5
sfall = sn.new('ShaderNodeVectorMath'); sfall.operation = 'LENGTH'; scen = sn.new('ShaderNodeVectorMath'); scen.operation = 'SUBTRACT'; scen.inputs[1].default_value = (.5, .5, .5)
sl.new(sco.outputs['Generated'], scen.inputs[0]); sl.new(scen.outputs[0], sfall.inputs[0])
smask = sn.new('ShaderNodeMapRange'); smask.inputs['From Min'].default_value = .15; smask.inputs['From Max'].default_value = .5; smask.inputs['To Min'].default_value = 1; smask.inputs['To Max'].default_value = 0
sl.new(sfall.outputs['Value'], smask.inputs['Value']); sl.new(sco.outputs['Object'], snoise.inputs['Vector'])
smul = sn.new('ShaderNodeMath'); smul.operation = 'MULTIPLY'; sl.new(smask.outputs[0], smul.inputs[0]); sl.new(snoise.outputs['Fac'], smul.inputs[1])
sden = sn.new('ShaderNodeMath'); sden.operation = 'MULTIPLY'; sden.inputs[1].default_value = 1.8; sl.new(smul.outputs[0], sden.inputs[0]); sl.new(sden.outputs[0], svol.inputs['Density'])
sl.new(svol.outputs['Volume'], sout.inputs['Volume'])
st = Batch('Steam leak volume'); st.box((W/2 - .55, 3*MOD_L + .6, .75), (1.0, 1.4, 1.5), steam)
steam_obj = place(st.finish(bevel=0), 'Steam leak', coll='Atmosphere'); steam_obj.display_type = 'WIRE'

def camera(name, loc, aim, lens):
    d = bpy.data.cameras.new(name); d.lens = lens; d.clip_end = 200
    o = bpy.data.objects.new(name, d); group('Lighting').objects.link(o); o.location = loc
    o.rotation_euler = (Vector(aim) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler(); return o
cam = camera('Corridor camera', (-.50, -1.1, 1.30), (0.10, N*MOD_L, 1.25), 24)
kitcam = camera('Kit camera', (-31.5, -33, 19), (-31.5, -6.5, 1.0), 40)
kitsun = light('Kit sun', 'SUN', (-34, -15, 20), 3, (1, .97, .92), aim=(-30, -5, 0)); kitsun.hide_render = True
scene.camera = cam

world = bpy.data.worlds.new('Dark hull'); scene.world = world; world.use_nodes = True
world.node_tree.nodes['Background'].inputs['Color'].default_value = (.002, .003, .005, 1)

# ---------------------------------------------------------------- render settings
scene.render.engine = 'CYCLES'; scene.cycles.samples = a.samples; scene.cycles.use_denoising = True
try: scene.cycles.denoiser = 'OPENIMAGEDENOISE'
except TypeError: pass
scene.cycles.max_bounces = 8; scene.cycles.volume_bounces = 2; scene.cycles.volume_step_rate = .5
scene.render.resolution_x = a.width; scene.render.resolution_y = round(a.width * 9/16); scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'AgX'; scene.view_settings.look = 'AgX - High Contrast'; scene.view_settings.exposure = -.05
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
    for c in ('Corridor • assembly', 'Atmosphere'): group(c).hide_render = True
    scene.render.filepath = str(a.out / 'corridor-kit.png'); bpy.ops.render.render(write_still=True)
    kit.hide_render = True; kitsun.hide_render = True; scene.camera = cam
    for c in ('Corridor • assembly', 'Atmosphere'): group(c).hide_render = False
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (.002, .003, .005, 1)
print('CORRIDOR_COMPLETE', a.out, flush=True)
