"""Protect the reflected facade transform and varied roof geometry."""
import importlib.util
from pathlib import Path
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('wallpaper_city',ROOT/'build/tools/wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)


class ArchitectureTests(unittest.TestCase):
    def test_facades_on_both_sides_have_outward_non_degenerate_faces(self):
        for side in (-1,1):
            for variant in range(3):
                with self.subTest(side=side,variant=variant):
                    p,n,uv,indices=city.architecture.victorian(
                        city.v,-20 if side<0 else 13,-5,7,6.5+variant*1.5,
                        'plaster_blue',side,city.ground,variant)
                    self.assertTrue(np.isfinite(p).all())
                    self.assertTrue(np.isfinite(uv).all())
                    self.assertLess(indices.max(),len(p))
                    self.assertTrue(np.allclose(np.linalg.norm(n,axis=1),1,atol=1e-5))
                    t=indices.reshape(-1,3); a,b,c=p[t[:,0]],p[t[:,1]],p[t[:,2]]
                    geometric=np.cross(b-a,c-a)
                    self.assertTrue(np.all(np.linalg.norm(geometric,axis=1)>1e-8))
                    self.assertTrue(np.all(np.einsum('ij,ij->i',geometric,n[t].mean(axis=1))>0))
                    # Both reflected buildings and their stairs stay outside
                    # the rails; mirrored transforms must not move them into the street.
                    self.assertTrue(np.all(p[:,0]<-9) if side<0 else np.all(p[:,0]>9))


if __name__=='__main__': unittest.main()
