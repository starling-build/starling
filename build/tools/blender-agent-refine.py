#!/usr/bin/env python3
"""Refine the VRoid goth agent toward the reference picture (see design/blender/agent/README.md).

  blender -b --python build/tools/blender-agent-refine.py -- --blend IN.blend --out OUT.blend [options]

Runs on the scene blender-agent-avatar.py saves (its agent.blend) and edits only what VRoid Studio
cannot: the blouse is cut into an off-shoulder top with short puffed sleeves and a frill, the bell
skirt is re-shaped into two layers of knife pleats with handkerchief points (petticoat dropped), the twin tails are
shortened, flared and waved, the cloth is re-tinted slate navy, hair and irises are hue-shifted, and
a lace choker, a gold-buckle belt, stocking bands with bows and hair ties are added. Every added
piece is weighted to a bone and every edited vertex keeps its weights, so the rig, the mouth shapes
and blender-agent-avatar.py --blend all keep working.
"""
import bpy, bmesh, sys, math, argparse
import numpy as np
from mathutils import Vector, Matrix
from mathutils.kdtree import KDTree
from mathutils.bvhtree import BVHTree

p = argparse.ArgumentParser()
p.add_argument('--blend', required=True); p.add_argument('--out', required=True)
p.add_argument('--neckline', type=float, default=1.285)     # off-shoulder line on the torso (rest pose, m)
p.add_argument('--sleeve-start', type=float, default=0.03)  # along the upper arm from the shoulder joint
p.add_argument('--sleeve-end', type=float, default=0.212)
p.add_argument('--puff', type=float, default=0.80)        # (VRoid-sleeve mode only)
p.add_argument('--puff-r', type=float, default=0.040)     # own sleeve: extra radius at the middle of the puff
p.add_argument('--vroid-sleeves', action='store_true')     # keep and puff VRoid's sleeve instead of building one
p.add_argument('--underbust', type=float, default=1.2)      # corset above this height becomes a navy bodice (0 = keep)
p.add_argument('--skirt-len', type=float, default=0.30)     # bottom tier, between the points
p.add_argument('--skirt-points', type=float, default=0.22)  # handkerchief point depth (fraction)
p.add_argument('--skirt-hem', type=float, default=0.30)
p.add_argument('--pleats', type=int, default=16); p.add_argument('--pleat-depth', type=float, default=0.038)
p.add_argument('--cloth-toony', type=float, default=0.5)
p.add_argument('--rim', type=float, default=0.55)          # strength of the built-in rim glow (0 = VRoid's)
p.add_argument('--hair-shade', type=int, nargs=3, default=(150, 96, 44))   # sRGB shade colour for the hair   # VRoid cloth is 0.95 (hard cel); the reference is soft
p.add_argument('--fishnet-cell', type=float, default=34); p.add_argument('--fishnet-width', type=float, default=3.2)   # texels at 2048
p.add_argument('--blouse', type=int, default=1)            # fitted gathered blouse over the upper torso, straight neckline
p.add_argument('--neckline-drop', type=float, default=0.034)   # neckline below the shoulder joints
p.add_argument('--piping', type=int, nargs=3, default=(58, 57, 80))   # sRGB piping colour
p.add_argument('--ruffle', type=float, default=0.022)     # hem frill depth under each skirt layer
p.add_argument('--skirt-cuts', type=int, default=5); p.add_argument('--skirt-flare', type=float, default=0.8)     # bottom-tier hem radius
p.add_argument('--tail-len', type=float, default=0.38)      # tie to tip, metres (--tail-tip overrides)
p.add_argument('--tail-tip', type=float, default=0.0)
p.add_argument('--tail-root', type=float, default=0.0);   # 0 = measure (top of the tail strands - 4 cm)
p.add_argument('--tail-spread', type=float, default=0.095)  # how far each tail arcs out from its tie
p.add_argument('--tail-width', type=float, default=1.4)    # strand cross-section scale
p.add_argument('--tail-flick', type=float, default=0.03)
p.add_argument('--tail-lift', type=float, default=0.035)   # how far the tails rise out of the ties before falling   # outward flick at the tips
p.add_argument('--tail-fan', type=int, default=1)          # add two copies per strand with other spreads/lengths
p.add_argument('--bangs', type=float, default=1.10)         # fringe length factor, from its hairline
p.add_argument('--sidelocks', type=float, default=1.9)      # length factor for the outer fringe pieces (face-framing locks)
p.add_argument('--crown', type=float, default=1.07)         # overall hair volume (not the tails)
p.add_argument('--tail-wave', type=float, default=0.008)
p.add_argument('--stocking-top', type=float, default=0.0)   # 0 = detect from the skin texture
p.add_argument('--thigh', type=float, default=0.10)         # extra thigh fullness (fraction, peaks mid-thigh)
p.add_argument('--arm-out', type=float, default=8.0)        # raise the arms away from the body (degrees)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=a.blend)
scene = bpy.context.scene
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
body = bpy.data.objects['Body']; hair = bpy.data.objects['Hair']; coll = body.users_collection[0]
B = arm.data.bones
DZ = B['J_Bip_C_Hips'].head_local.z - 0.977   # heights below were tuned on a model with hips at 0.977 m
if a.underbust: a.underbust += DZ
a.neckline += DZ
print('DZ %+.3f' % DZ)

def lin(c): c /= 255; return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def srgb(rgb): return tuple(lin(c) for c in rgb)

# ------------------------------------------------------------------ materials
def mtoon(mat):
    for n in mat.node_tree.nodes:
        if n.type == 'GROUP' and 'Lit Color' in n.inputs: return n
def lit_image(mat):
    imgs = [n.image for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]
    return max(imgs, key=lambda i: i.size[0] * i.size[1]) if imgs else None
def image_mean_linear(img):
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4); px = px[px[:, 3] > 0.5][:, :3]
    m = px.mean(axis=0) if len(px) else np.ones(3)
    return np.where(m <= 0.04045, m / 12.92, ((m + 0.055) / 1.055) ** 2.4)
def tint(key, target_srgb, shade=0.45):
    """Set MToon lit/shade so texture x factor lands on the target colour."""
    for m in bpy.data.materials:
        if key in m.name and not m.name.startswith('MToon Outline') and m.node_tree and mtoon(m):
            img = lit_image(m); mean = image_mean_linear(img) if img else np.ones(3)
            f = [min(1.0, t / max(1e-4, c)) for t, c in zip(srgb(target_srgb), mean)]
            g = mtoon(m); g.inputs['Lit Color'].default_value = (*f, 1.0)
            if 'Shade Color' in g.inputs: g.inputs['Shade Color'].default_value = (*[c * shade for c in f], 1.0)
            print('TINT', m.name[:40], [round(c, 3) for c in f])
def pmat(name, rgb, rough=0.5, metal=0.0, spec=0.5):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes.get('Principled BSDF')
    b.inputs['Base Color'].default_value = (*srgb(rgb), 1.0); b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if 'Specular IOR Level' in b.inputs: b.inputs['Specular IOR Level'].default_value = spec
    return m
SATIN = pmat('Choker satin', (14, 12, 18), rough=0.32, spec=0.6)
def lace_mat():
    m = pmat('Lace see-through', (7, 6, 9), rough=0.9, spec=0.05); nt = m.node_tree; b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord'); vo = nt.nodes.new('ShaderNodeTexVoronoi'); vo.feature = 'DISTANCE_TO_EDGE'; vo.inputs['Scale'].default_value = 330
    ramp = nt.nodes.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].position = 0.045; ramp.color_ramp.elements[1].position = 0.09
    ramp.color_ramp.elements[0].color = (1, 1, 1, 1); ramp.color_ramp.elements[1].color = (0.0, 0.0, 0.0, 1)
    nt.links.new(tc.outputs['Object'], vo.inputs['Vector']); nt.links.new(vo.outputs['Distance'], ramp.inputs['Fac']); nt.links.new(ramp.outputs['Color'], b.inputs['Alpha'])
    if hasattr(m, 'surface_render_method'): m.surface_render_method = 'DITHERED'
    if hasattr(m, 'blend_method'): m.blend_method = 'HASHED'
    return m
LACE = lace_mat()
NAVY_TRIM = pmat('Skirt trim', (26, 25, 38), rough=0.55)
GOLD = pmat('Buckle gold', (230, 176, 84), rough=0.22, metal=1.0)
SILVER = pmat('Grommet silver', (200, 200, 210), rough=0.3, metal=1.0)
TOON = next(m for m in bpy.data.materials if 'N00_002_03_Tops_01_CLOTH_02' in m.name and not m.name.startswith('MToon Outline'))

def rgb_to_hsv(c):
    mx = c.max(1); mn = c.min(1); d = mx - mn; h = np.zeros_like(mx)
    m = d > 1e-6; r, g, b = c[:, 0], c[:, 1], c[:, 2]
    i = m & (mx == r); h[i] = ((g - b)[i] / d[i]) % 6
    i = m & (mx == g); h[i] = (b - r)[i] / d[i] + 2
    i = m & (mx == b); h[i] = (r - g)[i] / d[i] + 4
    return h / 6, np.where(mx > 0, d / np.maximum(mx, 1e-6), 0), mx
