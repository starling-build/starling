#!/usr/bin/env python3
"""Refine the VRoid goth agent after import (see design/blender/agent/README.md).

  blender -b --python build/tools/blender-agent-refine.py -- --blend IN.blend --out OUT.blend
      [--petticoat 0.05] [--tail-shrink 0.72] [--tail-wave 0.055] [--tail-flare 1.7] [--skirt-shrink 0.72]

Works on the scene blender-agent-avatar.py saves (its agent.blend): recolours the skirt's
white petticoat material, compresses + waves + widens the twin tails, and shortens the skirt.
Mesh edits are in object space on the VRoid meshes, so the rig, weights and shape keys are untouched.
"""
import bpy, sys, math, argparse
from mathutils import Vector

p = argparse.ArgumentParser()
p.add_argument('--blend', required=True); p.add_argument('--out', required=True)
p.add_argument('--petticoat', type=float, default=0.05)
p.add_argument('--tail-shrink', type=float, default=0.72); p.add_argument('--tail-wave', type=float, default=0.055)
p.add_argument('--tail-flare', type=float, default=1.7); p.add_argument('--skirt-shrink', type=float, default=0.72)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=a.blend)

def mtoon_set(mat, key, rgb):
    for n in mat.node_tree.nodes:
        if n.type == 'GROUP' and key in n.inputs:
            n.inputs[key].default_value = (*rgb, 1.0); return True
    return False

body = bpy.data.objects['Body']; hair = bpy.data.objects['Hair']
# --- petticoat: the white CLOTH_03 material of the skirt preset -> near black (texture still multiplies, so the lace reads)
for m in body.data.materials:
    if m and 'N00_002_03_Tops_01_CLOTH_03' in m.name:
        ok = mtoon_set(m, 'Lit Color', (a.petticoat,) * 3); mtoon_set(m, 'Shade Color', (a.petticoat * 0.6,) * 3)
        print('PETTICOAT', m.name, 'recoloured' if ok else 'NO MTOON GROUP')

# --- twin tails: hair verts below the ears and off-centre. Compress toward the tie point, add an S-wave, widen.
me = hair.data
tail = [v for v in me.vertices if v.co.z < 1.40 and abs(v.co.x) > 0.05]
top = max(v.co.z for v in tail); bottom = min(v.co.z for v in tail); span = top - bottom
for side in (-1, 1):
    vs = [v for v in tail if (v.co.x > 0) == (side > 0)]
    cx = sum(v.co.x for v in vs) / len(vs)
    for v in vs:
        t = (top - v.co.z) / span                      # 0 at the tie, 1 at the tip
        z = top - (top - v.co.z) * a.tail_shrink       # shorter
        x = cx + (v.co.x - cx) * (1 + (a.tail_flare - 1) * t)   # fuller toward the tip
        x += side * a.tail_wave * math.sin(t * math.pi * 2.2) * t   # S-wave that grows down the tail
        y = v.co.y + a.tail_wave * 0.6 * math.sin(t * math.pi * 2.2 + 1.3) * t
        v.co = Vector((x, y, z))
print('TAILS', len(tail), 'verts, span %.2f -> %.2f' % (span, span * a.tail_shrink))

# --- skirt: outer skirt (CLOTH_01) + petticoat (CLOTH_03) compressed toward the waist
me = body.data
idx = {i for i, m in enumerate(me.materials) if m and ('N00_002_03_Tops_01_CLOTH_01' in m.name or 'N00_002_03_Tops_01_CLOTH_03' in m.name)}
sv = set()
for poly in me.polygons:
    if poly.material_index in idx: sv.update(poly.vertices)
waist = max(me.vertices[i].co.z for i in sv)
for i in sv:
    v = me.vertices[i]; v.co.z = waist - (waist - v.co.z) * a.skirt_shrink
print('SKIRT', len(sv), 'verts, waist %.2f' % waist)
for o in (body, hair):
    if o.data.shape_keys:   # VRoid meshes with keys: Basis must follow, or the edit is invisible
        for k in o.data.shape_keys.key_blocks:
            for i, v in enumerate(o.data.vertices): k.data[i].co = v.co
bpy.ops.wm.save_as_mainfile(filepath=a.out); print('SAVED', a.out)
