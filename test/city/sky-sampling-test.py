"""Spherical sampling must tolerate nonperiodic image-generator output."""
import importlib.util
from pathlib import Path
import unittest
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('city',ROOT/'build/tools/wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)


class SkySamplingTests(unittest.TestCase):
    def test_mismatched_source_edges_do_not_make_a_meridian_or_pinched_pole(self):
        # Deliberately incompatible east/west colors and nonuniform pole rows.
        source=np.zeros((64,128,3),dtype=np.uint8)
        source[:,:,0]=np.linspace(30,210,128).astype(np.uint8)
        source[:,:,1]=100
        source[:,:,2]=np.linspace(180,70,128).astype(np.uint8)
        result=city.sky_samples(Image.fromarray(source),size=(2048,256))
        self.assertTrue(np.isfinite(result).all())
        for row in (0,255):
            self.assertLess(np.ptp(result[row],axis=0).max(),1e-7)
        # The equator crosses the repaired source seam as well as the panorama
        # boundary. No adjacent step should retain the input's sharp color jump.
        equator=result[128]
        delta=np.abs(equator-np.roll(equator,1,axis=0)).max()
        self.assertLess(delta,.01)
        self.assertGreater(np.ptp(equator[:,0]),.1)


if __name__=='__main__': unittest.main()
