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
        width = {"SCALAR": 1, "VEC3": 3}[acc["type"]]
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


if __name__ == "__main__":
    unittest.main()
