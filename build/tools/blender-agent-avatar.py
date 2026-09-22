#!/usr/bin/env python3
"""Render a speaking AI-agent avatar from a VRM model, a voice line and a Rhubarb viseme timeline.

  /snap/bin/blender --factory-startup -b --python build/tools/blender-agent-avatar.py -- \
      --vrm model.vrm --audio line.wav --visemes line-visemes.json --addon-zip VRM_Addon.zip \
      --out DIR [--fps 30 --width 1920 --height 1080] [--stills 8,40,70] [--frames]

The VRM's own lip shapes (lip_a/i/u/e/o or VRoid Fcl_MTH_*) are keyed from Rhubarb's
mouth cues with short transitions; blinks, brow lifts, eye drift and idle head/chest
motion are layered on top. Frames go to DIR/frames/; mux with ffmpeg afterwards.
"""
import bpy, sys, json, math, random, argparse
from pathlib import Path
from mathutils import Vector, Matrix, Euler

p = argparse.ArgumentParser()
p.add_argument('--vrm'); p.add_argument('--blend', help='a prepared scene (e.g. goth.blend) instead of a raw VRM: keeps its pose, lights and Bust camera'); p.add_argument('--audio', required=True); p.add_argument('--visemes', required=True)
p.add_argument('--addon-zip'); p.add_argument('--out', type=Path, required=True)
p.add_argument('--fps', type=int, default=30); p.add_argument('--width', type=int, default=1920); p.add_argument('--height', type=int, default=1080)
p.add_argument('--stills', default=''); p.add_argument('--frames', action='store_true'); p.add_argument('--samples', type=int, default=32)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:]); a.out.mkdir(parents=True, exist_ok=True)
rng = random.Random(7)

# ---------------------------------------------------------------- VRM add-on + import
import addon_utils
if a.addon_zip: bpy.ops.preferences.addon_install(filepath=a.addon_zip, overwrite=True)
mod = [m.__name__ for m in addon_utils.modules() if 'vrm' in m.__name__.lower()][0]
bpy.ops.preferences.addon_enable(module=mod)
PREPARED = bool(a.blend)
if PREPARED: bpy.ops.wm.open_mainfile(filepath=a.blend)
else:
    for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)   # the factory cube, light and camera
    bpy.ops.import_scene.vrm(filepath=a.vrm)
scene = bpy.context.scene; scene.render.fps = a.fps
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
face = [o for o in bpy.data.objects if o.type == 'MESH' and o.data.shape_keys and any(k.name in ('lip_a', 'Face_Blendshape.Fcl_MTH_A') for k in o.data.shape_keys.key_blocks)][0]
keys = face.data.shape_keys.key_blocks
hb = arm.data.vrm_addon_extension.vrm1.humanoid.human_bones
def bone(name): return getattr(hb, name).node.bone_name
HEAD, NECK, CHEST = bone('head'), bone('neck'), bone('chest') or bone('spine')

# ---------------------------------------------------------------- shape-key vocabulary (Seed-san names, VRoid fallbacks)
def K(*names):
    for n in names:
        if n in keys: return n
    return None
LIP = {'a': K('lip_a', 'Face_Blendshape.Fcl_MTH_A'), 'i': K('lip_i', 'Face_Blendshape.Fcl_MTH_I'), 'u': K('lip_u', 'Face_Blendshape.Fcl_MTH_U'),
       'e': K('lip_e', 'Face_Blendshape.Fcl_MTH_E'), 'o': K('lip_o', 'Face_Blendshape.Fcl_MTH_O'), 'closed': K('mouth_short', 'Face_Blendshape.Fcl_MTH_Close')}
BLINK = [k for k in (K('blink_L', 'Face_Blendshape.Fcl_EYE_Close_L'), K('blink_R', 'Face_Blendshape.Fcl_EYE_Close_R')) if k] or [K('eye_close', 'Face_Blendshape.Fcl_EYE_Close')]
BROW = K('eye_brow_up', 'Face_Blendshape.Fcl_BRW_Surprised'); HAPPY = K('face_happy', 'Face_Blendshape.Fcl_ALL_Fun'); SMILE_EYES = K('eye_smile', 'Face_Blendshape.Fcl_EYE_Fun')
LOOK = {'l': K('look_left'), 'r': K('look_right'), 'u': K('look_up'), 'd': K('look_down')}
# Rhubarb mouth shapes -> lip weights. A closed (P/B/M), B teeth apart, C open, D wide, E rounded, F puckered, G F/V, H L, X rest.
SHAPES = {'X': {}, 'A': {'closed': .35}, 'B': {'i': .5}, 'C': {'e': .7}, 'D': {'a': .95}, 'E': {'o': .8}, 'F': {'u': .9}, 'G': {'i': .3, 'u': .25}, 'H': {'e': .4, 'a': .25}}
BASELINE = {HAPPY: .22, SMILE_EYES: .12}