def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6).astype(int) % 6; f = h * 6 - np.floor(h * 6)
    p_, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    out = np.stack([np.choose(i, [v, q, p_, p_, t, v]), np.choose(i, [t, v, v, q, p_, p_]), np.choose(i, [p_, p_, t, v, v, q])], 1)
    return out
def hue_shift(key, dh, sat=1.0, val=1.0, flat=0.0):
    done = set()
    for m in bpy.data.materials:
        if key in m.name and m.node_tree:
            img = lit_image(m)
            if not img or img.name in done: continue
            done.add(img.name)
            px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
            h, s, v = rgb_to_hsv(px[:, :3]); v = v * (1 - flat) + flat * v[px[:, 3] > 0.5].mean(); px[:, :3] = hsv_to_rgb((h + dh / 360) % 1, np.clip(s * sat, 0, 1), np.clip(v * val, 0, 1))
            img.pixels[:] = px.ravel(); img.pack(); print('HUE', key, img.name, dh, sat, val)

# ------------------------------------------------------------------ helpers for new, rigged pieces
def darkest_uv(mat):
    img = lit_image(mat); W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    lum = px[..., :3].mean(-1) + (px[..., 3] < 0.9) * 9
    y, x = np.unravel_index(np.argmin(lum), lum.shape); return ((x + 0.5) / W, (y + 0.5) / H)
def rigged(name, bm, mat, bone, uv=None):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for poly in me.polygons: poly.use_smooth = True
    ob = bpy.data.objects.new(name, me); coll.objects.link(ob); me.materials.append(mat)
    if mat is TOON or uv is not None:
        lay = me.uv_layers.new(name='UV')
        for d in lay.data: d.uv = uv if uv is not None else TOON_UV
    vg = ob.vertex_groups.new(name=bone); vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
    ob.parent = arm; mod = ob.modifiers.new('Armature', 'ARMATURE'); mod.object = arm
    return ob
def ring(bm, center, rx, ry, z0, z1, n=64, flare=0.0, scallop=0.0, cap=True):
    """Open band between heights z0 (bottom) and z1 (top); bottom edge flares outward by `flare`."""
    top, bot = [], []
    for i in range(n):
        t = 2 * math.pi * i / n; c, s = math.cos(t), math.sin(t)
        sc = 1 + (scallop * (0.5 + 0.5 * math.cos(t * n / 4)) if scallop else 0)
        top.append(bm.verts.new((center.x + rx * c, center.y + ry * s, z1)))
        bot.append(bm.verts.new((center.x + (rx + flare * sc) * c, center.y + (ry + flare * sc) * s, z0 - scallop * 0.01 * math.cos(t * n / 4))))
    for i in range(n):
        j = (i + 1) % n; bm.faces.new((bot[i], bot[j], top[j], top[i]))
    return top, bot

# ------------------------------------------------------------------ 1. colours
hue_shift('N00_007_01_Tops_01_CLOTH', 0, sat=0.0, flat=0.6)
tint('N00_007_01_Tops_01_CLOTH', (48, 46, 66))            # blouse: slate navy
tint('N00_002_03_Tops_01_CLOTH_01', (34, 32, 48))         # skirt
tint('N00_002_03_Tops_01_CLOTH_02', (30, 28, 40), 0.5)    # corset
hue_shift('Hair_00_HAIR', -12, sat=0.80, val=1.32)        # yellow -> honey blonde
hue_shift('EyeIris_00_EYE', 22, sat=0.5, val=1.3)          # lighter, greyer blue-violet        # vivid blue -> blue-violet
WARM = (0.98, 0.80, 0.72)
for m in bpy.data.materials:        # face: warm through the lit colour (nothing dark on it)
    if 'Face_00_SKIN' in m.name and m.node_tree and mtoon(m): mtoon(m).inputs['Lit Color'].default_value = (*WARM, 1.0)
done_ = set()
for m in bpy.data.materials:        # body: warm only the light texels - the gloves are painted dark grey into this texture
    if 'Body_00_SKIN' in m.name and m.node_tree and mtoon(m):
        img = lit_image(m)
        if img and img.name not in done_:
            done_.add(img.name); px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
            w = np.clip((px[:, :3].mean(1) - 0.35) / 0.35, 0, 1)[:, None]
            px[:, :3] *= 1 - w * (1 - np.array(WARM, dtype=np.float32)); img.pixels[:] = px.ravel(); img.pack()
        mtoon(m).inputs['Lit Color'].default_value = (1, 1, 1, 1)

TOON_UV = darkest_uv(TOON); print('TOON UV', TOON_UV)

# ------------------------------------------------------------------ 2. body mesh surgery
me = body.data; bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table()
dl = bm.verts.layers.deform.active
def mats(*keys): return {i for i, m in enumerate(me.materials) if m and any(k in m.name for k in keys)}
BLOUSE = mats('N00_007_01_Tops_01_CLOTH'); SKIRT = mats('N00_002_03_Tops_01_CLOTH_01')
PETTI = mats('N00_002_03_Tops_01_CLOTH_03'); CORSET = mats('N00_002_03_Tops_01_CLOTH_02'); TIE = mats('Accessory_Tie')
SKIRT_TOP = max(v.co.z for f in bm.faces if f.material_index in SKIRT for v in f.verts)
UA = B['J_Bip_L_UpperArm']; X0 = UA.head_local.x; AXY, AXZ = UA.head_local.y, UA.head_local.z
kill = []
for f in bm.faces:
    c = f.calc_center_median()
    if f.material_index in BLOUSE:
        along = abs(c.x) - X0
        if not a.vroid_sleeves and along > -0.01 and c.z > AXZ - 0.07: kill.append(f)   # VRoid's sleeve: its front was erased in VRoid; own sleeves are built below
        elif along > a.sleeve_end or (along < a.sleeve_start and c.z > a.neckline and (c.y < 0.04 or along > -0.03)): kill.append(f)   # keep the upper-back panel: VRoid built no skin under it; the shoulder is covered by the rebuilt arm
    elif f.material_index in PETTI or f.material_index in TIE: kill.append(f)
    elif f.material_index in CORSET and c.z < SKIRT_TOP - 0.035: kill.append(f)
bmesh.ops.delete(bm, geom=kill, context='FACES'); print('CUT', len(kill), 'faces')
if a.underbust:
    src = me.materials[min(CORSET)]; bod = src.copy(); bod.name = 'Bodice navy'
    img = lit_image(bod).copy(); img.name = 'Bodice flat'
    fpx = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4); h_, s_, v_ = rgb_to_hsv(fpx[:, :3])
    v_ = v_ * 0.08 + 0.92 * v_[fpx[:, 3] > 0.5].mean(); fpx[:, :3] = hsv_to_rgb(h_, s_ * 0.3, v_)   # soft blouse: drop the corset seams; img.pixels[:] = fpx.ravel(); img.pack()
    old_img = lit_image(src)
    for n_ in bod.node_tree.nodes:
        if n_.type == 'TEX_IMAGE' and n_.image == old_img: n_.image = img
    mean = image_mean_linear(img)
    f_ = [min(1.0, t / max(1e-4, c)) for t, c in zip(srgb((50, 48, 70)), mean)]
    mtoon(bod).inputs['Lit Color'].default_value = (*f_, 1.0)
    if 'Shade Color' in mtoon(bod).inputs: mtoon(bod).inputs['Shade Color'].default_value = (*[c * 0.45 for c in f_], 1.0)
    me.materials.append(bod); BOD_I = len(me.materials) - 1; nb = 0
    for f in bm.faces:
        if f.material_index in CORSET and f.calc_center_median().z > a.underbust: f.material_index = BOD_I; nb += 1
    print('BODICE', nb, 'faces navy above', a.underbust)
    top_e = [] if a.blouse else [e for e in bm.edges if e.is_boundary and e.link_faces and e.link_faces[0].material_index == BOD_I and min(v.co.z for v in e.verts) > 1.24 + DZ]
    if top_e:
        ret = bmesh.ops.extrude_edge_only(bm, edges=top_e); nv = [g for g in ret['geom'] if isinstance(g, bmesh.types.BMVert)]
        for i, v in enumerate(sorted(nv, key=lambda v: v.co.x)):
            out = Vector((v.co.x * 0.4, v.co.y - 0.02 - 0.5, 0)).normalized()
            v.co += (Vector((0, 0, 1)) * 0.75 + out * 0.65).normalized() * 0.020 * (1.0 + 0.25 * math.sin(v.co.x * 260)) + out * 0.004 * math.cos(v.co.x * 260)
        for g in ret['geom']:
            if isinstance(g, bmesh.types.BMFace): g.material_index = BOD_I; g.smooth = True
        print('RUFFLE', len(top_e), 'edges on the bodice top')
# puff the remaining sleeve: bulge away from the arm axis, most at the middle of the sleeve
sleeve = [v for v in {v for f in bm.faces if f.material_index in BLOUSE for v in f.verts}
          if a.sleeve_start - 0.01 < abs(v.co.x) - X0 < a.sleeve_end + 0.01]
