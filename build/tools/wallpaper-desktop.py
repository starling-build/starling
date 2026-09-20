#!/usr/bin/env python3
"""Prepare an opt-in desktop world from a generated wallpaper city. Does not install it."""
import argparse
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('city',HERE/'wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)


def configuration():
    data=city.navigation.description(city.ground,city.waterfront)
    nav=city.navigation.Navigation(data)
    x,z,yaw,pitch=data['spawn']
    floor=nav.floor(x,z)
    def numbers(key): return list(map(float,city.LIGHTING[key].split(',')))
    # A fallback for placing windows outside the narrow walking corridor.
    # Walking itself uses the finer geometry-derived sidecar.
    origin=[-80,-150]; size=[161,180]
    heights=[]
    for xx in range(origin[0],origin[0]+size[0]):
        for zz in range(origin[1],origin[1]+size[1]):
            y=nav.floor(xx+.5,zz+.5)
            heights.append(y if y is not None else -2.5)
    return dict(kind='voxel',ambient_animation=True,hub=[x,floor,z],eye_height=data['eye_height'],
        camera_home=dict(radius=0,height=0,dolly=0),ring_radius=7.5,
        exposure=numbers('ROOMTEST_EXPOSURE'),ibl_intensity=float(city.LIGHTING['ROOMTEST_IBL_LUX']),
        sun=dict(dir=numbers('ROOMTEST_SUN'),colour=numbers('ROOMTEST_SUN_COLOUR'),
                 lux=float(city.LIGHTING['ROOMTEST_SUN_LUX'])),fog=numbers('ROOMTEST_FOG'),
        pane_frame=dict(texture='frame.png',block=.18,margin=.012,depth=.025),
        workspaceRail=[dict(x=x,y=floor+data['eye_height']+2,z=z-17,width=3.8,height=2.375)],
        heightmap=dict(origin=origin,size=size,heights=heights)),data


def prepare(source,out):
    source=source.resolve();out=out.resolve()
    if source==out: raise ValueError('Use a separate output directory for the desktop profile')
    required=('room.glb','room_ibl.ktx','room_skybox.ktx','frame.png')
    for name in required:
        if not (source/name).is_file(): raise ValueError(f'Missing generated asset: {name}')
    if any((out/name).exists() for name in ('world.json','navigation.json')):
        if not all((out/name).is_symlink() and (out/name).resolve()==source/name for name in required):
            raise ValueError('Existing metadata is not part of this linked desktop profile')
    world,nav=configuration()
    out.mkdir(parents=True,exist_ok=True)
    # Refuse to overwrite unrelated assets; reruns may reuse our own links.
    for name in required:
        target=out/name
        if target.is_symlink() and target.resolve()==source/name: continue
        if target.exists() or target.is_symlink(): raise ValueError(f'Output asset already exists: {target}')
    for name in required:
        target=out/name
        if not target.is_symlink(): target.symlink_to(source/name)
    (out/'world.json').write_text(json.dumps(world,separators=(',',':'))+'\n')
    (out/'navigation.json').write_text(json.dumps(nav,indent=2)+'\n')
    return out


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',required=True,type=Path)
    p.add_argument('--out',required=True,type=Path)
    args=p.parse_args()
    try: out=prepare(args.source,args.out)
    except ValueError as error: p.error(str(error))
    print(f'Prepared {out}\nLaunch the locally built desktop with STARLING_ROOM_DIR={out}')


if __name__=='__main__': main()
