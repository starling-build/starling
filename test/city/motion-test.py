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
                    self.assertAlmostEqual(z, -7)
                    self.assertLessEqual(abs(x), 12)


if __name__ == "__main__":
    unittest.main()
