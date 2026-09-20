"""Exercise exporter material overrides without generating or changing a world."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('wallpaper_city', ROOT/'build/tools/wallpaper-city.py')
city = importlib.util.module_from_spec(spec)
spec.loader.exec_module(city)
v = city.v


class MaterialOptionsTests(unittest.TestCase):
    def test_normal_map_is_embedded_and_overrides_do_not_leak(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            v.make_atlas(tmp/'atlas.png',tmp/'frame.png')
            city.water_normal(tmp/'normal.png',32)
            mesh = v.mesh_blocks(np.zeros((1,1,1),np.uint8),(0,0),[
                ('box','water',0,0,0,4,1,4),
                ('box','plaster_rose',5,0,0,6,2,1)])
            def export(options):
                v.write_glb(tmp/'room.glb',*mesh,tmp/'atlas.png',actors=[],
                            light_positions=[],material_options=options)
                raw=(tmp/'room.glb').read_bytes()
                length=struct.unpack_from('<I',raw,12)[0]
                return json.loads(raw[20:20+length]),raw[28+length:]
            doc,binary=export({
                'surface_overrides': {'water':(None,(.1,.2,.3),.25,.35,7.)},
                'normal_maps': {'water':(tmp/'normal.png',.7)},
            })
            water=next(m for m in doc['materials'] if m['name']=='water')
            texture=doc['textures'][water['normalTexture']['index']]
            image=doc['images'][texture['source']]
            view=doc['bufferViews'][image['bufferView']]
            self.assertEqual(binary[view['byteOffset']:view['byteOffset']+view['byteLength']],
                             (tmp/'normal.png').read_bytes())
            self.assertEqual(doc['samplers'][texture['sampler']]['wrapS'],10497)
            all_indices=[]
            for primitive in doc['meshes'][0]['primitives']:
                acc=doc['accessors'][primitive['indices']]
                view=doc['bufferViews'][acc['bufferView']]
                all_indices.extend(np.frombuffer(binary,dtype='<u4',count=acc['count'],
                                                 offset=view['byteOffset']).tolist())
            self.assertCountEqual([tuple(all_indices[i:i+3]) for i in range(0,len(all_indices),3)],
                                  [tuple(t) for t in mesh[3].reshape(-1,3)])
            default,_=export(None)
            self.assertNotIn('water',{m['name'] for m in default['materials']})
            self.assertFalse(any('normalTexture' in m for m in default['materials']))


if __name__=='__main__': unittest.main()
