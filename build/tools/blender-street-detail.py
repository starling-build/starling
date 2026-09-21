"""Reproducible material and terrace detail for the native Blender study."""
import random


def apply(bpy):
    rng = random.Random(704)
    name = '11 • Terrace gardens'
    previous = bpy.data.collections.get(name)
    if previous:
        for obj in list(previous.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(previous)
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)

    def material(name, swatch):
        existing = bpy.data.materials.get(name)
        if existing:
            return existing
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        color = tuple(v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in swatch)
        mat.diffuse_color = (*color, 1)
        shader = mat.node_tree.nodes.get('Principled BSDF')
        shader.inputs['Base Color'].default_value = (*color, 1)
        shader.inputs['Roughness'].default_value = .8
        return mat

    masonry = [material('Terrace sandstone ' + str(i), c) for i, c in enumerate([
        (.48, .42, .34), (.57, .50, .40), (.61, .55, .46), (.52, .48, .40)])]
    soil = material('Garden soil', (.12, .085, .045))
    petals = [material('Garden bloom ' + str(i), c) for i, c in enumerate([
        (.75, .22, .09), (.91, .53, .11), (.83, .69, .27), (.61, .12, .08)])]
    foliage = [bpy.data.materials['Foliage ' + str(i)] for i in range(3)]
    trim = bpy.data.materials['Ivory painted timber']

    class Batch:
        def __init__(self, name):
            self.name = name
            self.vertices, self.faces, self.indices, self.materials = [], [], [], []

        def box(self, center, size, mat):
            x, y, z = center
            u, v, w = (s / 2 for s in size)
            start = len(self.vertices)
            self.vertices.extend((x + dx*u, y + dy*v, z + dz*w) for dx, dy, dz in [
                (-1,-1,-1), (1,-1,-1), (1,1,-1), (-1,1,-1),
                (-1,-1,1), (1,-1,1), (1,1,1), (-1,1,1)])
            self.faces.extend(tuple(start + i for i in face) for face in [
                (0,3,2,1), (4,5,6,7), (0,1,5,4), (1,2,6,5), (2,3,7,6), (3,0,4,7)])
            if mat not in self.materials:
                self.materials.append(mat)
            self.indices.extend([self.materials.index(mat)] * 6)

        def finish(self, bevel=0):
            mesh = bpy.data.meshes.new(self.name)
            mesh.from_pydata(self.vertices, [], self.faces)
            for mat in self.materials:
                mesh.materials.append(mat)
            for poly, index in zip(mesh.polygons, self.indices):
                poly.material_index = index
            mesh.update()
            obj = bpy.data.objects.new(self.name, mesh)
            collection.objects.link(obj)
            if bevel:
                modifier = obj.modifiers.new('Worn stone edges', 'BEVEL')
                modifier.width, modifier.segments = bevel, 2
            return obj

    def ground(y):
        return max(0, 24 - .23*y - .00065*y*y)

    for side in [-1, 1]:
        for row, y in enumerate([0, 13, 26, 39, 52, 65, 78]):
            label = f'{"West" if side < 0 else "East"} house {row+1}'
            old = bpy.data.objects.get(label + ' / terrace')
            if old:
                bpy.data.objects.remove(old, do_unlink=True)
            wall = Batch(label + ' / coursed retaining wall')
            for course in range(3):
                for k in range(8):
                    yy = y - 5 + k*.65 + (course % 2)*.30
                    wall.box((side*12.1, yy, ground(yy)+.17+course*.31),
                             (.46, .62, .29), rng.choice(masonry))
            for k in range(9):
                yy = y-5+k*.65
                wall.box((side*12.1, yy, ground(yy)+1.04), (.62,.64,.15), trim)
            for yy in [y-5, y+.2]:
                for course in range(4):
                    wall.box((side*12.1, yy, ground(yy)+.16+course*.30),
                             (.64,.63,.28), rng.choice(masonry))
                wall.box((side*12.1, yy, ground(yy)+1.34), (.77,.76,.17), trim)
            wall.finish(.022)

            # Beds sit streetward of the projecting bays, leaving the road-side path clear.
            bed = Batch(label + ' / planted sidewalk bed')
            plants = Batch(label + ' / shrubs and flowers')
            for k in range(6):
                yy = y+.3+k*.62
                zz = ground(yy)
                bed.box((side*10.65, yy, zz+.55), (.76,.61,.60), rng.choice(masonry))
                bed.box((side*10.65, yy, zz+.88), (.84,.62,.10), trim)
                bed.box((side*10.65, yy, zz+.94), (.60,.55,.035), soil)
            bed.finish(.018)
            for k in range(80):
                xx = side*(10.65+rng.uniform(-.28,.28))
                yy = y+rng.uniform(.05,3.65)
                zz = ground(yy)+rng.uniform(1.0,1.35)
                plants.box((xx,yy,zz), (.20,.23,.20), rng.choice(foliage))
                if k % 2 == 0:
                    flower = rng.choice(petals)
                    for dx,dy in [(0,0),(-.06,0),(.06,0),(0,.06),(0,-.06)]:
                        plants.box((xx+dx,yy+dy,zz+.15), (.075,.075,.075), flower)
            plants.finish()

    # World-space wear and damp patches, shared consistently across paving stones.
    for i in range(7):
        mat = bpy.data.materials['Cobble ' + str(i)]
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        nodes.clear()
        output = nodes.new('ShaderNodeOutputMaterial')
        shader = nodes.new('ShaderNodeBsdfPrincipled')
        links.new(shader.outputs[0], output.inputs['Surface'])
        position = nodes.new('ShaderNodeNewGeometry')
        wear = nodes.new('ShaderNodeTexNoise')
        wear.inputs['Scale'].default_value = 5
        wear.inputs['Detail'].default_value = 3
        links.new(position.outputs['Position'], wear.inputs['Vector'])
        bump = nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .28
        bump.inputs['Distance'].default_value = .035
        links.new(wear.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], shader.inputs['Normal'])
        tint = nodes.new('ShaderNodeMixRGB')
        tint.blend_type = 'MULTIPLY'
        tint.inputs[0].default_value = .3
        tint.inputs[1].default_value = mat.diffuse_color
        links.new(wear.outputs['Fac'], tint.inputs[2])
        links.new(tint.outputs[0], shader.inputs['Base Color'])
        damp = nodes.new('ShaderNodeTexNoise')
        damp.inputs['Scale'].default_value = .17
        damp.inputs['Detail'].default_value = 2
        links.new(position.outputs['Position'], damp.inputs['Vector'])
        rough = nodes.new('ShaderNodeMapRange')
        rough.inputs['From Min'].default_value = .3
        rough.inputs['From Max'].default_value = .7
        rough.inputs['To Min'].default_value = .28 + i*.015
        rough.inputs['To Max'].default_value = .60 + i*.015
        links.new(damp.outputs['Fac'], rough.inputs['Value'])
        links.new(rough.outputs['Result'], shader.inputs['Roughness'])
    road = bpy.data.objects['Individual cobbles • downhill street']
    for modifier in road.modifiers:
        if modifier.type == 'BEVEL':
            modifier.width, modifier.segments = .035, 3