def slice_centre(vs, x, w=0.012):
    sl = [q for q in vs if abs(q.co.x - x) < w] or vs
    return sum(q.co.y for q in sl) / len(sl), sum(q.co.z for q in sl) / len(sl)
centres = {v: slice_centre(sleeve, v.co.x) for v in sleeve}
SLEEVE_AXIS = {}
for side in (1, -1):
    sv = [v for v in sleeve if side * v.co.x > X0 + 0.008 and math.hypot(v.co.y - AXY, v.co.z - AXZ) < 0.075]
    SLEEVE_AXIS[side] = [(side * x, *slice_centre(sv, side * x)) for x in np.linspace(X0 + a.sleeve_start, X0 + a.sleeve_end, 8)] if sv else []
if not a.vroid_sleeves:
    sleeve = []; SLEEVE_AXIS = {1: [(X0, AXY, AXZ)], -1: [(X0, AXY, AXZ)]}
for v in sleeve:
    along = abs(v.co.x) - X0; cy_, cz_ = centres[v]
    u = min(1, max(0, (along - a.sleeve_start) / (a.sleeve_end - a.sleeve_start)))
    k = 1 + a.puff * math.sin(math.pi * u) ** 0.8
    v.co.y = cy_ + (v.co.y - cy_) * k; v.co.z = cz_ + (v.co.z - cz_) * k
# arm skin: VRoid culls the body under clothing, so the upper arm and elbow have no skin once the
# sleeve is short. Rebuild a tube from inside the puff to the forearm's open edge, weighted across the elbow.
SKIN = mats('Body_00_SKIN'); uvl = bm.loops.layers.uv.active; OWN_SLEEVES = []
arm_skin = me.materials[min(SKIN)].copy(); arm_skin.name = 'Arm skin (no outline)'   # outlines are per-material modifiers
me.materials.append(arm_skin); ARM_I = len(me.materials) - 1
skin_uv = None
for side, tag in ((1, 'L'), (-1, 'R')):
    ua, la = B['J_Bip_%s_UpperArm' % tag], B['J_Bip_%s_LowerArm' % tag]
    ay, az, elbow = ua.head_local.y, ua.head_local.z, abs(la.head_local.x)
    gu, gl = body.vertex_groups['J_Bip_%s_UpperArm' % tag].index, body.vertex_groups['J_Bip_%s_LowerArm' % tag].index
    gs = body.vertex_groups['J_Bip_%s_Shoulder' % tag].index
    ringv = {v for e in bm.edges if e.is_boundary and e.link_faces and e.link_faces[0].material_index in SKIN for v in e.verts
             if 0.38 < side * v.co.x < 0.47 and math.hypot(v.co.y - ay, v.co.z - az) < 0.07}
    if len(ringv) < 6: print('ARM', tag, 'no forearm edge found'); continue
    xr = sum(side * v.co.x for v in ringv) / len(ringv)
    ey, ez = sum(v.co.y for v in ringv) / len(ringv), sum(v.co.z for v in ringv) / len(ringv)
    ang = sorted((math.atan2(v.co.z - ez, v.co.y - ey), math.hypot(v.co.y - ey, v.co.z - ez)) for v in ringv)
    def R(t):
        for (t0, r0_), (t1, r1_) in zip(ang, ang[1:] + [(ang[0][0] + 2 * math.pi, ang[0][1])]):
            if t0 <= t <= t1: return r0_ + (r1_ - r0_) * (t - t0) / max(1e-6, t1 - t0)
        return ang[0][1]
    if skin_uv is None:
        simg = lit_image(me.materials[min(SKIN)]); SW, SH = simg.size
        spx = np.array(simg.pixels[:], dtype=np.float32).reshape(SH, SW, 4)
        for f in bm.faces:
            if f.material_index in SKIN and 0.45 < side * f.calc_center_median().x < 0.52:
                uv = sum((l[uvl].uv for l in f.loops), Vector((0, 0))) / len(f.loops)
                t_ = spx[int(uv.y * SH) % SH, int(uv.x * SW) % SW]
                if t_[3] > 0.95 and t_[:3].mean() > 0.75: skin_uv = uv; break
        print('SKIN UV', skin_uv)
    shv = [v for v in {v for e in bm.edges if e.is_boundary and e.link_faces and e.link_faces[0].material_index in SKIN for v in e.verts}
           if 0.08 < side * v.co.x < 0.145 and math.hypot(v.co.y - ay, v.co.z - az) < 0.075]
    x0, rsh, N, M = X0 - 0.030, 0.037, 24, 24          # start over the shoulder top: VRoid left no skin under the sleeve there
    axis = SLEEVE_AXIS.get(side) or [(X0, ey, ez)]
    xs_end, ys_end, zs_end = axis[-1]
    def centre_at(x):   # sleeve centre line inside the sleeve, then straight to the forearm edge's centre
        if x <= axis[0][0]: return axis[0][1], axis[0][2]
        for (x1, y1, z1), (x2, y2, z2) in zip(axis, axis[1:]):
            if x1 <= x <= x2: t_ = (x - x1) / max(1e-6, x2 - x1); return y1 + (y2 - y1) * t_, z1 + (z2 - z1) * t_
        t_ = (x - xs_end) / max(1e-6, xr - xs_end); return ys_end + (ey - ys_end) * t_, zs_end + (ez - zs_end) * t_
    sy, sz = centre_at(X0)
    rings = []
    for j in range(M + 1):
        t = j / M; x = x0 + (xr - x0) * t; row = []; ay, az = centre_at(x)
        for i in range(N):
            th = -math.pi + 2 * math.pi * i / N; tt = min(1.0, max(0.0, (x - X0 - 0.004) / (xr - X0 - 0.004))); r = (rsh * (0.55 + 0.45 * min(1.0, max(0.0, (x - x0) / (X0 - x0)))) if x < X0 else 0.034) * (1 - tt) + R(th) * tt; xx = x   # tapered start hides inside the shoulder
            v = bm.verts.new((side * xx, ay + r * math.cos(th), az + r * math.sin(th)))
            wl = min(1, max(0, (x - (elbow - 0.03)) / 0.06))               # upper arm -> forearm across the elbow
            wa = min(1, max(0, (x - (X0 - 0.01)) / 0.035))                 # shoulder -> upper arm across the joint
            if wa < 1: v[dl][gs] = 1 - wa
            if wa * (1 - wl) > 0: v[dl][gu] = wa * (1 - wl)
            if wl > 0: v[dl][gl] = wl
            row.append(v)
        rings.append(row)
    for j in range(M):
        for i in range(N):
            k = (i + 1) % N; f = bm.faces.new((rings[j][i], rings[j][k], rings[j + 1][k], rings[j + 1][i]))
            f.material_index = ARM_I; f.smooth = True; f.normal_update(); c = f.calc_center_median()
            if f.normal.dot(Vector((0, c.y - (sy + ey) / 2, c.z - (sz + ez) / 2))) < 0: f.normal_flip()
            for l in f.loops: l[uvl].uv = skin_uv
    print('ARM', tag, 'rebuilt x %.3f -> %.3f  centre (%.3f,%.3f)->(%.3f,%.3f)' % (x0, xr, sy, sz, ey, ez))
    if not a.vroid_sleeves:
        OWN_SLEEVES.append((side, tag, centre_at))

def mid_texel(mat):
    img = lit_image(mat); W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4); op = px[..., 3] > 0.9
    lum = np.abs(px[..., :3].mean(-1) - px[..., :3].mean(-1)[op].mean()) + (~op) * 9
    y, x = np.unravel_index(np.argmin(lum), lum.shape); return ((x + 0.5) / W, (y + 0.5) / H)
SLEEVE_MAT = me.materials[BOD_I] if a.underbust else me.materials[min(BLOUSE)]
SLEEVE_UV = mid_texel(SLEEVE_MAT)
if not a.vroid_sleeves and a.underbust:   # what is left of VRoid's blouse is its upper-back panel: make it the blouse navy
    nbp = 0
    for f in bm.faces:
        if f.material_index in BLOUSE:
            f.material_index = BOD_I; nbp += 1
            for l in f.loops: l[uvl].uv = SLEEVE_UV
    print('BACK PANEL', nbp, 'faces -> blouse navy')
