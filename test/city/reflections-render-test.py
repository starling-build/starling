"""GPU smoke check for opt-in screen-space reflections in the bay preview.

python3 test/city/reflections-render-test.py --world /tmp/wallpaper-city
"""
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
    args=parser.parse_args()
    env={**os.environ,**city.LIGHTING,'ROOMTEST_FRAMES':'4'}
    env.pop('ROOMTEST_REFLECTIONS',None)
    camera=city.WATERFRONT_CAMERA
    with tempfile.TemporaryDirectory(prefix='starling-reflections-') as scratch:
        frames={}
        for name,value in (('default',None),('disabled','0'),('enabled','1')):
            path=Path(scratch)/(name+'.ppm')
            run_env=env if value is None else {**env,'ROOMTEST_REFLECTIONS':value}
            result=subprocess.run([str(ROOT/'.build-shared/roomtest'),
                str(args.world/'room.glb'),str(args.world/'room_ibl.ktx'),
                str(args.world/'room_skybox.ktx'),str(path),'700','500',
                *map(str,camera['position']),str(camera['yaw']),str(camera['pitch'])],
                env=run_env,capture_output=True,text=True)
            if result.returncode: raise RuntimeError(result.stdout+result.stderr)
            with Image.open(path) as image: frames[name]=np.asarray(image,dtype=float)
        default_error=np.abs(frames['default']-frames['disabled']).mean()
        assert default_error<.5, f'default changed: {default_error}'
        sky=(slice(10,100),slice(200,500))
        water=(slice(350,440),slice(280,460))
        sky_error=np.abs(frames['enabled'][sky]-frames['disabled'][sky]).mean()
        water_delta=np.abs(frames['enabled'][water]-frames['disabled'][water]).mean()
        assert sky_error<.5, f'reflections changed sky: {sky_error}'
        assert water_delta>.5, f'no visible water reflection change: {water_delta}'
        print(f'Reflection GPU checks passed: default equals disabled; sky preserved; '
              f'water changes by {water_delta:.2f}/255 mean RGB')


if __name__=='__main__': main()
