#!/usr/bin/env python3
"""Record a scripted pedestrian preview; does not install a desktop world."""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import numpy as np

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('city',HERE/'wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)


def camera_path(fps=24):
    times=np.arange(100*fps,dtype=float)/fps
    knots=[0,42,47,67,74,77,93,96,100]
    x=np.interp(times,knots,[9.8,9.8,8.5,8.5,8.5,8.5,34,34,34])
    z=np.interp(times,knots,[-5,-78,-86,-119,-130,-130,-130,-130,-130])
    yaw=np.interp(times,knots,[0,0,0,0,0,90,90,0,0])
    pitch=np.interp(times,knots,[12,12,0,0,0,0,0,-75,-75])
    surface=[]
    for zz in z:
        if zz>=-84: floor=city.ground(zz)+.16
        elif zz>=-121: floor=-1.9
        elif zz>-128: floor=-1.9+min(10,np.ceil((-121-zz)/.7))*.132
        else: floor=-.58
        surface.append(floor)
    # Ease small stair risers over a quarter second, without camera head-bob.
    radius=max(1,round(fps*.125))
    surface=np.convolve(np.pad(surface,(radius,radius),mode='edge'),
                        np.ones(radius*2+1)/(radius*2+1),mode='valid')
    return np.column_stack((times,x,surface+1.7,z,yaw,pitch))


def verify_motion(video):
    frames=[]
    for second in (0,70,99):
        result=subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-ss',str(second),
            '-i',str(video),'-frames:v','1','-vf','scale=160:100',
            '-f','rawvideo','-pix_fmt','rgb24','pipe:1'],stdout=subprocess.PIPE,check=True)
        if len(result.stdout)!=160*100*3: raise RuntimeError('Incomplete decoded checkpoint')
        frames.append(np.frombuffer(result.stdout,dtype=np.uint8).astype(float))
    for first,last in zip(frames,frames[1:]):
        if np.abs(first-last).mean()<5:
            raise RuntimeError('Encoded walkthrough appears frozen between checkpoints')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world',required=True,type=Path)
    parser.add_argument('--out',required=True,type=Path)
    parser.add_argument('--fps',type=int,default=24)
    args=parser.parse_args()
    if not 1<=args.fps<=60: parser.error('--fps must be between 1 and 60')
    args.out.parent.mkdir(parents=True,exist_ok=True)
    path=args.out.with_suffix('.csv')
    np.savetxt(path,camera_path(args.fps),delimiter=',',fmt='%.7f')
    with tempfile.TemporaryDirectory(prefix='wallpaper-walk-',dir=args.out.parent) as scratch:
        raw=Path(scratch)/'frames.rgb'
        log=args.out.with_suffix('.render.log')
        with log.open('w') as output:
            subprocess.run([str(city.ROOT/'.build-shared/roomtest'),
                str(args.world/'room.glb'),str(args.world/'room_ibl.ktx'),
                str(args.world/'room_skybox.ktx'),str(raw),'960','600'],
                env={**os.environ,**city.LIGHTING,'ROOMTEST_PATH':str(path.resolve())},
                stdout=output,stderr=output,check=True)
        expected=len(camera_path(args.fps))*960*600*3
        if raw.stat().st_size!=expected:
            raise RuntimeError(f'Incomplete frame stream: {raw.stat().st_size} != {expected}')
        subprocess.run(['ffmpeg','-y','-hide_banner','-loglevel','error',
            '-f','rawvideo','-pixel_format','rgb24','-video_size','960x600',
            '-framerate',str(args.fps),'-i',str(raw),'-an','-c:v','libx264',
            '-preset','medium','-crf','22','-pix_fmt','yuv420p','-movflags','+faststart',
            str(args.out)],check=True)
    verify_motion(args.out)
    print(f'Saved {args.out}: 100-second scripted route, {args.fps} fps; camera samples: {path}')


if __name__=='__main__': main()