for side, tag, centre_at in OWN_SLEEVES:
    sb = bmesh.new(); s0, s1 = X0 + a.sleeve_start, X0 + a.sleeve_end; NS, MS = 40, 22; rows_ = []
    for j in range(MS + 1):
        u = j / MS; x = s0 + (s1 - s0) * u; cy2, cz2 = centre_at(x); row = []
        bulge = math.sin(math.pi * u ** 1.35) ** 0.8                       # fullest two-thirds down, like a gathered sleeve
        for i in range(NS):
            th = -math.pi + 2 * math.pi * i / NS
            r = 0.040 + a.puff_r * bulge
            r *= 1 + 0.06 * math.sin(14 * th + 0.4 * j) * bulge ** 0.5          # gathers
            row.append(sb.verts.new((side * x, cy2 + r * math.cos(th), cz2 + r * math.sin(th))))
        rows_.append(row)
    for j in range(MS):
        for i in range(NS):
            k = (i + 1) % NS; f = sb.faces.new((rows_[j][i], rows_[j][k], rows_[j + 1][k], rows_[j + 1][i])); f.normal_update()
            c = f.calc_center_median(); cy2, cz2 = centre_at(side * c.x)
            if f.normal.dot(Vector((0, c.y - cy2, c.z - cz2))) < 0: f.normal_flip()
    for row, sgn, w in ((rows_[0], -1, 0.022), (rows_[-1], 1, 0.012)):          # frill on the off-shoulder line and on the cuff
        edges = [e for e in sb.edges if all(v in set(row) for v in e.verts)]
        ret = bmesh.ops.extrude_edge_only(sb, edges=edges)
        for g in (g for g in ret['geom'] if isinstance(g, bmesh.types.BMVert)):
            cy2, cz2 = centre_at(side * g.co.x); rad_ = Vector((0, g.co.y - cy2, g.co.z - cz2)); th_ = math.atan2(rad_.z, rad_.y)
            rad_.normalize()                                                             # soft gathered ruffle, not saw teeth
            g.co += (Vector((side * sgn * 0.55, 0, 0)) + rad_ * 0.85).normalized() * w * (1.0 + 0.22 * math.sin(11 * th_)) + rad_ * 0.004 * math.cos(11 * th_)
    for f in sb.faces: f.smooth = True
    rigged('Sleeve ' + tag, sb, SLEEVE_MAT, 'J_Bip_%s_UpperArm' % tag, uv=SLEEVE_UV)
    print('SLEEVE', tag, 'x %.3f -> %.3f' % (s0, s1))

for side, tag in ((1, 'L'), (-1, 'R')):
    ul = B['J_Bip_%s_UpperLeg' % tag]; hx, hy = ul.head_local.x, ul.head_local.y
    for v in {v for f in bm.faces if f.material_index in SKIN for v in f.verts}:
        z0_, z1_ = B['J_Bip_%s_LowerLeg' % tag].head_local.z - 0.16, B['J_Bip_%s_UpperLeg' % tag].head_local.z - 0.01
        if side * v.co.x > 0.01 and z0_ < v.co.z < z1_:
            u = (v.co.z - z0_) / (z1_ - z0_); k = 1 + a.thigh * math.sin(math.pi * u) ** 1.5 * (1 - 0.5 * u)
            v.co.x = hx + (v.co.x - hx) * k; v.co.y = hy + (v.co.y - hy) * k

# frill: extrude the cut edges of the blouse outward
def frill(edges, out, width, zig):
    if not edges: return
    src = {v for e in edges for v in e.verts}
    ret = bmesh.ops.extrude_edge_only(bm, edges=edges)
    new = [e for e in ret['geom'] if isinstance(e, bmesh.types.BMVert)]
    for i, v in enumerate(sorted(new, key=lambda v: math.atan2(v.co.y, v.co.x) + v.co.x)):
        d = out(v); v.co += d * width * (1.0 + zig * (1 if i % 2 else -1))
    print('FRILL', len(edges), 'edges')
bnd = [e for e in bm.edges if e.is_boundary and e.link_faces and e.link_faces[0].material_index in BLOUSE]
def mid(e): return (e.verts[0].co + e.verts[1].co) / 2
neck_e = [e for e in bnd if (abs(mid(e).x) - X0 < a.sleeve_start + 0.012 and abs(mid(e).z - a.neckline) < 0.035 and mid(e).y < 0.06)
          or (a.vroid_sleeves and abs(abs(mid(e).x) - X0 - a.sleeve_start) < 0.015)]
cuff_e = [e for e in bnd if abs(abs(mid(e).x) - X0 - a.sleeve_end) < 0.02]
def neck_out(v):   # up and outward from the body
    r = Vector((v.co.x, v.co.y - 0.0, 0)).normalized(); return (Vector((0, 0, 1)) * 0.8 + r * 0.6).normalized()
def cuff_out(v):
    s = 1 if v.co.x > 0 else -1; rad = Vector((0, v.co.y - AXY, v.co.z - AXZ)).normalized()
    return (Vector((s, 0, 0)) * 0.7 + rad * 0.7).normalized()
frill(neck_e, neck_out, 0.026, 0.5); frill(cuff_e, cuff_out, 0.014, 0.35)

# skirt: two layers of knife pleats with handkerchief points and double piping, flaring from the belt
sk_faces = [f for f in bm.faces if f.material_index in SKIRT]
bmesh.ops.subdivide_edges(bm, edges=list({e for f in sk_faces for e in f.edges}), cuts=a.skirt_cuts, use_grid_fill=True)
sk_faces = [f for f in bm.faces if f.material_index in SKIRT]
sk_verts = list({v for f in sk_faces for v in f.verts})
ztop = max(v.co.z for v in sk_verts); zbot = min(v.co.z for v in sk_verts)
cy = sum(v.co.y for v in sk_verts if v.co.z > ztop - 0.02) / max(1, len([v for v in sk_verts if v.co.z > ztop - 0.02]))
def rad(v): return math.hypot(v.co.x, v.co.y - cy)
bins = [[] for _ in range(21)]
for v in sk_verts: bins[min(20, int(20 * (ztop - v.co.z) / (ztop - zbot)))].append(rad(v))
prof = [sum(b) / len(b) if b else None for b in bins]
for i in range(21):
    if prof[i] is None: prof[i] = prof[i - 1]
r0 = prof[0]
def pleat(th, phase):          # knife pleat: slow rise, sharp fold, in [-0.5, 0.5]
    f = ((a.pleats * th + phase) / (2 * math.pi)) % 1.0     # rounded pleats: a sawtooth shows as teeth on the silhouette
    return 0.5 * math.sin(2 * math.pi * f) + 0.12 * math.sin(4 * math.pi * f)
def remap(verts, lenfac, roff, phase=0.0):
    for v in verts:
        s = (ztop - v.co.z) / (ztop - zbot); s = min(1, max(0, s))
        th = math.atan2(v.co.y - cy, v.co.x)
        L = a.skirt_len * (1 + a.skirt_points * abs(math.sin(3 * th)) ** 5)   # points at centre front and front-sides
        depth = s * L * lenfac
        target = r0 + (a.skirt_hem - r0) * min(1.2, depth / a.skirt_len) ** a.skirt_flare + roff * s ** 0.6
        target += a.pleat_depth * (0.25 + 0.75 * s) * pleat(th, phase)
        k = target / float(np.interp(s * 20, np.arange(21), prof))   # interpolated: a stepped profile shows as ridges once subdivided
        v.co.x *= k; v.co.y = cy + (v.co.y - cy) * k; v.co.z = ztop - depth
tiers = [(sk_verts, 1.0, 0.0)]
for lenfac, roff in ((0.80, 0.014),):
    ret = bmesh.ops.duplicate(bm, geom=sk_faces + list({e for f in sk_faces for e in f.edges}) + sk_verts)
    tiers.append(([g for g in ret['geom'] if isinstance(g, bmesh.types.BMVert)], lenfac, roff))
hems = []
for vs, lenfac, roff in tiers:
    vset = set(vs); spre = {v: (ztop - v.co.z) / (ztop - zbot) for v in vs}
    hems.append([e for e in bm.edges if e.is_boundary and all(v in vset and spre[v] > 0.85 for v in e.verts)])
for ti, (vs, lenfac, roff) in enumerate(tiers): remap(vs, lenfac, roff, phase=0.0)   # pleats in step, so the outer layer nests over the inner
# plain fabric: a flattened copy of the skirt texture (drops the buttons and panel seams)
skm = me.materials[min(SKIRT)]; simg = lit_image(skm); fimg = simg.copy(); fimg.name = 'Skirt flat'
fpx = np.array(fimg.pixels[:], dtype=np.float32).reshape(-1, 4); h_, s_, v_ = rgb_to_hsv(fpx[:, :3]); op = fpx[:, 3] > 0.5
v_ = v_ * 0.3 + 0.7 * v_[op].mean(); fpx[:, :3] = hsv_to_rgb(h_, s_ * 0.5, v_); fimg.pixels[:] = fpx.ravel(); fimg.pack()
for n_ in skm.node_tree.nodes:
    if n_.type == 'TEX_IMAGE' and n_.image == simg: n_.image = fimg
def texel_uv(mat, target):
    img = lit_image(mat); W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    lum = np.abs(px[..., :3].mean(-1) - target) + (px[..., 3] < 0.9) * 9
    y, x = np.unravel_index(np.argmin(lum), lum.shape); return ((x + 0.5) / W, (y + 0.5) / H)
