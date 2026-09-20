"""Exercise a complete pedestrian trip plus boundaries and delayed input."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('preview', ROOT/'build/tools/wallpaper-preview.py')
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class NavigationTest(unittest.TestCase):
    def test_walk_to_quay(self):
        w = preview.Walker()
        w.x,w.z=9.8,-5.
        w.y=w.floor(w.z)+1.7
        for _ in range(435): w.update(['KeyW'], .1, [0, 0])
        self.assertAlmostEqual(w.z, -83.3)
        for _ in range(7): w.update(['KeyA'], .1, [0, 0])
        self.assertAlmostEqual(w.x, 8.54)
        for _ in range(260): w.update(['KeyW'], .1, [0, 0])
        self.assertAlmostEqual(w.z, -130.1)
        for _ in range(140): w.update(['KeyD'], .1, [0, 0])
        self.assertGreater(w.x, 33)
        self.assertAlmostEqual(w.y, 1.12, places=3)
        # Water side is closed: cannot step off the quay.
        for _ in range(100): w.update(['KeyS'], .1, [0, 0])
        self.assertLessEqual(w.z, -129)
        self.assertTrue(w.allowed(w.x, w.z))

    def test_workspace_connects_to_sidewalk(self):
        w=preview.Walker()
        self.assertTrue(w.allowed(w.x,w.z))
        for _ in range(55): w.update(['KeyD'],.1,[0,0])
        self.assertAlmostEqual(w.x,9.9)
        for _ in range(30): w.update(['KeyW'],.1,[0,0])
        self.assertAlmostEqual(w.z,-4.4)
        self.assertTrue(w.allowed(w.x,w.z))

    def test_floor_matches_pavement_geometry(self):
        nav = preview.Walker().navigation
        # Heights at staircase treads, limestone nosings, and the quay lip
        # must match the actual boxes emitted by the waterfront generator.
        props=[]
        preview.city.waterfront.quay(props)
        for i in range(441):
            z=-119-i*.025
            top=max(p[6] for p in props if p[0]=='box' and p[2]<=8.5<=p[5]
                    and p[4]<=z<=p[7])
            self.assertAlmostEqual(nav.floor(8.5,z),top,places=7)
        # The midpoint of each street strip follows its flat slab, not the
        # analytical slope half a strip farther downhill.
        for z,y in preview.city.navigation.street_rows(preview.city.ground):
            self.assertAlmostEqual(nav.floor(9.8,z+.3),y+.16,places=7)

    def test_clearance_and_large_dt(self):
        w = preview.Walker()
        for point in [(9.3,-3), (17,-131), (30,-120), (0,-100), (80,-130)]:
            self.assertFalse(w.allowed(*point), point)
        old = w.z
        w.update(['KeyW'], 100, [0, 0])
        self.assertLessEqual(abs(w.z-old), .181)
        for _ in range(200): w.update(['KeyD','KeyW'], .1, [0, 0])
        self.assertTrue(w.allowed(w.x,w.z))
        w.update(['Home'], .1, [0,0])
        self.assertEqual((w.x,w.z,w.pitch), (0,1,5.))


if __name__ == '__main__': unittest.main()
