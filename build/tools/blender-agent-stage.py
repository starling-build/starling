#!/usr/bin/env python3
"""Full-length "character sheet" render of the agent: dark indigo stage, overhead spot with a pool on the
floor, violet and pink rims, warm hair glow, neutral face (see design/blender/agent/README.md).

  blender -b --python build/tools/blender-agent-stage.py -- IN.blend OUT.png [VIEW_TRANSFORM] [FRAME]

Works on any agent.blend from blender-agent-avatar.py or blender-agent-refine.py; hides their bust-shot
backdrop, halo and lights and never saves the file.
"""
import bpy, math, sys
from mathutils import Vector
argv = sys.argv[sys.argv.index('--') + 1:]; blend, out = argv[0], argv[1]; view = argv[2] if len(argv) > 2 else 'Standard'
bpy.ops.wm.open_mainfile(filepath=blend); sc = bpy.context.scene; sc.frame_set(int(argv[3]) if len(argv) > 3 else 1)
for o in bpy.data.objects:   # neutral face: drop the clip's expression keys for the still
    if o.type == 'MESH' and o.data.shape_keys and o.data.shape_keys.animation_data:
        o.data.shape_keys.animation_data.action = None
        for k in o.data.shape_keys.key_blocks[1:]: k.value = 0.0
for o in bpy.data.objects:
    if o.name in ('Backdrop', 'Halo ring') or o.type == 'LIGHT': o.hide_render = True
w = sc.world or bpy.data.worlds.new('W'); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes.get('Background'); bg.inputs[0].default_value = (0.006, 0.004, 0.02, 1); bg.inputs[1].default_value = 1.0
def light(name, kind, loc, energy, color, size=0.5, spot=None, target=(0, 0, 0.9)):
    d = bpy.data.lights.new(name, kind); d.energy = energy; d.color = color
    if kind in ('AREA',): d.size = size
    if kind == 'SPOT': d.spot_size = math.radians(spot or 40); d.spot_blend = 0.6; d.shadow_soft_size = 0.15
    o = bpy.data.objects.new(name, d); sc.collection.objects.link(o); o.location = loc
    o.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler(); return o
light('Stage spot', 'SPOT', (0.25, -1.6, 3.8), 650, (1.0, 0.9, 0.84), spot=26, target=(0, 0, 0.55))
light('Face fill', 'AREA', (-0.8, -2.2, 1.6), 22, (0.8, 0.75, 1.0), size=1.5, target=(0, 0, 1.4))
light('Rim L', 'SPOT', (-1.3, 1.2, 2.0), 380, (0.62, 0.4, 1.0), spot=24, target=(0, 0, 1.25))
light('Hair glow', 'SPOT', (0.0, 1.4, 2.6), 420, (1.0, 0.82, 0.5), spot=22, target=(0, 0.05, 1.5))
light('Rim R', 'SPOT', (1.3, 1.1, 1.9), 330, (1.0, 0.45, 0.8), spot=24, target=(0, 0, 1.2))
# floor + a violet haze behind the figure
bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0)); fl = bpy.context.object
fm = bpy.data.materials.new('Stage floor'); fm.use_nodes = True; b = fm.node_tree.nodes['Principled BSDF']
b.inputs['Base Color'].default_value = (0.02, 0.018, 0.03, 1); b.inputs['Roughness'].default_value = 0.55; fl.data.materials.append(fm)
bpy.ops.mesh.primitive_plane_add(size=9, location=(0.4, 3.0, 2.2), rotation=(math.radians(90), 0, 0)); hz = bpy.context.object
hm = bpy.data.materials.new('Haze'); hm.use_nodes = True; n, l = hm.node_tree.nodes, hm.node_tree.links; n.clear()
tc = n.new('ShaderNodeTexCoord'); gr = n.new('ShaderNodeTexGradient'); gr.gradient_type = 'SPHERICAL'; mp = n.new('ShaderNodeMapping')
mp.inputs['Scale'].default_value = (0.55, 0.42, 1); mp.inputs['Location'].default_value = (0.0, 0.08, 0)
cr = n.new('ShaderNodeValToRGB'); cr.color_ramp.elements[0].color = (0.004, 0.003, 0.016, 1); cr.color_ramp.elements[1].color = (0.05, 0.016, 0.085, 1)
em = n.new('ShaderNodeEmission'); em.inputs['Strength'].default_value = 1.0; o_ = n.new('ShaderNodeOutputMaterial')
l.new(tc.outputs['Object'], mp.inputs['Vector']); l.new(mp.outputs['Vector'], gr.inputs['Vector']); l.new(gr.outputs['Fac'], cr.inputs['Fac'])
l.new(cr.outputs['Color'], em.inputs['Color']); l.new(em.outputs['Emission'], o_.inputs['Surface']); hz.data.materials.append(hm)
cam = bpy.data.cameras.new('Ref cam'); cam.lens = 75; co = bpy.data.objects.new('Ref cam', cam); sc.collection.objects.link(co)
co.location = (0, -4.1, 1.05); co.rotation_euler = (Vector((0, 0, 0.84)) - co.location).to_track_quat('-Z', 'Y').to_euler()
sc.camera = co; sc.render.resolution_x = 640; sc.render.resolution_y = 1137
sc.view_settings.view_transform = view; sc.view_settings.look = 'None'
if hasattr(sc.eevee, 'use_shadows'): sc.eevee.use_shadows = True
sc.render.filepath = out; bpy.ops.render.render(write_still=True)
