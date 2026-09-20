"""Compile and compare desktop navigation with the exported Python route."""
import importlib.util
import json
from pathlib import Path
import random
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('city',ROOT/'build/tools/wallpaper-city.py')
city=importlib.util.module_from_spec(spec); spec.loader.exec_module(city)
data=city.navigation.description(city.ground,city.waterfront)
nav=city.navigation.Navigation(data)
rng=random.Random(52)
samples=[]
for x,z in [(9.8,-5),(9.8,-40),(9.8,-82),(8.5,-100),(8.5,-121),
            (8.5,-127.8),(8.5,-129.5),(34,-130),(73.8,-130)]:
    for _ in range(150):
        dx,dz=rng.uniform(-2,2),rng.uniform(-2,2)
        xx,zz=nav.move(x,z,dx,dz)
        samples.append([x,z,dx,dz,xx,zz,nav.floor(xx,zz)])
        x,z=xx,zz
with tempfile.TemporaryDirectory() as tmp:
    tmp=Path(tmp)
    (tmp/'navigation.json').write_text(json.dumps(data))
    (tmp/'samples.json').write_text(json.dumps(samples))
    subprocess.run(['swiftc',str(ROOT/'shell/Sources/DesktopShellApp/Compositor/WorldNavigation.swift'),
                    str(ROOT/'test/city/world-navigation-test.swift'),'-o',str(tmp/'test')],check=True)
    subprocess.run([str(tmp/'test'),str(tmp/'navigation.json'),str(tmp/'samples.json')],check=True)
