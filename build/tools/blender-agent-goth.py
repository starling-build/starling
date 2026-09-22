#!/usr/bin/env python3
"""Dress the VRoid sample girl as a blonde twin-tail gothic character (see design/blender/agent).

  /snap/bin/blender --factory-startup -b --python build/tools/blender-agent-goth.py -- \
      --vrm twist-sample.vrm --addon-zip VRM_Addon.zip --out DIR [--width 720 --height 1280]

Keeps the VRM rig, face and mouth shapes (so the lip-sync script still works), recolours
hair and eyes by hue-shifting their textures, trims the hair to a bob and adds twin tails,
and builds the outfit as new meshes parented to the bones. Saves DIR/goth.blend.
"""
import bpy, sys, math, argparse, bmesh
import numpy as np
from pathlib import Path
from mathutils import Vector, Matrix

p = argparse.ArgumentParser()
p.add_argument('--vrm', required=True); p.add_argument('--addon-zip'); p.add_argument('--out', type=Path, required=True)
p.add_argument('--width', type=int, default=720); p.add_argument('--height', type=int, default=1280); p.add_argument('--no-render', action='store_true')
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:]); a.out.mkdir(parents=True, exist_ok=True)

import addon_utils
if a.addon_zip: bpy.ops.preferences.addon_install(filepath=a.addon_zip, overwrite=True)
bpy.ops.preferences.addon_enable(module=[m.__name__ for m in addon_utils.modules() if 'vrm' in m.__name__.lower()][0])
for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.vrm(filepath=a.vrm)
scene = bpy.context.scene
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
body = bpy.data.objects['Body']; face = bpy.data.objects['Face']; hair = bpy.data.objects['Hair']
hb = arm.data.vrm_addon_extension.vrm1.humanoid.human_bones
def bone(n): return getattr(hb, n).node.bone_name
def bpos(n, tail=False):
    pb = arm.pose.bones[bone(n)]; return arm.matrix_world @ (pb.tail if tail else pb.head)

# ---------------------------------------------------------------- textures: blonde hair, blue eyes
def hue_shift(image, hue=None, sat_mul=1.0, val_mul=1.0):
    w, h = image.size; px = np.empty(w * h * 4, dtype=np.float32); image.pixels.foreach_get(px); px = px.reshape(-1, 4)
    r, g, b = px[:, 0], px[:, 1], px[:, 2]; mx = np.max(px[:, :3], axis=1); mn = np.min(px[:, :3], axis=1); d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0); v = mx
    hh = np.zeros_like(mx); m = d > 1e-6
    rc = np.where(m, (mx - r) / np.maximum(d, 1e-6), 0); gc = np.where(m, (mx - g) / np.maximum(d, 1e-6), 0); bc = np.where(m, (mx - b) / np.maximum(d, 1e-6), 0)
    hh = np.where(r == mx, bc - gc, np.where(g == mx, 2 + rc - bc, 4 + gc - rc)) / 6.0 % 1.0
    if hue is not None: hh = np.where(m, hue, hh)
    s = np.clip(s * sat_mul, 0, 1); v = np.clip(v * val_mul, 0, 1)
    i = np.floor(hh * 6).astype(int) % 6; f = hh * 6 - np.floor(hh * 6); pp = v * (1 - s); q = v * (1 - s * f); t = v * (1 - s * (1 - f))
    R = np.choose(i, [v, q, pp, pp, t, v]); G = np.choose(i, [t, v, v, q, pp, pp]); B = np.choose(i, [pp, pp, t, v, v, q])
    px[:, 0], px[:, 1], px[:, 2] = R, G, B; image.pixels.foreach_set(px.ravel()); image.update()
    image.pack()   # re-embed the recoloured pixels, or a reopened .blend shows the original texture
for nm in ('Hair_00', 'HairBack_00'):
    if nm in bpy.data.images: hue_shift(bpy.data.images[nm], hue=.12, sat_mul=.9, val_mul=1.6)
if 'EyeIris_00' in bpy.data.images: hue_shift(bpy.data.images['EyeIris_00'], hue=.62, sat_mul=1.35, val_mul=1.1)