TRIM_UV = texel_uv(me.materials[min(CORSET)], 0.75)
trim = me.materials[min(CORSET)].copy(); trim.name = 'Skirt trim navy'
_ti = lit_image(trim); _tw, _th = _ti.size; _tp = np.array(_ti.pixels[:], dtype=np.float32).reshape(_th, _tw, 4)
_tc = _tp[int(TRIM_UV[1] * _th), int(TRIM_UV[0] * _tw), :3]; _tc = np.where(_tc <= 0.04045, _tc / 12.92, ((_tc + 0.055) / 1.055) ** 2.4)
tf = [min(1.0, t / max(1e-4, c)) for t, c in zip(srgb(tuple(a.piping)), _tc)]   # scale against the texel the piping samples
mtoon(trim).inputs['Lit Color'].default_value = (*tf, 1.0)
if 'Shade Color' in mtoon(trim).inputs: mtoon(trim).inputs['Shade Color'].default_value = (*[c * 0.5 for c in tf], 1.0)
me.materials.append(trim); CORSET_I = len(me.materials) - 1; nt = 0
SLOPE = (a.skirt_hem - r0) / a.skirt_len * 0.6
def band(edges, up, width):
    """A piping strip on the skirt surface, `up` metres above the hem, `width` tall."""
    global nt
    geom = list({v for e in edges for v in e.verts}) + edges
    ret = bmesh.ops.duplicate(bm, geom=geom); dup = [g for g in ret['geom'] if isinstance(g, bmesh.types.BMEdge)]
    for g in ret['geom']:
        if isinstance(g, bmesh.types.BMVert):
            r = math.hypot(g.co.x, g.co.y - cy); k = (r - up * SLOPE + 0.0025) / max(r, 1e-4)
            g.co.x *= k; g.co.y = cy + (g.co.y - cy) * k; g.co.z += up
    ret = bmesh.ops.extrude_edge_only(bm, edges=dup)
    for g in ret['geom']:
        if isinstance(g, bmesh.types.BMVert):
            r = math.hypot(g.co.x, g.co.y - cy); k = (r - width * SLOPE) / max(r, 1e-4)
            g.co.x *= k; g.co.y = cy + (g.co.y - cy) * k; g.co.z += width
        elif isinstance(g, bmesh.types.BMFace):
            g.material_index = CORSET_I; g.smooth = True; nt += 1
            for l in g.loops: l[uvl].uv = TRIM_UV
RUF_UV = mid_texel(me.materials[min(SKIRT)])
def ruffle(edges, drop, gathers):
    """A gathered frill hanging below a hem: duplicated hem edge, extruded down and out, rippled."""
    global nt
    geom = list({v for e in edges for v in e.verts}) + edges
    ret = bmesh.ops.duplicate(bm, geom=geom); dup = [g for g in ret['geom'] if isinstance(g, bmesh.types.BMEdge)]
    for g in ret['geom']:
        if isinstance(g, bmesh.types.BMVert):   # tuck the frill's top just inside the hem
            r = math.hypot(g.co.x, g.co.y - cy); k = (r - 0.002) / max(r, 1e-4); g.co.x *= k; g.co.y = cy + (g.co.y - cy) * k; g.co.z += 0.004
    ret = bmesh.ops.extrude_edge_only(bm, edges=dup)
    for g in ret['geom']:
        if isinstance(g, bmesh.types.BMVert):
            th = math.atan2(g.co.y - cy, g.co.x); r = math.hypot(g.co.x, g.co.y - cy)
            k = (r + drop * 0.55 + 0.007 * math.sin(gathers * th)) / max(r, 1e-4)
            g.co.x *= k; g.co.y = cy + (g.co.y - cy) * k; g.co.z -= drop
        elif isinstance(g, bmesh.types.BMFace):
            g.material_index = min(SKIRT); g.smooth = True; nt += 1
            for l in g.loops: l[uvl].uv = RUF_UV
for edges in hems:
    if not edges: continue
    ruffle(edges, a.ruffle, 90)
    band(edges, 0.0, 0.005); band(edges, 0.012, 0.003); band(edges, 0.022, 0.003)
print('TRIM faces', nt)
print('SKIRT top %.3f bot %.3f r0 %.3f cy %.3f' % (ztop, zbot, r0, cy))
bm.to_mesh(me); me.update()

# soft blouse: a fitted tube over the upper torso from under the corset's top edge to a straight
# off-shoulder neckline with a ruffle (the VRoid corset's sweetheart edge, busk and ornament show otherwise)
if a.blouse and a.underbust:
    zb0 = a.underbust; zn = AXZ - a.neckline_drop
    keep = set().union(CORSET, BLOUSE, {BOD_I}, mats('Body_00_SKIN'))
    src = sorted({i for p_ in me.polygons if p_.material_index in keep for i in p_.vertices
                  if abs(me.vertices[i].co.x) < X0 - 0.005 and zb0 - 0.02 < me.vertices[i].co.z < zn + 0.02})
    cyB = sum(me.vertices[i].co.y for i in src) / len(src)
    NB, rows_z = 72, list(np.arange(zb0, zn + 1e-6, 0.006))
    R = np.zeros((len(rows_z), NB))
    for ri, zr in enumerate(rows_z):
        pts = [me.vertices[i].co for i in src if abs(me.vertices[i].co.z - zr) < 0.012]
        ang = np.array([math.atan2(q.y - cyB, q.x) for q in pts]); rad = np.array([math.hypot(q.x, q.y - cyB) for q in pts])
        for k in range(NB):
            th = -math.pi + 2 * math.pi * k / NB; dth = np.abs((ang - th + math.pi) % (2 * math.pi) - math.pi)
            sel = rad[dth < 0.2]; R[ri, k] = sel.max() if len(sel) else np.nan
        row = R[ri]; good = ~np.isnan(row)
        R[ri] = np.interp(np.arange(NB), np.arange(NB)[good], row[good], period=NB) if good.any() else R[ri - 1]
    for _ in range(2):   # smooth around and up
        R = (np.roll(R, 1, 1) + 2 * R + np.roll(R, -1, 1)) / 4
        R[1:-1] = (R[:-2] + 2 * R[1:-1] + R[2:]) / 4
    bb2 = bmesh.new(); vrows = []
    for ri, zr in enumerate(rows_z):
        f_ = (zr - zb0) / max(1e-4, zn - zb0); vr = []
        for k in range(NB):
            th = -math.pi + 2 * math.pi * k / NB
            r = R[ri, k] + (0.006 if zr > zb0 + 0.012 else 0.001) + 0.004 * math.sin(20 * th) * f_ ** 1.5   # gathers toward the top
            vr.append(bb2.verts.new((r * math.cos(th), cyB + r * math.sin(th), zr)))
        vrows.append(vr)
    for ri in range(len(vrows) - 1):
        for k in range(NB):
            k2 = (k + 1) % NB; bb2.faces.new((vrows[ri][k], vrows[ri][k2], vrows[ri + 1][k2], vrows[ri + 1][k]))
    top_edges = [e for e in bb2.edges if all(v in set(vrows[-1]) for v in e.verts)]
    ret = bmesh.ops.extrude_edge_only(bb2, edges=top_edges)
    for g in ret['geom']:
        if isinstance(g, bmesh.types.BMVert):
            th = math.atan2(g.co.y - cyB, g.co.x); out = Vector((math.cos(th), math.sin(th), 0))
            g.co += (Vector((0, 0, 1)) * 0.6 + out * 0.8).normalized() * 0.022 * (1 + 0.25 * math.sin(26 * th)) + out * 0.004 * math.cos(26 * th)
    for f in bb2.faces: f.smooth = True
    bme = bpy.data.meshes.new('Blouse'); bb2.to_mesh(bme); bb2.free()
    bob = bpy.data.objects.new('Blouse', bme); coll.objects.link(bob); bme.materials.append(me.materials[BOD_I])
    lay = bme.uv_layers.new(name='UV')
    for d in lay.data: d.uv = SLEEVE_UV
    kdb = KDTree(len(src))
    for n_, i in enumerate(src): kdb.insert(me.vertices[i].co, i)
    kdb.balance()
    for g in body.vertex_groups: bob.vertex_groups.new(name=g.name)
    for v in bme.vertices:
        co_, idx, dist = kdb.find(v.co)
        for gr in me.vertices[idx].groups: bob.vertex_groups[gr.group].add([v.index], gr.weight, 'REPLACE')
    bob.parent = arm; bob.modifiers.new('Armature', 'ARMATURE').object = arm
    print('BLOUSE %d rows, z %.3f -> %.3f' % (len(rows_z), zb0, zn))

# ------------------------------------------------------------------ 3. twin tails
hb = bmesh.new(); hb.from_mesh(hair.data); hb.verts.ensure_lookup_table()
seen = set(); tails = []; bangs = []; crown = []
for v in hb.verts:
    if v.index in seen: continue
    st = [v]; comp = []; seen.add(v.index)
    while st:
        w = st.pop(); comp.append(w)
        for e in w.link_edges:
            o = e.other_vert(w)
            if o.index not in seen: seen.add(o.index); st.append(o)
    zz = [c.co.z for c in comp]
    if min(zz) < 1.2 + DZ and max(zz) - min(zz) > 0.3: tails.append(comp)          # real strands only (tiny cards hide at the chest)
    elif min(zz) > 1.40 + DZ and max(zz) > 1.55 + DZ and sum(c.co.y for c in comp) / len(comp) < -0.02: bangs.append(comp)
    elif min(zz) >= 1.2 + DZ: crown.append(comp)
ZP = a.tail_root or max(c.co.z for comp in tails for c in comp) - 0.04   # where VRoid gathers each tail bundle
a.tail_tip = a.tail_tip or ZP - a.tail_len
print('TAIL ROOT %.3f tip %.3f' % (ZP, a.tail_tip))
TIE = {}
for comp in tails:
    side = 1 if sum(c.co.x for c in comp) > 0 else -1
    TIE.setdefault(side, []).extend([c.co.copy() for c in comp if ZP - 0.02 < c.co.z < ZP + 0.01])
