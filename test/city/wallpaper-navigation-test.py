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
        self.assertEqual((w.x,w.z,w.pitch), (9.8,-5.,12.))


if __name__ == '__main__': unittest.main()
