"""Check waterfront face winding and the reconstructed basin's open water."""
import importlib.util
from pathlib import Path
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('city',ROOT/'build/tools/wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)


class WaterfrontTests(unittest.TestCase):
    def test_block_and_quay_geometry(self):
        props=[]
        for variant in range(3):
            city.waterfront.district_block(props,variant*10,-105,7,4.4+variant*2,
                                            'plaster_cream',variant)
        city.waterfront.quay(props)
        pos,norm,uv,indices=city.v.mesh_blocks(np.zeros((1,1,1),np.uint8),(0,0),props)
        self.assertTrue(np.isfinite(pos).all() and np.isfinite(uv).all())
        self.assertTrue(np.allclose(np.linalg.norm(norm,axis=1),1,atol=1e-5))
        triangles=indices.reshape(-1,3)
        a,b,c=(pos[triangles[:,i]] for i in range(3))
        cross=np.cross(b-a,c-a)
        self.assertTrue((np.linalg.norm(cross,axis=1)>1e-8).all())
        self.assertTrue((np.einsum('ij,ij->i',cross,norm[triangles].mean(axis=1))>0).all())

    def test_basin_remains_open_between_connected_shores(self):
        props=[]; city.waterfront.quay(props)
        def solid_at(x,z):
            return any(p[0]=='box' and p[2]<=x<=p[5] and p[4]<=z<=p[7]
                       and p[3]<=-2.5<=p[6] for p in props)
        for x,z in ((40,-100),(60,-116),(35,-120)):
            self.assertFalse(solid_at(x,z),(x,z))
        for x,z in ((20,-105),(40,-85),(40,-132),(8,-120)):
            self.assertTrue(solid_at(x,z),(x,z))


if __name__=='__main__': unittest.main()
