"""GPU smoke check for optional distance haze using the reference camera.

python3 test/city/fog-render-test.py --world /tmp/wallpaper-city
Requires built roomtest and the generated prototype. No installed world changes.
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
spec=importlib.util.spec_from_file_location('wallpaper_city',ROOT/'build/tools/wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world',required=True,type=Path)
    args=parser.parse_args()
    env={**os.environ,**city.LIGHTING,'ROOMTEST_FRAMES':'3'}
    env.pop('ROOMTEST_FOG',None)
    with tempfile.TemporaryDirectory(prefix='starling-fog-test-') as scratch:
        frames={}
        for name,fog in (('default',None),('disabled','0,160,0,.07,.42,.65,.75,.9'),
                         ('enabled',city.LIGHTING['ROOMTEST_FOG'])):
            frame=Path(scratch)/(name+'.ppm')
            run_env=env if fog is None else {**env,'ROOMTEST_FOG':fog}
            cmd=[str(ROOT/'.build-shared/roomtest'),str(args.world/'room.glb'),
                 str(args.world/'room_ibl.ktx'),str(args.world/'room_skybox.ktx'),str(frame),
                 '512','288',*map(str,city.CAMERA['position']),
                 str(city.CAMERA['yaw']),str(city.CAMERA['pitch'])]
            result=subprocess.run(cmd,env=run_env,capture_output=True,text=True)
            if result.returncode:
                raise RuntimeError(result.stdout+result.stderr)
            with Image.open(frame) as image: frames[name]=np.asarray(image,dtype=float)
        # These fixed regions exclude animated actors and the foreground tree.
        regions={'sky':(slice(10,45),slice(200,300)),
                 'foreground':(slice(258,282),slice(100,440)),
                 'hills':(slice(101,119),slice(110,190))}
        for name,region in regions.items():
            error=np.abs(frames['default'][region]-frames['disabled'][region]).mean()
            assert error<.5, f'disabling fog changed {name}: mean error {error:.3f}'
        delta={name:float(np.abs(frames['enabled'][region]-frames['default'][region]).mean())
               for name,region in regions.items()}
        assert delta['hills']>2, f'fog did not soften distant terrain: {delta}'
        assert delta['sky']<.5, f'fog changed the skybox: {delta}'
        assert delta['foreground']<.5, f'fog reached the foreground: {delta}'
        print('Fog GPU checks passed: default equals disabled; sky and foreground preserved; '
              f'distant terrain changes by {delta["hills"]:.2f}/255 mean RGB')


if __name__=='__main__': main()