# MToon colour factors on the VRM's own materials (shirt, shorts, shoes go black)
def mtoon_tint(matname, rgb, shade=None):
    m = bpy.data.materials.get(matname)
    if not m: return
    mt = m.vrm_addon_extension.mtoon1
    mt.pbr_metallic_roughness.base_color_factor = (*rgb, 1)
    mt.extensions.vrmc_materials_mtoon.shade_color_factor = shade or tuple(c * .55 for c in rgb)
for nm in ('Tops_01_CLOTH', 'Bottoms_01_CLOTH', 'Shoes_01_CLOTH'): mtoon_tint(nm, (.08, .07, .10))

# ---------------------------------------------------------------- hair: trim to a bob, twin tails from curves
def trim_below(obj, z, material_name=None):
    bm = bmesh.new(); bm.from_mesh(obj.data)
    mi = None
    if material_name:
        for k, m in enumerate(obj.data.materials):
            if m and m.name == material_name: mi = k
    geom = [f for f in bm.faces if mi is None or f.material_index == mi]
    geom = geom + list({e for f in geom for e in f.edges}) + list({v for f in geom for v in f.verts})
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, -1), clear_outer=True)
    low = [v for v in bm.verts if (obj.matrix_world @ v.co).z < z - .002 and (mi is None or any(f.material_index == mi for f in v.link_faces))]
    bmesh.ops.delete(bm, geom=low, context='VERTS')
    bm.to_mesh(obj.data); bm.free()
trim_below(hair, 1.37); trim_below(body, 1.37, 'HairBack_00_HAIR')   # ear level: bangs and crown stay, sides end at the tails' ties

def toon(name, color, shade=.5, alpha_grid=None, spec=.0):
    m = bpy.data.materials.new(name); m.use_nodes = True; n, l = m.node_tree.nodes, m.node_tree.links; n.clear()
    out = n.new('ShaderNodeOutputMaterial'); dif = n.new('ShaderNodeBsdfDiffuse'); dif.inputs['Color'].default_value = (1, 1, 1, 1)
    torgb = n.new('ShaderNodeShaderToRGB'); ramp = n.new('ShaderNodeValToRGB'); ramp.color_ramp.interpolation = 'CONSTANT'
    ramp.color_ramp.elements[0].color = (*(c * shade for c in color), 1); ramp.color_ramp.elements[1].position = .42; ramp.color_ramp.elements[1].color = (*color, 1)
    em = n.new('ShaderNodeEmission'); l.new(dif.outputs[0], torgb.inputs[0]); l.new(torgb.outputs['Color'], ramp.inputs['Fac']); l.new(ramp.outputs['Color'], em.inputs['Color'])
    if spec:
        gl = n.new('ShaderNodeBsdfGlossy') if hasattr(bpy.types, 'ShaderNodeBsdfGlossy') else n.new('ShaderNodeBsdfAnisotropic'); gl.inputs['Roughness'].default_value = .25
        add = n.new('ShaderNodeAddShader'); mixf = n.new('ShaderNodeMixShader'); mixf.inputs['Fac'].default_value = spec
        l.new(em.outputs[0], add.inputs[0]); l.new(gl.outputs[0], mixf.inputs[2]); l.new(em.outputs[0], mixf.inputs[1]); l.new(mixf.outputs[0], out.inputs['Surface'])
    elif alpha_grid:
        tr = n.new('ShaderNodeBsdfTransparent'); mix = n.new('ShaderNodeMixShader'); uv = n.new('ShaderNodeTexCoord')
        mp = n.new('ShaderNodeMapping'); mp.inputs['Rotation'].default_value = (0, 0, math.radians(45)); mp.inputs['Scale'].default_value = (alpha_grid, alpha_grid * .5, 1)
        w1 = n.new('ShaderNodeTexWave'); w1.wave_type = 'BANDS'; w1.bands_direction = 'X'; w1.wave_profile = 'TRI'; w1.inputs['Scale'].default_value = 1
        w2 = n.new('ShaderNodeTexWave'); w2.wave_type = 'BANDS'; w2.bands_direction = 'Y'; w2.wave_profile = 'TRI'; w2.inputs['Scale'].default_value = 1
        l.new(uv.outputs['UV'], mp.inputs['Vector']); l.new(mp.outputs[0], w1.inputs['Vector']); l.new(mp.outputs[0], w2.inputs['Vector'])
        mn = n.new('ShaderNodeMath'); mn.operation = 'MINIMUM'; l.new(w1.outputs['Fac'], mn.inputs[0]); l.new(w2.outputs['Fac'], mn.inputs[1])
        thr = n.new('ShaderNodeMath'); thr.operation = 'LESS_THAN'; thr.inputs[1].default_value = .18; l.new(mn.outputs[0], thr.inputs[0])
        l.new(thr.outputs[0], mix.inputs['Fac']); l.new(tr.outputs[0], mix.inputs[1]); l.new(em.outputs[0], mix.inputs[2]); l.new(mix.outputs[0], out.inputs['Surface'])
        m.blend_method = 'HASHED'; m.use_backface_culling = False
    else: l.new(em.outputs[0], out.inputs['Surface'])
    return m