def fr(t): return round(t * a.fps)
def key(name, value, frame):
    if not name: return
    kb = keys[name]; kb.value = value; kb.keyframe_insert('value', frame=frame)

# ---------------------------------------------------------------- pose: arms down from the T-pose, relaxed
arm.rotation_mode = 'XYZ'
def rotate_bone(bname, axis, degrees):
    pb = arm.pose.bones[bname]; rest = pb.bone.matrix_local.to_3x3()
    R = Matrix.Rotation(math.radians(degrees), 3, axis)
    pb.rotation_mode = 'QUATERNION'; pb.rotation_quaternion = (rest.inverted() @ R @ rest).to_quaternion()
if not PREPARED:
  rotate_bone(bone('left_upper_arm'), 'Y', 68); rotate_bone(bone('right_upper_arm'), 'Y', -68)
  rotate_bone(bone('left_lower_arm'), 'Z', 18); rotate_bone(bone('right_lower_arm'), 'Z', -18)
  for side, sgn in (('left', 1), ('right', -1)):
    sh = getattr(hb, side + '_shoulder').node.bone_name
    if sh: rotate_bone(sh, 'Y', sgn * 6)

# ---------------------------------------------------------------- camera, lights, backdrop
if PREPARED:
    scene.camera = bpy.data.objects.get('Bust camera') or scene.camera
else:
    def world_of(bname): return arm.matrix_world @ arm.pose.bones[bname].head
    bpy.context.view_layer.update(); head = world_of(HEAD); chest = world_of(CHEST)
    cam_d = bpy.data.cameras.new('Agent camera'); cam_d.lens = 62; cam = bpy.data.objects.new('Agent camera', cam_d); scene.collection.objects.link(cam)
    aim = head + Vector((0, 0, .01)); cam.location = aim + Vector((.05, -1.62, .02)); cam.rotation_euler = (aim - cam.location).to_track_quat('-Z', 'Y').to_euler(); scene.camera = cam
    def light(name, kind, loc, energy, color, size=1.0, aim_at=None):
        d = bpy.data.lights.new(name, kind); d.energy = energy; d.color = color
        if kind == 'AREA': d.size = size
        o = bpy.data.objects.new(name, d); scene.collection.objects.link(o); o.location = loc
        o.rotation_euler = ((aim_at if aim_at else aim) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler(); return o
    light('Key', 'AREA', aim + Vector((.9, -1.3, .7)), 260, (1, .93, .85), 1.4)
    light('Fill', 'AREA', aim + Vector((-1.2, -1.1, .1)), 70, (.75, .85, 1), 2.0)
    light('Rim cyan', 'AREA', aim + Vector((-1.0, .7, .55)), 1100, (.3, .85, 1), .5)
    light('Rim warm', 'AREA', aim + Vector((1.1, .8, .3)), 120, (1, .6, .4), .6)
    # backdrop: dark gradient plane with a soft cyan halo ring behind her
    bpy.ops.mesh.primitive_plane_add(size=8, location=aim + Vector((0, 2.6, 0)), rotation=(math.radians(90), 0, 0)); bd = bpy.context.object; bd.name = 'Backdrop'
    m = bpy.data.materials.new('Backdrop gradient'); m.use_nodes = True; n, l = m.node_tree.nodes, m.node_tree.links; n.clear()
    out = n.new('ShaderNodeOutputMaterial'); em = n.new('ShaderNodeEmission'); co = n.new('ShaderNodeTexCoord'); grad = n.new('ShaderNodeTexGradient'); grad.gradient_type = 'SPHERICAL'
    mp = n.new('ShaderNodeMapping'); mp.inputs['Location'].default_value = (-.5, -.55, 0); mp.inputs['Scale'].default_value = (1.1, 1.4, 1)
    ramp = n.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].color = (.005, .008, .016, 1); ramp.color_ramp.elements[1].color = (.05, .10, .17, 1)
    l.new(co.outputs['UV'], mp.inputs['Vector']); l.new(mp.outputs[0], grad.inputs['Vector']); l.new(grad.outputs['Fac'], ramp.inputs['Fac']); l.new(ramp.outputs['Color'], em.inputs['Color']); l.new(em.outputs[0], out.inputs['Surface'])
    bd.data.materials.append(m)
    bpy.ops.mesh.primitive_torus_add(major_radius=.55, minor_radius=.010, location=aim + Vector((0, 1.2, .05)), rotation=(math.radians(90), 0, 0)); ring = bpy.context.object; ring.name = 'Halo ring'
    hm = bpy.data.materials.new('Halo cyan'); hm.use_nodes = True; hs = hm.node_tree.nodes['Principled BSDF']; hs.inputs['Emission Color'].default_value = (.25, .8, 1, 1); hs.inputs['Emission Strength'].default_value = 1.6; hs.inputs['Base Color'].default_value = (.05, .3, .4, 1); ring.data.materials.append(hm)
    world = bpy.data.worlds.new('Studio'); scene.world = world; world.use_nodes = True; world.node_tree.nodes['Background'].inputs['Color'].default_value = (.02, .03, .05, 1); world.node_tree.nodes['Background'].inputs['Strength'].default_value = .6


