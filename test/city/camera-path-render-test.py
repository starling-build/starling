"""Check camera-path validation, RGB frame layout and deterministic rendering."""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('city',ROOT/'build/tools/wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world',required=True,type=Path)
    world=parser.parse_args().world
    with tempfile.TemporaryDirectory() as scratch:
        scratch=Path(scratch); path=scratch/'path.csv'; raw=scratch/'frames.rgb'
        cmd=[str(ROOT/'.build-shared/roomtest'),str(world/'room.glb'),
             str(world/'room_ibl.ktx'),str(world/'room_skybox.ktx'),str(raw),'384','216']
        env={**os.environ,**city.LIGHTING,'ROOMTEST_PATH':str(path)}
        for invalid in ('','0,1,2\n','nan,0,40,18,0,7.5\n',
                        '1,0,40,18,0,7.5\n0,0,40,18,0,7.5\n'):
            path.write_text(invalid)
            result=subprocess.run(cmd,env=env,capture_output=True)
            assert result.returncode==2, result.stderr.decode()
            assert not raw.exists()
        path.write_text('0,0,40,18,0,7.5\n1,10,30,-20,0,7.5\n2,8.5,-.2,-119,0,0\n3,34,1.12,-130,0,-55\n')
        subprocess.run(cmd,env=env,capture_output=True,check=True)
        frames=np.fromfile(raw,dtype=np.uint8).reshape(4,216,384,3).astype(float)
        still=scratch/'still.ppm'
        cmd[4]=str(still); env.pop('ROOMTEST_PATH')
        env['ROOMTEST_FRAMES']='3'
        subprocess.run(cmd+['0','40','18','0','7.5'],env=env,capture_output=True,check=True)
        with Image.open(still) as image: expected=np.asarray(image,dtype=float)
        error=np.abs(frames[0]-expected).mean()
        change=np.abs(frames[1]-frames[0]).mean()
        assert error<.5, f'first video frame differs from still: {error}'
        assert change>2, f'camera did not move: {change}'
        env['ROOMTEST_TIME']='3'
        subprocess.run(cmd+['34','1.12','-130','0','-55'],env=env,capture_output=True,check=True)
        with Image.open(still) as image: last=np.asarray(image,dtype=float)
        last_error=np.abs(frames[-1]-last).mean()
        assert last_error<1, f'later video frame is stale/wrong: {last_error}' 
        print(f'Camera path checks passed: invalid rows rejected; RGB orientation and size correct; '
              f'first-frame error {error:.3f}/255; moving camera delta {change:.2f}/255')


if __name__=='__main__': main()