BLACK = toon('Goth black', (.075, .065, .095), .38); BLACK_SHINE = toon('Goth leather', (.07, .06, .09), .4, spec=.25)
BLONDE = toon('Blonde hair', (.95, .80, .45), .66, spec=.12)
_n, _l = BLONDE.node_tree.nodes, BLONDE.node_tree.links
_ramp = [x for x in _n if x.type == 'VALTORGB'][0]; _uv = _n.new('ShaderNodeTexCoord'); _wave = _n.new('ShaderNodeTexWave'); _wave.wave_type = 'BANDS'; _wave.bands_direction = 'Y'; _wave.inputs['Scale'].default_value = 40; _wave.inputs['Distortion'].default_value = .8
_mul = _n.new('ShaderNodeMix'); _mul.data_type = 'RGBA'; _mul.blend_type = 'MULTIPLY'; _mul.inputs['Factor'].default_value = .28
_l.new(_uv.outputs['UV'], _wave.inputs['Vector']); _l.new(_ramp.outputs['Color'], _mul.inputs['A']); _l.new(_wave.outputs['Color'], _mul.inputs['B'])
_em = [x for x in _n if x.type == 'EMISSION'][0]; _l.new(_mul.outputs['Result'], _em.inputs['Color']); GOLD = toon('Gold buckle', (.85, .62, .18), .5, spec=.4)
LACE = toon('Lace grey', (.30, .28, .34), .5); FISHNET = toon('Fishnet', (.08, .07, .10), .45, alpha_grid=26)
SKIN = toon('Pale skin', (.98, .88, .82), .7); RIBBON = toon('Ribbon black', (.10, .08, .12), .5)

def link(obj, name, parent_bone=None):
    obj.name = name; scene.collection.objects.link(obj) if obj.name not in scene.collection.objects else None
    if parent_bone:
        obj.parent = arm; obj.parent_type = 'BONE'; obj.parent_bone = parent_bone
        pb = arm.pose.bones[parent_bone]
        obj.matrix_parent_inverse = (arm.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.length, 0))).inverted()
    return obj
def mesh_obj(name, verts, faces, mat, uvs=None, parent_bone=None, smooth=True):
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.materials.append(mat)
    if uvs:
        uvl = me.uv_layers.new(); k = 0
        for poly in me.polygons:
            for li in poly.loop_indices: uvl.data[li].uv = uvs[me.loops[li].vertex_index]
    for pl in me.polygons: pl.use_smooth = smooth
    o = bpy.data.objects.new(name, me); return link(o, name, parent_bone)
def tube(name, centers, radii, mat, n=24, cap=False, parent_bone=None, scale_y=1.0):
    verts = []; uvs = []; faces = []
    for k, (c, r) in enumerate(zip(centers, radii)):
        for i in range(n):
            t = 2 * math.pi * i / n; verts.append((c[0] + r * math.cos(t), c[1] + r * scale_y * math.sin(t), c[2])); uvs.append((i / n, k / (len(centers) - 1)))
    for k in range(len(centers) - 1):
        for i in range(n): j = (i + 1) % n; faces.append((k*n + i, k*n + j, (k+1)*n + j, (k+1)*n + i))
    if cap: faces.append(tuple(range(n))); faces.append(tuple(reversed(range((len(centers)-1)*n, len(centers)*n))))
    return mesh_obj(name, verts, faces, mat, uvs, parent_bone)