TIE = {k: sum(v, Vector()) / len(v) for k, v in TIE.items() if v}
# Each strand is re-synthesised along a new centre line: kept as-is above the tie, then out and down in
# an arc, cross-section tapering to a point, tip flicked outward. Copies with other spreads and lengths
# fill the bundle out. (Compressing VRoid's long strands instead rolls their flared ends into balls.)
def synth(comp, side, spread, lenf, dy, width):
    T = TIE[side]; below = [c for c in comp if c.co.z < T.z]
    if not below: return
    zmin = min(c.co.z for c in below); D = T.z - zmin
    Z = np.array([c.co.z for c in below]); U = (T.z - Z) / D
    px_ = np.polyfit(U, [c.co.x for c in below], 4); py_ = np.polyfit(U, [c.co.y for c in below], 4)   # smooth centre line
    def cen_at(u): return float(np.polyval(px_, u)), float(np.polyval(py_, u))
    ox0, oy0 = cen_at(0.0)[0] - T.x, cen_at(0.0)[1] - T.y              # the strand's own place in the bundle at the tie
    L = (T.z - a.tail_tip) * lenf
    def centre(u):
        out = spread * math.sin(math.pi * min(1.0, u / 0.8) * 0.5) ** 0.7 * (1 - 0.25 * max(0.0, u - 0.6) / 0.4)
        flick = a.tail_flick * max(0.0, (u - 0.72) / 0.28) ** 2
        wave = a.tail_wave * math.sin(2 * math.pi * 1.2 * u) * u
        return (T.x + ox0 * (1 - 0.3 * u) + side * (out + flick + wave),
                T.y + oy0 * (1 - 0.3 * u) + dy * min(1.0, u / 0.3) + 0.02 * u,
                T.z - L * u + a.tail_lift * math.sin(math.pi * min(1.0, u / 0.45)) * (1 - u))   # puff up out of the tie first
    for c in below:
        d = T.z - c.co.z; u = d / D; cx0, cy0 = cen_at(u)
        w_ = min(1.0, d / 0.04)                                 # blend in just below the tie
        taper = 1.0 if u < 0.5 else max(0.08, 1 - ((u - 0.5) / 0.5) ** 1.3 * 0.92)
        nx, ny, nz = centre(u)
        tx = nx + (c.co.x - cx0) * width * taper; ty = ny + (c.co.y - cy0) * width * taper
        c.co = Vector((c.co.x + (tx - c.co.x) * w_, c.co.y + (ty - c.co.y) * w_, c.co.z + (nz - c.co.z) * w_))
copies = 0; plan = []
for comp in tails:
    side = 1 if sum(c.co.x for c in comp) > 0 else -1
    plan.append((comp, side, a.tail_spread, 1.0, 0.0, a.tail_width))
    if a.tail_fan:
        faces = list({f for v in comp for f in v.link_faces}); edges = list({e for f in faces for e in f.edges})
        for spread, lenf, dy in ((a.tail_spread * 1.45, 0.86, 0.018), (a.tail_spread * 0.55, 1.08, -0.016)):
            ret = bmesh.ops.duplicate(hb, geom=list(comp) + edges + faces)
            plan.append(([g for g in ret['geom'] if isinstance(g, bmesh.types.BMVert)], side, spread, lenf, dy, a.tail_width * 0.9)); copies += 1
for i, (comp, side, spread, lenf, dy, width) in enumerate(plan):
    synth(comp, side, spread * (0.85 + 0.3 * ((i * 7) % 5) / 4), lenf * (0.93 + 0.14 * ((i * 3) % 4) / 3), dy, width)
# fringe longer from its own hairline; the outer pieces much longer, as face-framing locks that clear the cheeks
HC = arm.data.bones['J_Bip_C_Head'].head_local + Vector((0, 0, 0.05))
for comp in bangs:
    top = max(c.co.z for c in comp); mx = sum(c.co.x for c in comp) / len(comp); side = 1 if mx > 0 else -1
    lock = abs(mx) > 0.038; f = a.sidelocks if lock else a.bangs; piv = top - 0.02; low = min(c.co.z for c in comp)
    for c in comp:
        if c.co.z < piv:
            t = (piv - c.co.z) / max(1e-4, piv - low); c.co.z = piv - (piv - c.co.z) * f
            if lock: c.co.x += side * 0.028 * t ** 1.2; c.co.y -= 0.006 * t
        c.co.x *= 1.03
# temple locks: the side pieces in front of the ears run down to the jaw instead of stopping at the cheek
FZ = min(v.co.z for v in bpy.data.objects['Face'].data.vertices) - 0.008; nl = 0
for comp in crown:
    mx = sum(c.co.x for c in comp) / len(comp); my = sum(c.co.y for c in comp) / len(comp); zz = [c.co.z for c in comp]
    if 0.045 < abs(mx) < 0.064 and my < 0.015 and min(zz) > FZ + 0.02 and max(zz) - min(zz) > 0.08:
        side = 1 if mx > 0 else -1; piv = max(zz) - 0.035; low = min(zz); f = (piv - FZ) / max(1e-4, piv - low); nl += 1
        for c in comp:
            if c.co.z < piv:
                t = (piv - c.co.z) / max(1e-4, piv - low); c.co.z = piv - (piv - c.co.z) * f
                c.co.x += side * 0.016 * t ** 1.2; c.co.y -= 0.004 * t
print('TEMPLE LOCKS', nl, 'down to %.3f' % FZ)
for comp in crown:
    for c in comp: c.co = HC + (c.co - HC) * a.crown
hb.to_mesh(hair.data); hair.data.update(); print('TAILS', len(tails), 'strands ->', a.tail_tip, '+', copies, 'fanned copies;', len(bangs), 'bang pieces;', len(crown), 'crown pieces')
hb.free()

# sheer stocking: the reference's dark thigh-high is brown-black with skin showing through
def leg_mask(side, top_z):
    img = lit_image(me.materials[min(mats('Body_00_SKIN'))]); W, H = img.size
    m_ = np.zeros((H, W), dtype=bool); uvd = me.uv_layers.active.data; n = 0; SK = mats('Body_00_SKIN')
    for poly in me.polygons:
        if poly.material_index in SK and side * poly.center.x > 0.01 and 0.18 < poly.center.z < top_z + 0.01:
            pts = [(uvd[li].uv.x * W, uvd[li].uv.y * H) for li in poly.loop_indices]; n += 1
            for k in range(1, len(pts) - 1):                   # fan-triangulate, fill by barycentric test
                (x0, y0), (x1, y1), (x2, y2) = pts[0], pts[k], pts[k + 1]
                xa, xb = int(max(0, min(x0, x1, x2))), int(min(W - 1, max(x0, x1, x2)) + 1)
                ya, yb = int(max(0, min(y0, y1, y2))), int(min(H - 1, max(y0, y1, y2)) + 1)
                if xb <= xa or yb <= ya: continue
                X, Y = np.meshgrid(np.arange(xa, xb) + 0.5, np.arange(ya, yb) + 0.5)
                d = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
                if abs(d) < 1e-9: continue
                l1 = ((y1 - y2) * (X - x2) + (x2 - x1) * (Y - y2)) / d; l2 = ((y2 - y0) * (X - x2) + (x0 - x2) * (Y - y2)) / d
                m_[ya:yb, xa:xb] |= (l1 >= -0.01) & (l2 >= -0.01) & (1 - l1 - l2 >= -0.01)
    return img, m_, n
def sheer_stocking(side, top_z):
    img, m_, n = leg_mask(side, top_z); W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    dark = m_ & (px[..., :3].mean(-1) < 0.35)
    tone = np.array([48, 33, 37], dtype=np.float32) / 255      # image pixels are stored sRGB-encoded
    px[dark, :3] = px[dark, :3] * 0.35 + tone * 0.65
    img.pixels[:] = px.ravel(); img.pack(); print('SHEER', n, 'faces,', int(dark.sum()), 'texels')
    # sheer shading: its own copy of the skin material, whose lit colour follows the view angle -
    # skin shows through where the leg faces you, the nylon doubles up dark at the silhouette
    SK = mats('Body_00_SKIN'); sm = me.materials[min(SK)].copy(); sm.name = 'Sheer stocking'
    me.materials.append(sm); SI = len(me.materials) - 1; nf = 0
    for poly in me.polygons:
        if poly.material_index in SK and side * poly.center.x > 0.01 and 0.18 < poly.center.z < top_z - 0.005: poly.material_index = SI; nf += 1
    nt_ = sm.node_tree; g = mtoon(sm); lw = nt_.nodes.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = 0.35
    cr = nt_.nodes.new('ShaderNodeValToRGB'); cr.color_ramp.elements[0].color = (1.25, 1.12, 1.08, 1); cr.color_ramp.elements[1].color = (0.42, 0.40, 0.42, 1)
    cr.color_ramp.elements[0].position = 0.15; cr.color_ramp.elements[1].position = 0.85
    nt_.links.new(lw.outputs['Facing'], cr.inputs['Fac']); nt_.links.new(cr.outputs['Color'], g.inputs['Lit Color'])
    print('SHEER SHADING', nf, 'faces')
