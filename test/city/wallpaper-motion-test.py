"""Physical constraints and glTF export checks for prototype actor motion."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('city',ROOT/'build/tools/wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)


class MotionTests(unittest.TestCase):
    def test_loops_and_ferry_heading(self):
        tracks=city.motion_tracks()
        for times,positions,quaternions in tracks.values():
            self.assertTrue(np.all(np.diff(times)>0))
            self.assertTrue(np.allclose(positions[0],positions[-1]))
            self.assertTrue(np.allclose(np.linalg.norm(quaternions,axis=1),1))
            self.assertAlmostEqual(abs(np.dot(quaternions[0],quaternions[-1])),1)
        t,p,q=tracks['bay-ferry']
        # Rotated local +X axis must point along the boat's horizontal velocity.
        heading=np.column_stack((1-2*q[:,1]**2,-2*q[:,1]*q[:,3]))
        velocity=np.gradient(p[:,[0,2]],t,axis=0)
        velocity/=np.linalg.norm(velocity,axis=1,keepdims=True)
        self.assertTrue(np.all(np.einsum('ij,ij->i',heading[1:-1],velocity[1:-1])>.999))

    def test_trolley_wheels_follow_curved_street(self):
        t,p,q=city.motion_tracks()['plaza-cable-car']
        pitch=2*np.arctan2(q[:,0],q[:,3])
        for wheel_z in (-1.7,1.7):
            z=p[:,2]+np.cos(pitch)*wheel_z
            y=p[:,1]-np.sin(pitch)*wheel_z
            clearance=y-np.array([city.ground(zz) for zz in z])
            self.assertTrue(np.all(clearance>.04))
            self.assertTrue(np.all(clearance<.10))

    def test_rotation_channels_are_exported_and_invalid_rotations_rejected(self):
        v=city.v
        mesh=v.mesh_blocks(np.zeros((1,1,1),np.uint8),(0,0),[('box','dark',0,0,0,1,1,1)])
        times,positions,q=city.motion_tracks()['bay-ferry']
        with tempfile.TemporaryDirectory() as tmp:
            tmp=Path(tmp); v.make_atlas(tmp/'atlas.png',tmp/'frame.png')
            def export(rotations):
                v.write_glb(tmp/'room.glb',*mesh,tmp/'atlas.png',light_positions=[],
                    actors=[('boat',mesh,times,positions)],actor_rotations={'boat':rotations})
            export(q)
            data=(tmp/'room.glb').read_bytes(); size=struct.unpack_from('<I',data,12)[0]
            doc=json.loads(data[20:20+size]); binary=data[28+size:]
            animation=doc['animations'][0]
            channel=next(c for c in animation['channels'] if c['target']['path']=='rotation')
            sampler=animation['samplers'][channel['sampler']]
            accessor=doc['accessors'][sampler['output']]
            self.assertEqual(accessor['type'],'VEC4')
            view=doc['bufferViews'][accessor['bufferView']]
            saved=np.frombuffer(binary,dtype='<f4',offset=view['byteOffset'],count=len(q)*4).reshape(-1,4)
            self.assertTrue(np.allclose(saved,q))
            with self.assertRaises(ValueError): export(q[:-1])
            with self.assertRaises(ValueError): export(q*2)


if __name__=='__main__': unittest.main()