def body_radius(z, xsign, band=.012):
    pts = [body.matrix_world @ v.co for v in body.data.vertices]
    sel = [p for p in pts if abs(p.z - z) < band and p.x * xsign > .02]
    if not sel: return .05
    cx = sum(p.x for p in sel) / len(sel); cy = sum(p.y for p in sel) / len(sel)
    return max(math.hypot(p.x - cx, p.y - cy) for p in sel), (cx, cy)

# twin tails
def twin_tail(sign):
    hz = bpos('head').z; base = Vector((sign * .105, .0, hz + .085))
    for k, (dx, dy, r) in enumerate([(0, 0, .038), (.018, -.018, .026), (-.012, .02, .024), (.01, .03, .02), (.03, .005, .018), (-.02, -.02, .016)]):
        cu = bpy.data.curves.new(f'tail{sign}{k}', 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = r; cu.bevel_resolution = 6; cu.fill_mode = 'FULL'; cu.use_fill_caps = True
        if hasattr(cu, 'use_uv_as_generated'): cu.use_uv_as_generated = True
        sp = cu.splines.new('BEZIER'); sp.bezier_points.add(3)
        pts = [base + Vector((sign * (.01 + dx), dy, .0)), base + Vector((sign * (.075 + dx), -.005 + dy, -.09)), base + Vector((sign * (.085 + dx), .015 + dy, -.34)), base + Vector((sign * (.06 + dx * .5), .03 + dy, -.62 - k * .025))]
        for bp, pt, rad in zip(sp.bezier_points, pts, (.9, 1.2, .9, .15)):
            bp.co = pt; bp.handle_left_type = bp.handle_right_type = 'AUTO'; bp.radius = rad
        o = bpy.data.objects.new(f'Twin tail {"L" if sign > 0 else "R"} {k}', cu); o.data.materials.append(BLONDE); link(o, o.name, bone('head'))
    # hair tie: a small black bow
    for s in (-1, 1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=.03, location=base + Vector((sign * .02, s * .03, .01))); bo = bpy.context.object; bo.scale = (.7, 1.3, .8); bo.data.materials.append(RIBBON); link(bo, f'Hair bow {sign}{s}', bone('head'))
twin_tail(1); twin_tail(-1)

# ---------------------------------------------------------------- outfit
sh_z = bpos('left_upper_arm').z; chest_z = bpos('chest').z; hips_z = bpos('hips').z; spine_z = bpos('spine').z
# off-shoulder frill: a soft ring just below the shoulders
rb, _ = body_radius(sh_z - .06, 1); rb = .175
tube('Off-shoulder frill', [(0, -.01, sh_z - .045), (0, -.01, sh_z - .075), (0, -.015, sh_z - .10)], [rb + .01, rb + .035, rb + .02], BLACK, n=40, parent_bone=bone('chest'), scale_y=.72)
tube('Frill lace edge', [(0, -.015, sh_z - .10), (0, -.015, sh_z - .112)], [rb + .022, rb + .028], LACE, n=40, parent_bone=bone('chest'), scale_y=.72)
# puff sleeves on the upper arms (built in rest pose, parented to the arm bones)
for side in ('left', 'right'):
    h = bpos(side + '_upper_arm'); t = bpos(side + '_upper_arm', True); c = h.lerp(t, .36)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=12, radius=.062, location=c); s = bpy.context.object; s.scale = (1.25, .95, .9); s.data.materials.append(BLACK); link(s, f'Puff sleeve {side}', bone(side + '_upper_arm'))
    tube(f'Sleeve cuff {side}', [(c.x + (1 if side == 'left' else -1) * .075, c.y, c.z), (c.x + (1 if side == 'left' else -1) * .085, c.y, c.z)], [.05, .052], LACE, n=20, parent_bone=bone(side + '_upper_arm'))
    # gloves: a rounded block over the hand plus a cuff at the wrist
    hh = bpos(side + '_hand'); ht = bpos(side + '_hand', True); hc = hh.lerp(ht, .55)
    bpy.ops.mesh.primitive_cube_add(size=1, location=hc); g = bpy.context.object; g.scale = (.11, .035, .075); g.data.materials.append(BLACK_SHINE)
    bev = g.modifiers.new('round', 'BEVEL'); bev.width = .015; bev.segments = 4; link(g, f'Glove {side}', bone(side + '_hand'))
    tube(f'Glove cuff {side}', [(hh.x, hh.y, hh.z)], [.04], BLACK_SHINE, n=16, parent_bone=bone(side + '_hand')) if False else None