def fine_fishnet(side, top_z, cell, width):
    """Replace the coarse VRoid fishnet with a finer diamond net drawn in the same UV region."""
    img, m_, n = leg_mask(side, top_z); W, H = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    lum = px[..., :3].mean(-1); skin_ = m_ & (lum > 0.6)
    if not skin_.any(): print('FISHNET skipped'); return
    base = np.median(px[skin_][:, :3], axis=0)
    px[m_ & (lum <= 0.6), :3] = base                             # erase the old net
    Y, X = np.mgrid[0:H, 0:W]; c = cell * W / 2048; w = width * W / 2048
    net = m_ & ((((X + Y) % c) < w) | (((X - Y) % c) < w))
    px[net, :3] = np.array([18, 16, 22], dtype=np.float32) / 255
    img.pixels[:] = px.ravel(); img.pack(); print('FISHNET', int(net.sum()), 'texels, cell', cell)

# ------------------------------------------------------------------ 4. accessories
skin = mats('Body_00_SKIN')
skin_v = {i for poly in me.polygons if poly.material_index in skin for i in poly.vertices}
def section(z, pred, pct=0.9):
    pts = [me.vertices[i].co for i in skin_v if abs(me.vertices[i].co.z - z) < 0.006 and pred(me.vertices[i].co)]
    cx = sum(p.x for p in pts) / len(pts); cyy = sum(p.y for p in pts) / len(pts)
    rs = sorted(math.hypot(p.x - cx, p.y - cyy) for p in pts)
    return Vector((cx, cyy, z)), rs[int(pct * (len(rs) - 1))]
# choker: satin band + lace frill
NB_ = B['J_Bip_C_Neck']; zc = NB_.head_local.z + 0.30 * (NB_.tail_local.z - NB_.head_local.z)   # choker follows the neck
cen, r = section(zc, lambda c: abs(c.x) < 0.07 and math.hypot(c.x, c.y - 0.02) < 0.07)
cb = bmesh.new(); ring(cb, cen, r + 0.004, r + 0.004, zc - 0.012, zc + 0.012, n=48)
rigged('Choker', cb, TOON, 'J_Bip_C_Neck')
cf = bmesh.new(); ring(cf, cen, r + 0.005, r + 0.005, zc - 0.030, zc - 0.010, n=64, flare=0.010, scallop=0.35)
rigged('Choker lace', cf, LACE, 'J_Bip_C_Neck'); print('CHOKER r %.3f at' % r, cen)
# belt + gold buckle at the skirt waistband
zb = ztop - 0.012
SKV = {i for p_ in me.polygons if p_.material_index in SKIRT for i in p_.vertices}
CV = {i for p_ in me.polygons if p_.material_index in CORSET for i in p_.vertices}
# the belt follows the corset's real cross-section at its height (an ellipse cuts in at the front)
bpts = [me.vertices[i].co for i in (CV | SKV) if abs(me.vertices[i].co.z - zb) < 0.012]
bc = Vector((0, sum(q.y for q in bpts) / len(bpts), 0))
angs = sorted((math.atan2(q.y - bc.y, q.x), math.hypot(q.x, q.y - bc.y)) for q in bpts)
def belt_r(th, win=0.20):
    near = [r_ for t_, r_ in angs if abs(math.remainder(t_ - th, 2 * math.pi)) < win]
    return (max(near) if near else max(r_ for _, r_ in angs)) + 0.005
bb = bmesh.new(); NB = 72; top_, bot_ = [], []
for i in range(NB):
    th = 2 * math.pi * i / NB; r_ = belt_r(th)
    for lst, dz in ((bot_, -0.009), (top_, 0.009)): lst.append(bb.verts.new((r_ * math.cos(th), bc.y + r_ * math.sin(th), zb + dz)))
for i in range(NB):
    j = (i + 1) % NB; bb.faces.new((bot_[i], bot_[j], top_[j], top_[i]))
rigged('Belt', bb, TOON, 'J_Bip_C_Hips')
ry = belt_r(-math.pi / 2) - 0.001
gb = bmesh.new(); fy = bc.y - ry - 0.002
for (w, h, x0) in ((0.030, 0.024, 0.0),):
    t = 0.005   # frame bars: top, bottom, left, right, centre prong
    for (cx, cz, sx, sz) in ((0, h / 2 - t / 2, w, t), (0, -h / 2 + t / 2, w, t), (-w / 2 + t / 2, 0, t, h), (w / 2 - t / 2, 0, t, h), (0.004, 0, t * 0.8, h * 0.8)):
        m = bmesh.ops.create_cube(gb, size=1.0)['verts']
        for v in m: v.co = Vector((cx + v.co.x * sx, fy - 0.003 + v.co.y * 0.006, zb + cz + v.co.z * sz))
rigged('Belt buckle', gb, GOLD, 'J_Bip_C_Hips')
# stocking bands + bows
def stocking_top():
    if a.stocking_top: return a.stocking_top
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get(), deform=False)
    img = lit_image(me.materials[min(skin)]); W, H = img.size; px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
    uvl = me.uv_layers.active.data; best = 0.62
    from mathutils.geometry import barycentric_transform
    def dark(x, z):
        loc, nrm, fi, dist = bvh.ray_cast(Vector((x, -0.5, z)), Vector((0, 1, 0)))
        if loc is None or me.polygons[fi].material_index not in skin: return False
        poly = me.polygons[fi]; vs = [me.vertices[i].co for i in poly.vertices[:3]]; uvs = [uvl[li].uv for li in poly.loop_indices[:3]]
        uv = barycentric_transform(loc, *vs, *(Vector((q.x, q.y, 0)) for q in uvs))
        return px[int((uv.y % 1) * H) % H, int((uv.x % 1) * W) % W, :3].mean() < 0.35
    for zi in range(0, 40):
        z = 0.55 + DZ * 0.5 + zi * 0.005
        if all(dark(x, z) for x in (-0.105, -0.08, -0.055)): best = z
    return best
zs = stocking_top(); print('STOCKING TOP %.3f' % zs)
sheer_stocking(-1, zs)
if a.fishnet_cell: fine_fishnet(1, zs, a.fishnet_cell, a.fishnet_width)
def bow(bm, at, normal, s=1.0):
    """Satin bow facing `normal`, centred at `at`."""
    zax = Vector((0, 0, 1)); xax = zax.cross(normal).normalized(); yax = normal.normalized()
    def P(x, y, z): return at + xax * x * s + yax * y * s + zax * z * s
    for side in (-1, 1):                                     # two loops, flat against the leg
        top_, bot_ = [], []
        for i in range(28):
            u = 2 * math.pi * i / 28; e = 0.5 - 0.5 * math.cos(u)
            x = side * (0.004 + 0.034 * e); y = 0.010 * math.sin(u) + 0.004 * e; w = 0.004 + 0.011 * e ** 0.8
            top_.append(bm.verts.new(P(x, y, w))); bot_.append(bm.verts.new(P(x, y, -w)))
        for i in range(28):
            j = (i + 1) % 28; bm.faces.new((bot_[i], bot_[j], top_[j], top_[i]))
    for side in (-1, 1):                                     # two tails
        pts = [(side * (0.002 + 0.012 * t), 0.004, -0.004 - 0.034 * t) for t in (0, 0.5, 1.0)]
        ls = [bm.verts.new(P(x - 0.006, y, z)) for x, y, z in pts]; rs = [bm.verts.new(P(x + 0.006, y, z - (0.006 * side if k == 2 else 0))) for k, (x, y, z) in enumerate(pts)]
        for i in range(2): bm.faces.new((ls[i], rs[i], rs[i + 1], ls[i + 1]))
    kn = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=1.0)['verts']
    for v in kn: v.co = P(v.co.x * 0.008, v.co.y * 0.006 + 0.006, v.co.z * 0.009)
for side, bone in ((1, 'J_Bip_L_UpperLeg'), (-1, 'J_Bip_R_UpperLeg')):
    cen, r = section(zs, lambda c, s=side: s * c.x > 0.015 and abs(c.x - s * 0.08) < 0.1)
    sb = bmesh.new(); ring(sb, cen, r + 0.003, r + 0.003, zs - 0.012, zs + 0.012, n=48)
    rigged('Stocking band ' + ('L' if side > 0 else 'R'), sb, TOON, bone)
    lb2 = bmesh.new(); ring(lb2, cen, r + 0.005, r + 0.005, zs + 0.010, zs + 0.030, n=72, flare=0.004, scallop=0.45)
    rigged('Stocking lace ' + ('L' if side > 0 else 'R'), lb2, LACE, bone)
    th = math.radians(-90 + side * 14); nrm = Vector((math.cos(th), math.sin(th), 0))
    bw = bmesh.new(); bow(bw, cen + nrm * (r + 0.010) + Vector((0, 0, 0.006)), nrm, 1.6)
    rigged('Stocking bow ' + ('L' if side > 0 else 'R'), bw, TOON, bone)