# ---------------------------------------------------------------- lip sync from Rhubarb cues
cues = json.load(open(a.visemes))['mouthCues']; duration = json.load(open(a.visemes))['metadata']['duration']
scene.frame_start = 0; scene.frame_end = fr(duration) + a.fps // 2
lip_names = [v for v in LIP.values() if v]
for kname, v in BASELINE.items(): key(kname, v, 0)
prev = {n: 0.0 for n in lip_names}
TRANS = max(1, round(.07 * a.fps))          # ~70 ms transition into each shape
for c in cues:
    target = {n: 0.0 for n in lip_names}
    for sym, w in SHAPES.get(c['value'], {}).items():
        if LIP[sym]: target[LIP[sym]] = w
    f0 = fr(c['start'])
    for n in lip_names:
        key(n, prev[n], max(0, f0 - TRANS)); key(n, target[n], f0)
    prev = target
for n in lip_names: key(n, 0.0, fr(duration) + 3)

# blinks, brows, eye drift
for t in [1.1, 3.9, 6.4, 8.7, 11.0, 13.5]:
    if t > duration + .3: break
    for b in BLINK:
        key(b, 0, fr(t) - 3); key(b, 1, fr(t)); key(b, 1, fr(t) + 2); key(b, 0, fr(t) + 6)
for t in [.25, 4.1, 7.6, 10.5]:
    if t > duration: break
    key(BROW, 0, fr(t) - 4); key(BROW, .45, fr(t) + 2); key(BROW, .45, fr(t) + 14); key(BROW, 0, fr(t) + 26)
for i in range(0, scene.frame_end, 40):
    lx = rng.uniform(-.12, .12); ly = rng.uniform(-.06, .06)
    key(LOOK['l'], max(0, -lx), i); key(LOOK['r'], max(0, lx), i); key(LOOK['u'], max(0, ly), i); key(LOOK['d'], max(0, -ly), i)

# idle head / chest motion: slow layered sines, keyed every 6 frames
for bname, amp in ((HEAD, (2.2, 3.0, 1.4)), (NECK, (.8, 1.0, .5)), (CHEST, (.5, .8, .6))):
    pb = arm.pose.bones[bname]; pb.rotation_mode = 'XYZ'
    for f in range(0, scene.frame_end + 1, 6):
        t = f / a.fps
        pb.rotation_euler = Euler((math.radians(amp[0] * (math.sin(t * .9) * .6 + math.sin(t * 2.3 + 1) * .4)),
                                   math.radians(amp[2] * math.sin(t * .7 + 2) * .8),
                                   math.radians(amp[1] * (math.sin(t * .55) * .7 + math.sin(t * 1.7 + .5) * .3))), 'XYZ')
        pb.keyframe_insert('rotation_euler', frame=f)
# a gentle nod on the greeting
pb = arm.pose.bones[HEAD]
for f, dx in ((fr(.2), 0), (fr(.55), 5.5), (fr(1.0), 0)):
    e = pb.rotation_euler.copy(); e.x += math.radians(dx); pb.rotation_euler = e; pb.keyframe_insert('rotation_euler', frame=f)

# ---------------------------------------------------------------- render settings
scene.render.engine = 'BLENDER_EEVEE'
try: scene.eevee.taa_render_samples = a.samples
except Exception: pass
scene.render.resolution_x = a.width; scene.render.resolution_y = a.height; scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'AgX'; scene.view_settings.look = 'AgX - Medium High Contrast'
scene.render.image_settings.file_format = 'PNG'; scene.render.film_transparent = False
bpy.ops.wm.save_as_mainfile(filepath=str(a.out / 'agent.blend'))
if a.stills:
    for f in [int(x) for x in a.stills.split(',')]:
        scene.frame_set(f); scene.render.filepath = str(a.out / f'still-{f:04d}.png'); bpy.ops.render.render(write_still=True)
if a.frames:
    (a.out / 'frames').mkdir(exist_ok=True); scene.render.filepath = str(a.out / 'frames' / 'f'); bpy.ops.render.render(animation=True)
print('AGENT_RENDER_COMPLETE', a.out, 'frames', scene.frame_end, flush=True)