# corset and belt around the waist
waist_z = spine_z + .02; wr = .16
tube('Corset', [(0, -.01, waist_z - .07), (0, -.01, waist_z), (0, -.01, waist_z + .08)], [wr + .012, wr - .004, wr + .01], BLACK_SHINE, n=40, parent_bone=bone('spine'), scale_y=.68)
for k in range(5):
    z = waist_z - .06 + k * .03; mesh_obj(f'Corset lace {k}', [(-.045, -.012 - (wr - .004) * .68 - .003, z), (.045, -.012 - (wr - .004) * .68 - .003, z), (.045, -.012 - (wr - .004) * .68 - .003, z + .006), (-.045, -.012 - (wr - .004) * .68 - .003, z + .006)], [(0, 1, 2, 3)], LACE, parent_bone=bone('spine'), smooth=False)
tube('Belt', [(0, -.01, waist_z - .012), (0, -.01, waist_z + .012)], [wr + .018, wr + .018], BLACK_SHINE, n=40, parent_bone=bone('spine'), scale_y=.68)
bpy.ops.mesh.primitive_torus_add(major_radius=.022, minor_radius=.005, location=(0, -.01 - (wr + .02) * .68, waist_z), rotation=(math.radians(90), 0, 0)); bk = bpy.context.object; bk.scale = (1.3, 1, 1); bk.data.materials.append(GOLD); link(bk, 'Belt buckle', bone('spine'))
# pleated skirt: waist ring to a zigzag hem, two layers
def skirt(name, top_z, bot_z, top_r, bot_r, mat, n=48, zig=.02):
    centers = [(0, -.005, top_z), (0, -.005, top_z - (top_z - bot_z) * .45), (0, -.005, bot_z)]
    verts = []; faces = []
    for k, (c, r) in enumerate(zip(centers, (top_r, top_r + (bot_r - top_r) * .5, bot_r))):
        for i in range(n):
            t = 2 * math.pi * i / n; rr = r + (zig if (i % 2 == 0 and k == 2) else 0) + (zig * .5 if (i % 2 == 0 and k == 1) else 0)
            verts.append((rr * math.cos(t), c[1] + rr * .8 * math.sin(t), c[2] + (-.012 if (i % 2 == 0 and k == 2) else 0)))
    for k in range(2):
        for i in range(n): j = (i + 1) % n; faces.append((k*n + i, k*n + j, (k+1)*n + j, (k+1)*n + i))
    return mesh_obj(name, verts, faces, mat, parent_bone=bone('hips'), smooth=False)
