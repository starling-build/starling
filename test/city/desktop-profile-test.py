"""Load the generated profile through the desktop's actual World3D Swift parser."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('desktop',ROOT/'build/tools/wallpaper-desktop.py')
desktop=importlib.util.module_from_spec(spec);spec.loader.exec_module(desktop)
world,nav=desktop.configuration()
assert len(world['heightmap']['heights'])==161*180
source=(ROOT/'shell/Sources/DesktopShellApp/Compositor/FilamentRoom.swift').read_text()
model=source[source.index('struct World3D {'):source.index('final class FilamentRoomRenderer:')]
with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp)
    assets=tmp/'assets';assets.mkdir()
    for name in ('room.glb','room_ibl.ktx','room_skybox.ktx','frame.png'):
        (assets/name).write_bytes(b'fixture')
    generated=desktop.prepare(assets,tmp/'profile')
    assert (generated/'room.glb').is_symlink()
    desktop.prepare(assets,generated)  # Same-profile regeneration is allowed.
    foreign=tmp/'foreign';foreign.mkdir()
    (foreign/'world.json').write_text('preserve this')
    try: desktop.prepare(assets,foreign)
    except ValueError: pass
    else: raise AssertionError('unrelated world metadata was overwritten')
    assert (foreign/'world.json').read_text()=='preserve this'
    new=tmp/'new';old=tmp/'old';invalid=tmp/'invalid' 
    for directory in (new,old,invalid): directory.mkdir()
    (new/'world.json').write_text(json.dumps(world))
    (new/'navigation.json').write_text(json.dumps(nav))
    (old/'world.json').write_text(json.dumps(dict(kind='voxel',hub=[0,4,0],
        heightmap=dict(origin=[0,0],size=[2,2],heights=[1,2,3,4]))))
    broken=dict(world,fog=[1,2])
    (invalid/'world.json').write_text(json.dumps(broken))
    (tmp/'World.swift').write_text('import Foundation\n'+model)
    (tmp/'Test.swift').write_text('''import Foundation
@main struct Tests {
 static func main() {
  let root=CommandLine.arguments[1]
  let w=World3D.load(root+"/new")
  precondition(w.kind == .voxel && w.ambientAnimation)
  precondition(w.navigation != nil && w.navigation!.valid)
  let n=w.navigation!, p=n.spawn
  precondition(abs(w.ground(p[0],p[1])-n.ground(p[0],p[1])!) < 1e-8)
  precondition(w.workspaceRail.count == 1)
  precondition(abs(w.workspaceRail[0].y-w.ground(p[0],p[1])-n.eye_height-2) < 1e-8)
  precondition(w.fog?.count == 8 && w.fog![0] == 0.003)
  precondition(w.sun!.lux == 22000 && w.iblIntensity == 5000)
  precondition(w.cameraDolly == 0)
  let old=World3D.load(root+"/old")
  precondition(old.navigation == nil && old.fog == nil)
  precondition(old.ground(0,1) == 2 && old.ground(1,0) == 3)
  precondition(World3D.load(root+"/invalid").fog == nil)
  print("Desktop profile: actual Swift loader accepts navigation, rail, lighting and fog; legacy heightmap preserved")
 }
}''')
    subprocess.run(['swiftc',str(tmp/'World.swift'),
        str(ROOT/'shell/Sources/DesktopShellApp/Compositor/WorldNavigation.swift'),
        str(tmp/'Test.swift'),'-o',str(tmp/'test')],check=True)
    subprocess.run([str(tmp/'test'),str(tmp)],check=True)