# corset lacing: grommets in two columns down the front and a criss-cross ribbon between them
dg_ = bpy.context.evaluated_depsgraph_get(); bvh_c = BVHTree.FromBMesh(bm) if False else None
cor_faces = [p_ for p_ in me.polygons if p_.material_index in CORSET]
if cor_faces:
    from mathutils.bvhtree import BVHTree as _B
    cbvh = _B.FromPolygons([v.co for v in me.vertices], [p_.vertices for p_ in cor_faces])
    zc0 = ztop + 0.012; zc1 = (a.underbust or ztop + 0.10) - 0.004; n_ = 7
    def front(x, z):
        loc, nrm, fi, d = cbvh.ray_cast(Vector((x, -0.6, z)), Vector((0, 1, 0)))
        return (loc + Vector((0, -0.004, 0))) if loc else None
    cols = {sgn: [front(sgn * 0.032, zc0 + (zc1 - zc0) * i / (n_ - 1)) for i in range(n_)] for sgn in (-1, 1)}
    if all(p_ is not None for sgn in cols for p_ in cols[sgn]):
        gb_ = bmesh.new()
        for sgn in cols:
            for c_ in cols[sgn]:
                ring_v = bmesh.ops.create_circle(gb_, cap_ends=False, segments=10, radius=0.0035)['verts']
                inner = bmesh.ops.create_circle(gb_, cap_ends=False, segments=10, radius=0.0018)['verts']
                for v_ in ring_v + inner: v_.co = Vector((c_.x + v_.co.x, c_.y - 0.0005, c_.z + v_.co.y))
                for i_ in range(10): gb_.faces.new((ring_v[i_], ring_v[(i_ + 1) % 10], inner[(i_ + 1) % 10], inner[i_]))
        rigged('Corset grommets', gb_, SILVER, 'J_Bip_C_Spine')
        lb_ = bmesh.new(); w_ = 0.0016
        for i_ in range(n_ - 1):
            for sgn in (-1, 1):
                p0, p1 = cols[sgn][i_], cols[-sgn][i_ + 1]; d_ = (p1 - p0).normalized(); side_ = d_.cross(Vector((0, -1, 0))).normalized() * w_
                q = [lb_.verts.new(p0 - side_ + Vector((0, -0.0015 * (sgn > 0), 0))), lb_.verts.new(p0 + side_ + Vector((0, -0.0015 * (sgn > 0), 0))),
                     lb_.verts.new(p1 + side_ + Vector((0, -0.0015 * (sgn > 0), 0))), lb_.verts.new(p1 - side_ + Vector((0, -0.0015 * (sgn > 0), 0)))]
                lb_.faces.new(q)
        rigged('Corset lacing', lb_, SATIN, 'J_Bip_C_Spine'); print('CORSET LACING', n_, 'rows from %.3f to %.3f' % (zc0, zc1))
    else: print('CORSET LACING skipped: front not found')

# forearm lacing: two crossing helices of black ribbon from the wrist up the forearm
for side, tag in ((1, 'L'), (-1, 'R')):
    fv = [me.vertices[i].co for i in skin_v if 0.40 < side * me.vertices[i].co.x < 0.56 and math.hypot(me.vertices[i].co.y - 0.029, me.vertices[i].co.z - 1.336 - DZ) < 0.07]
    if len(fv) < 20: continue
    def sec(x):
        sl = [q for q in fv if abs(side * q.x - x) < 0.012] or fv
        cy_, cz_ = sum(q.y for q in sl) / len(sl), sum(q.z for q in sl) / len(sl)
        return cy_, cz_, sorted(math.hypot(q.y - cy_, q.z - cz_) for q in sl)[int(0.8 * (len(sl) - 1))]
    lb = bmesh.new()
    for phase in (0.0, math.pi):
        e0, e1 = [], []
        for i in range(90):
            t = i / 89; x = 0.515 - 0.10 * t; th = phase + side * 2 * math.pi * 2.2 * t
            cy_, cz_, rr = sec(x); rr += 0.003
            c_ = Vector((side * x, cy_ + rr * math.cos(th), cz_ + rr * math.sin(th)))
            e0.append(lb.verts.new(c_ + Vector((side * 0.003, 0, 0)))); e1.append(lb.verts.new(c_ - Vector((side * 0.003, 0, 0))))
        for i in range(89): lb.faces.new((e0[i], e0[i + 1], e1[i + 1], e1[i]))
    rigged('Forearm lacing ' + tag, lb, TOON, 'J_Bip_%s_LowerArm' % tag)
# lace bib: a scalloped fall of lace from the choker onto the collarbones, front only
lb = bmesh.new(); cen_c, rc = section(zc, lambda c: abs(c.x) < 0.07 and math.hypot(c.x, c.y - 0.02) < 0.07)
rows = []
for k, (z, r_) in enumerate(((zc - 0.012, rc + 0.006), (zc - 0.029, rc + 0.016), (zc - 0.045, rc + 0.028))):
    row = []
    for i in range(33):
        th = math.radians(-150 + 120 * i / 32); sc_ = 0.006 * (k == 2) * (0.5 + 0.5 * math.cos(i * math.pi / 2))
        row.append(lb.verts.new((cen_c.x + r_ * math.cos(th), cen_c.y + r_ * math.sin(th), z - sc_ - 0.012 * (k == 2) * math.cos(math.radians(-90) - th) ** 8)))
    rows.append(row)
for k in range(2):
    for i in range(32): lb.faces.new((rows[k + 1][i], rows[k + 1][i + 1], rows[k][i + 1], rows[k][i]))
rigged('Lace bib', lb, LACE, 'J_Bip_C_Neck')
hmw = hair.matrix_world
for side, c in TIE.items():
    tb2 = bmesh.new(); ring(tb2, c, 0.030, 0.034, c.z - 0.010, c.z + 0.010, n=32)
    rigged('Hair tie ' + ('L' if side > 0 else 'R'), tb2, TOON, 'J_Bip_C_Head')
if a.arm_out:
    for tag, sgn in (('L', 1), ('R', -1)):
        pb = arm.pose.bones['J_Bip_%s_UpperArm' % tag]; rest = pb.bone.matrix_local.to_3x3()
        R = Matrix.Rotation(math.radians(sgn * (68 - a.arm_out)), 3, 'Y')
        pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = (rest.inverted() @ R @ rest).to_quaternion()
# softer cel shading on every cloth material, so folds and pleats read (VRoid ships 0.95)
nsoft = 0
for m in bpy.data.materials:
    if m.name.startswith('MToon Outline') or not m.node_tree: continue
    if any(k in m.name for k in ('Tops_01_CLOTH', 'Bodice', 'Skirt trim', 'Shoes_01_CLOTH')):
        g = mtoon(m)
        if g and 'Shading Toony' in g.inputs:
            g.inputs['Shading Toony'].default_value = a.cloth_toony; g.inputs['Shading Shift'].default_value = 0.05; nsoft += 1
print('SOFT SHADING on', nsoft, 'materials')
# hair: warm ochre shade and softer cel so clumps and strands read (the reference's hair has deep gold shadows)
for m in bpy.data.materials:
    if 'Hair_00_HAIR' in m.name and not m.name.startswith('MToon Outline') and m.node_tree:
        g = mtoon(m)
        if g:
            g.inputs['Shade Color'].default_value = (*srgb(a.hair_shade), 1.0)
            if 'Shading Toony' in g.inputs: g.inputs['Shading Toony'].default_value = 0.6; g.inputs['Shading Shift'].default_value = 0.15
            print('HAIR SHADE', m.name[:30], a.hair_shade)
# rim light in the material itself (MToon parametric rim, exported with the VRM): warm gold on the
# hair, soft pink on skin, violet on cloth - the backlit glow the reference has on every edge
def rim(keys, rgb, power, lift, mul):
    n_ = 0
    for m in bpy.data.materials:
        if m.name.startswith('MToon Outline') or not m.node_tree or not any(k in m.name for k in keys): continue
        g = mtoon(m)
        if g and 'Parametric Rim Color' in g.inputs:
            g.inputs['Parametric Rim Color'].default_value = (*[c * mul for c in srgb(rgb)], 1.0)
            g.inputs['Parametric Rim Fresnel Power'].default_value = power; g.inputs['Parametric Rim Lift'].default_value = lift; n_ += 1
    return n_
if a.rim:
    print('RIM', rim(('Hair_00_HAIR',), (255, 196, 96), 4.5, 0.0, a.rim * 0.7),
          # no skin rim: VRoid paints the gloves into the skin texture and a rim turns them brown
          rim(('Tops_01_CLOTH', 'Bodice', 'Skirt trim', 'Shoes_01_CLOTH'), (150, 110, 255), 4.0, 0.0, a.rim * 0.5))
# no outline shell on the body skin: VRoid removed the skin under the old collar and sleeves, and the
# inverted-hull outline shows through those gaps as dark red. The reference has no skin contour lines anyway.
for md in list(body.modifiers):
    if md.type == 'NODES' and 'Body_00_SKIN' in md.name: print('OUTLINE removed', md.name); body.modifiers.remove(md)
bpy.ops.wm.save_as_mainfile(filepath=a.out); print('SAVED', a.out)