skirt('Skirt', hips_z + .06, hips_z - .27, wr - .01, .36, BLACK)
skirt('Skirt underlayer', hips_z + .05, hips_z - .30, wr - .015, .35, LACE, n=48, zig=.015)
tube('Skirt hem trim', [(0, -.005, hips_z - .265), (0, -.005, hips_z - .28)], [.372, .375], LACE, n=48, parent_bone=bone('hips'), scale_y=.8)
# stockings: left opaque, right fishnet; each split at the knee so it follows both leg bones
for side, mat in (('left', BLACK), ('right', FISHNET)):
    sgn = 1 if side == 'left' else -1
    up_h = bpos(side + '_upper_leg'); kn = bpos(side + '_lower_leg'); an = bpos(side + '_foot')
    def ring(z):
        r, (cx, cy) = body_radius(z, sgn); return (cx, cy, z), r + .004
    top_z = up_h.z - .16
    zs_up = [top_z, top_z - .06, kn.z + .06, kn.z]; zs_lo = [kn.z, kn.z - .1, an.z + .12, an.z + .06]
    cu = [ring(z) for z in zs_up]; lo = [ring(z) for z in zs_lo]
    tube(f'Stocking {side} upper', [c for c, r in cu], [r for c, r in cu], mat, n=28, parent_bone=bone(side + '_upper_leg'))
    tube(f'Stocking {side} lower', [c for c, r in lo], [r for c, r in lo], mat, n=28, parent_bone=bone(side + '_lower_leg'))
    c0, r0 = cu[0]; tube(f'Stocking top band {side}', [(c0[0], c0[1], top_z + .012), (c0[0], c0[1], top_z - .012)], [r0 + .003, r0 + .003], LACE, n=28, parent_bone=bone(side + '_upper_leg'))
    for s in (-1, 1):   # bow on the outer front
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=.024, location=(c0[0] + sgn * (r0 + .01) * .6 + s * .02, c0[1] - (r0 + .01) * .75, top_z + .012)); bo = bpy.context.object; bo.scale = (1.3, .6, .8); bo.data.materials.append(RIBBON); link(bo, f'Stocking bow {side}{s}', bone(side + '_upper_leg'))
    # platform boot: sole, foot block, shaft
    fz = an.z; fx = c0[0]
    bpy.ops.mesh.primitive_cube_add(size=1, location=(fx, an.y - .03, .025)); sole = bpy.context.object; sole.scale = (.105, .27, .05); sole.data.materials.append(BLACK_SHINE); link(sole, f'Boot sole {side}', bone(side + '_foot'))
    bpy.ops.mesh.primitive_cube_add(size=1, location=(fx, an.y - .035, .09)); ft = bpy.context.object; ft.scale = (.095, .245, .08); ft.data.materials.append(BLACK_SHINE)
    bv = ft.modifiers.new('round', 'BEVEL'); bv.width = .02; bv.segments = 3; link(ft, f'Boot foot {side}', bone(side + '_foot'))
    lo_c, lo_r = lo[-1]; tube(f'Boot shaft {side}', [(lo_c[0], lo_c[1] + .01, .11), (lo_c[0], lo_c[1] + .01, .21), (lo_c[0], lo_c[1] + .005, .27)], [lo_r + .012, lo_r + .01, lo_r + .012], BLACK_SHINE, n=24, parent_bone=bone(side + '_lower_leg'))
    for k in range(5):   # laces
        z = .13 + k * .03; mesh_obj(f'Boot lace {side}{k}', [(lo_c[0] - .02, lo_c[1] - lo_r - .012, z), (lo_c[0] + .02, lo_c[1] - lo_r - .012, z), (lo_c[0] + .02, lo_c[1] - lo_r - .012, z + .006), (lo_c[0] - .02, lo_c[1] - lo_r - .012, z + .006)], [(0, 1, 2, 3)], LACE, parent_bone=bone(side + '_lower_leg'), smooth=False)
# choker: lace band at the neck
nz = bpos('neck').z + .035
tube('Choker', [(0, .01, nz - .012), (0, .01, nz + .012)], [.048, .048], BLACK, n=24, parent_bone=bone('neck'))
tube('Choker lace', [(0, .0, nz - .05), (0, .005, nz - .014)], [.09, .052], LACE, n=32, parent_bone=bone('neck'), scale_y=.8)

# ---------------------------------------------------------------- pose: arms down and slightly forward
def rotate_bone(bname, axis, degrees):
    pb = arm.pose.bones[bname]; rest = pb.bone.matrix_local.to_3x3(); R = Matrix.Rotation(math.radians(degrees), 3, axis)
    pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = (rest.inverted() @ R @ rest).to_quaternion()
rotate_bone(bone('left_upper_arm'), 'Y', 72); rotate_bone(bone('right_upper_arm'), 'Y', -72)
rotate_bone(bone('left_lower_arm'), 'X', -12); rotate_bone(bone('right_lower_arm'), 'X', -12)
for side, sgn in (('left', 1), ('right', -1)):
    sh = getattr(hb, side + '_shoulder').node.bone_name
    if sh: rotate_bone(sh, 'Y', sgn * 5)

