"""Validate the shipped city animation buffers without a GPU or third-party modules."""
import json
import math
from pathlib import Path
import struct
import unittest


class CityMotionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        data = (root / "shell/Resources/Worlds/city/room.glb").read_bytes()
        magic, version, length = struct.unpack_from("<III", data)
        assert (magic, version, length) == (0x46546C67, 2, len(data))
        size, kind = struct.unpack_from("<II", data, 12)
        assert kind == 0x4E4F534A
        cls.doc = json.loads(data[20:20 + size])
        binary_size, kind = struct.unpack_from("<II", data, 20 + size)
        assert kind == 0x004E4942
        cls.binary = data[28 + size:28 + size + binary_size]
        cls.world = json.loads((root / "shell/Resources/Worlds/city/world.json").read_text())

    def values(self, index):
        acc = self.doc["accessors"][index]
        view = self.doc["bufferViews"][acc["bufferView"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[acc["type"]]
        count = width * acc["count"]
        offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        self.assertLessEqual(offset + count * 4, len(self.binary))
        values = struct.unpack_from("<" + "f" * count, self.binary, offset)
        self.assertTrue(all(math.isfinite(v) for v in values))
        return [values[i:i + width] for i in range(0, count, width)]

    def test_actors_are_separate_scene_nodes(self):
        names = {a["name"] for a in self.doc["animations"]}
        self.assertEqual(names, {"bay-ferry", "plaza-cable-car"} | {f"cloud-{i}" for i in range(5)})
        nodes = []
        for animation in self.doc["animations"]:
            channel = animation["channels"][0]
            self.assertEqual(channel["target"]["path"], "translation")
            node = channel["target"]["node"]
            self.assertIn(node, self.doc["scenes"][0]["nodes"])
            self.assertNotEqual(node, 0)  # never animate the city or app anchors
            nodes.append(node)
        self.assertEqual(len(nodes), len(set(nodes)))

    def test_tracks_move_and_loop_without_teleporting(self):
        for animation in self.doc["animations"]:
            sampler = animation["samplers"][0]
            times = [x[0] for x in self.values(sampler["input"])]
            positions = self.values(sampler["output"])
            self.assertEqual(len(times), len(positions))
            self.assertEqual(times[0], 0)
            self.assertTrue(all(b > a for a, b in zip(times, times[1:])))
            self.assertGreaterEqual(times[-1], 60)
            self.assertTrue(any(math.dist(positions[0], p) > 5 for p in positions))
            self.assertLess(math.dist(positions[0], positions[-1]), 1e-5)

    def test_routes_leave_the_interaction_foreground_clear(self):
        for animation in self.doc["animations"]:
            positions = self.values(animation["samplers"][0]["output"])
            for x, y, z in positions:
                if animation["name"].startswith("cloud-"):
                    self.assertGreaterEqual(y, 24)
                    self.assertLess(z, -60)
                elif animation["name"] == "bay-ferry":
                    self.assertLess(z, -28)
                    self.assertLess(y, 5)
                else:
                    self.assertAlmostEqual(x, -4)
                    self.assertGreaterEqual(z, -37)
                    self.assertLessEqual(z, -12)
                    self.assertAlmostEqual(y, 5+(z+8)*.19+.06, places=5)

    def test_geometry_is_finite_and_indexed(self):
        for mesh in self.doc["meshes"]:
            for primitive in mesh["primitives"]:
                vertices = self.values(primitive["attributes"]["POSITION"])
                normals = self.values(primitive["attributes"]["NORMAL"])
                self.assertEqual(len(vertices),len(normals))
                for normal in normals:
                    self.assertAlmostEqual(math.sqrt(sum(x*x for x in normal)),1,places=5)
                acc = self.doc["accessors"][primitive["indices"]]
                view = self.doc["bufferViews"][acc["bufferView"]]
                indices = struct.unpack_from("<"+"I"*acc["count"],self.binary,view["byteOffset"])
                self.assertLess(max(indices),len(vertices))

    def test_east_panorama_has_no_nearby_facade_at_eye_level(self):
        primitive = self.doc["meshes"][0]["primitives"][0]
        vertices = self.values(primitive["attributes"]["POSITION"])
        # Authored boxes have four vertices per face. Conservatively test
        # face bounds along three horizontal rays through the east monitor.
        eye = 5+self.world["eye_height"]+self.world["camera_home"]["height"]
        for slope in (.65,.85,1.05):
            for i in range(0,len(vertices),4):
                face = vertices[i:i+4]
                if not min(p[1] for p in face) <= eye <= max(p[1] for p in face):
                    continue
                lo,hi = .1,55.0
                for axis,origin,direction in ((0,0,slope),(2,13,-1)):
                    a = (min(p[axis] for p in face)-origin)/direction
                    b = (max(p[axis] for p in face)-origin)/direction
                    lo,hi = max(lo,min(a,b)),min(hi,max(a,b))
                self.assertGreater(lo,hi,"A nearby face blocks the east panorama")

    def test_evening_lighting_and_walkable_slope(self):
        self.assertGreater(self.world["sun"]["lux"],2000)
        self.assertLess(self.world["sun"]["lux"],20000)
        self.assertGreater(self.world["sun"]["colour"][0],self.world["sun"]["colour"][2])
        material = self.doc["materials"][0]
        self.assertIn("emissiveTexture",material)
        self.assertGreater(material["extensions"]["KHR_materials_emissive_strength"]["emissiveStrength"],0)
        self.assertLess(material["extensions"]["KHR_materials_emissive_strength"]["emissiveStrength"],1)
        lights = self.doc["extensions"]["KHR_lights_punctual"]["lights"]
        self.assertEqual(len(lights),6)
        light_nodes = [n for n in self.doc["nodes"] if "KHR_lights_punctual" in n.get("extensions",{})]
        self.assertEqual(len(light_nodes),len(lights))
        hm = self.world["heightmap"]
        def height(x,z):
            return hm["heights"][(x-hm["origin"][0])*hm["size"][1]+z-hm["origin"][1]]
        for x in (-8,0,8):
            for z in (-8,0,13):
                self.assertEqual(height(x,z),5)
            self.assertAlmostEqual(height(x,-35),-.13)
            self.assertAlmostEqual(height(x,-20),2.72)
        self.assertEqual(self.world["clock"]["z"],-49)

    def test_material_groups_preserve_every_city_triangle_once(self):
        primitives = self.doc["meshes"][0]["primitives"]
        all_indices = []
        for primitive in primitives:
            acc = self.doc["accessors"][primitive["indices"]]
            view = self.doc["bufferViews"][acc["bufferView"]]
            offset = view.get("byteOffset",0) + acc.get("byteOffset",0)
            all_indices.extend(struct.unpack_from("<"+"I"*acc["count"],self.binary,offset))
        # Every authored quad is triangulated into six indices. Splitting
        # materials must neither drop nor overlay any of those triangles.
        count = self.doc["accessors"][0]["count"]
        expected = [(i,i+1,i+2) for i in range(0,count,4)]
        expected += [(i,i+2,i+3) for i in range(0,count,4)]
        actual = [tuple(all_indices[i:i+3]) for i in range(0,len(all_indices),3)]
        self.assertCountEqual(actual,expected)

    def test_architecture_uses_repeating_physical_scale_materials(self):
        materials = self.doc["materials"]
        plaster = next(p for p in self.doc["meshes"][0]["primitives"]
                       if materials[p["material"]]["name"] == "plaster_rose")
        material = materials[plaster["material"]]["pbrMetallicRoughness"]
        texture = self.doc["textures"][material["baseColorTexture"]["index"]]
        sampler = self.doc["samplers"][texture["sampler"]]
        self.assertEqual((sampler["wrapS"],sampler["wrapT"]),(10497,10497))
        self.assertEqual(sampler["minFilter"],9987)  # trilinear mipmaps
        uv = self.values(plaster["attributes"]["TEXCOORD_0"])
        positions = self.values(plaster["attributes"]["POSITION"])
        normals = self.values(plaster["attributes"]["NORMAL"])
        # A texture covers two metres on all three dominant face planes.
        for p,n,t in zip(positions,normals,uv):
            axis = max(range(3),key=lambda i: abs(n[i]))
            plane = ((2,1),(0,2),(0,1))[axis]
            for k,coordinate in enumerate(plane):
                self.assertAlmostEqual(t[k],p[coordinate]/2,places=4)

    def test_cloud_surfaces_have_outward_non_degenerate_triangles(self):
        # Smooth spheres with collapsed latitude poles can silently ship
        # zero-area triangles or inverted faces. Check the exported geometry.
        import numpy as np
        for node in self.doc["nodes"]:
            if not node.get("name", "").startswith("cloud-"):
                continue
            primitive = self.doc["meshes"][node["mesh"]]["primitives"][0]
            p = np.asarray(self.values(primitive["attributes"]["POSITION"]))
            n = np.asarray(self.values(primitive["attributes"]["NORMAL"]))
            acc = self.doc["accessors"][primitive["indices"]]
            view = self.doc["bufferViews"][acc["bufferView"]]
            indices = np.frombuffer(self.binary,dtype="<u4",count=acc["count"],
                                    offset=view.get("byteOffset",0)+acc.get("byteOffset",0)).reshape(-1,3)
            a,b,c = p[indices[:,0]],p[indices[:,1]],p[indices[:,2]]
            geometric = np.cross(b-a,c-a)
            self.assertTrue(np.all(np.linalg.norm(geometric,axis=1)>1e-7))
            averaged = n[indices].mean(axis=1)
            self.assertTrue(np.all(np.sum(geometric*averaged,axis=1)>0))


if __name__ == "__main__":
    unittest.main()