# ---------------------------------------------------------------- scene: dark violet studio
cam_d = bpy.data.cameras.new('Full camera'); cam_d.lens = 50; cam = bpy.data.objects.new('Full camera', cam_d); scene.collection.objects.link(cam)
aim = Vector((0, 0, .82)); cam.location = Vector((0, -3.6, .95)); cam.rotation_euler = (aim - cam.location).to_track_quat('-Z', 'Y').to_euler(); scene.camera = cam
bust_d = bpy.data.cameras.new('Bust camera'); bust_d.lens = 65; bust = bpy.data.objects.new('Bust camera', bust_d); scene.collection.objects.link(bust)
baim = bpos('head') + Vector((0, 0, -.02)); bust.location = baim + Vector((.04, -1.5, .02)); bust.rotation_euler = (baim - bust.location).to_track_quat('-Z', 'Y').to_euler()
def light(name, kind, loc, energy, color, size=1.0, at=aim):
    d = bpy.data.lights.new(name, kind); d.energy = energy; d.color = color
    if kind == 'AREA': d.size = size
    o = bpy.data.objects.new(name, d); scene.collection.objects.link(o); o.location = loc; o.rotation_euler = (Vector(at) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler(); return o
light('Key', 'AREA', (1.4, -2.6, 2.2), 700, (1, .95, .92), 2.0)
light('Fill', 'AREA', (-1.8, -2.2, 1.2), 220, (.8, .75, 1), 3.0)
light('Rim violet', 'AREA', (-1.2, 1.6, 1.9), 900, (.7, .4, 1), 1.0)
light('Rim warm', 'AREA', (1.3, 1.4, 1.6), 300, (1, .7, .5), 1.0)
bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0)); floor = bpy.context.object; floor.name = 'Floor'
fm = bpy.data.materials.new('Studio floor'); fm.use_nodes = True; fs = fm.node_tree.nodes['Principled BSDF']; fs.inputs['Base Color'].default_value = (.03, .02, .05, 1); fs.inputs['Roughness'].default_value = .35; floor.data.materials.append(fm)
bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 3.5, 3), rotation=(math.radians(90), 0, 0)); bd = bpy.context.object; bd.name = 'Backdrop'
bm_ = bpy.data.materials.new('Violet gradient'); bm_.use_nodes = True; n, l = bm_.node_tree.nodes, bm_.node_tree.links; n.clear()
out = n.new('ShaderNodeOutputMaterial'); em = n.new('ShaderNodeEmission'); co = n.new('ShaderNodeTexCoord'); grad = n.new('ShaderNodeTexGradient'); grad.gradient_type = 'SPHERICAL'
mp = n.new('ShaderNodeMapping'); mp.inputs['Location'].default_value = (-.5, -.42, 0); mp.inputs['Scale'].default_value = (1.3, 1.6, 1)
ramp = n.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].color = (.008, .004, .014, 1); ramp.color_ramp.elements[1].color = (.16, .06, .26, 1)
l.new(co.outputs['UV'], mp.inputs['Vector']); l.new(mp.outputs[0], grad.inputs['Vector']); l.new(grad.outputs['Fac'], ramp.inputs['Fac']); l.new(ramp.outputs['Color'], em.inputs['Color']); l.new(em.outputs[0], out.inputs['Surface']); bd.data.materials.append(bm_)
world = bpy.data.worlds.new('Studio'); scene.world = world; world.use_nodes = True; world.node_tree.nodes['Background'].inputs['Color'].default_value = (.03, .015, .05, 1); world.node_tree.nodes['Background'].inputs['Strength'].default_value = .5

scene.render.engine = 'BLENDER_EEVEE'; scene.render.resolution_x = a.width; scene.render.resolution_y = a.height
scene.view_settings.view_transform = 'AgX'; scene.view_settings.look = 'AgX - Medium High Contrast'
bpy.ops.wm.save_as_mainfile(filepath=str(a.out / 'goth.blend'))
if not a.no_render:
    scene.render.filepath = str(a.out / 'goth-full.png'); bpy.ops.render.render(write_still=True)
    scene.camera = bust; scene.render.resolution_x = a.height * 16 // 9 if a.height < a.width else 1280; scene.render.resolution_y = 720
    scene.render.filepath = str(a.out / 'goth-bust.png'); bpy.ops.render.render(write_still=True)
print('GOTH_COMPLETE', a.out, flush=True)
