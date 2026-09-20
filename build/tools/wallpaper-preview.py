#!/usr/bin/env python3
"""Local interactive Filament preview. Run with --world /path/to/wallpaper-city."""
import argparse
import importlib.util
import io
import json
import math
import os
from pathlib import Path
import subprocess
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from PIL import Image

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('city', HERE/'wallpaper-city.py')
city = importlib.util.module_from_spec(spec)
spec.loader.exec_module(city)


class Walker:
    """Conservative pedestrian corridor, not a collision mesh for the whole city.

    Bounds include body clearance from buildings, railings and basin edges.
    Small swept steps prevent a delayed input from crossing excluded areas.
    """
    def __init__(self, data=None):
        self.navigation = city.navigation.Navigation(data or city.navigation.description(city.ground, city.waterfront))
        self.reset()

    def reset(self):
        self.x, self.z, self.yaw, self.pitch = self.navigation.data['spawn']
        self.y = self.floor(self.z) + self.navigation.data['eye_height']

    def allowed(self, x, z): return self.navigation.allowed(x, z)

    def floor(self, z): return self.navigation.floor(self.x, z)

    def update(self, keys, dt, look):
        dt = min(.1, max(0., dt))
        if 'Home' in keys: self.reset(); return
        self.yaw = (self.yaw + max(-100., min(100., look[0]))*.16
                    + (('ArrowRight' in keys)-('ArrowLeft' in keys))*65*dt) % 360
        self.pitch = max(-85., min(70., self.pitch + max(-100., min(100., look[1]))*.16
                    + (('ArrowDown' in keys)-('ArrowUp' in keys))*50*dt))
        forward = ('KeyW' in keys)-('KeyS' in keys)
        side = ('KeyD' in keys)-('KeyA' in keys)
        norm = max(1., math.hypot(forward, side))
        speed = 3.6 if 'ShiftLeft' in keys or 'ShiftRight' in keys else 1.8
        angle = math.radians(self.yaw)
        dx = (math.sin(angle)*forward+math.cos(angle)*side)*speed*dt/norm
        dz = (-math.cos(angle)*forward+math.sin(angle)*side)*speed*dt/norm
        self.x, self.z = self.navigation.move(self.x,self.z,dx,dz)
        target = self.floor(self.z)+self.navigation.data['eye_height']
        self.y += (target-self.y)*(1-math.exp(-16*dt))


class Renderer:
    def __init__(self, world, log):
        self.width, self.height = 960, 600
        read_fd, write_fd = os.pipe()
        self.output = os.fdopen(read_fd, 'rb')
        self.log = open(log, 'w')
        env = {**os.environ, **city.LIGHTING, 'ROOMTEST_STREAM': '1'}
        env.pop('ROOMTEST_PATH', None)
        self.process = subprocess.Popen([str(city.ROOT/'.build-shared/roomtest'),
            str(world/'room.glb'), str(world/'room_ibl.ktx'), str(world/'room_skybox.ktx'),
            f'/dev/fd/{write_fd}', str(self.width), str(self.height)],
            stdin=subprocess.PIPE, stdout=self.log, stderr=self.log,
            pass_fds=(write_fd,), env=env)
        os.close(write_fd)
        self.started = time.monotonic()

    def frame(self, walker):
        sample = (time.monotonic()-self.started, walker.x, walker.y,
                  walker.z, walker.yaw, walker.pitch)
        self.process.stdin.write((','.join(map(str, sample))+'\n').encode())
        self.process.stdin.flush()
        pixels = self.output.read(self.width*self.height*3)
        if len(pixels) != self.width*self.height*3:
            raise RuntimeError('Renderer stopped; see preview log')
        result = io.BytesIO()
        Image.frombytes('RGB', (self.width, self.height), pixels).save(result, 'JPEG', quality=88)
        return result.getvalue()

    def close(self):
        self.process.terminate()
        try: self.process.wait(timeout=5)
        except subprocess.TimeoutExpired: self.process.kill(); self.process.wait()
        self.output.close()
        self.process.stdin.close()
        self.log.close()


PAGE = '''<!doctype html><meta charset="utf-8"><title>Wallpaper city — walking preview</title>
<style>body{margin:0;background:#22232b;color:#f6d8b7;font:16px system-ui;text-align:center}
header{padding:16px}img{display:block;width:min(100%,1200px,calc((100dvh - 180px)*1.6));margin:auto;cursor:grab}
p{margin:8px}button{font:inherit;padding:6px 14px;background:#f6d8b7;border:0;border-radius:6px}</style>
<header><b>Wallpaper city · interactive walking preview</b><p>WASD walk · Shift faster · arrows look · drag to look · Home reset</p>
<p>Walk right to the sidewalk, then head downhill through the shops to the quay.</p>
<button id="reset">Return to hillside</button> <span id="status">Loading the world…</span></header>
<img id="view" draggable="false" alt="Live rendering of the sunset city">
<script>
const keys=new Set(), view=document.querySelector('#view'), status=document.querySelector('#status');
let look=[0,0], last=performance.now(), dragging=false, url;
const controls=new Set(['KeyW','KeyA','KeyS','KeyD','ShiftLeft','ShiftRight','Home','ArrowLeft','ArrowRight','ArrowUp','ArrowDown']);
onkeydown=e=>{if(controls.has(e.code)){e.preventDefault();keys.add(e.code)}};
onkeyup=e=>keys.delete(e.code);
onblur=()=>{keys.clear();dragging=false;look=[0,0]};
document.onvisibilitychange=()=>{keys.clear();dragging=false};
view.onpointerdown=e=>{dragging=true;view.setPointerCapture(e.pointerId)};
view.onpointerup=()=>dragging=false;view.onpointercancel=()=>dragging=false;
view.onpointermove=e=>{if(dragging){look[0]+=e.movementX;look[1]+=e.movementY}};
document.querySelector('#reset').onclick=()=>keys.add('Home');
async function tick(){
 try{
  const now=performance.now(), dt=Math.min(.1,(now-last)/1000);last=now;
  const movement=look;look=[0,0];
  const response=await fetch('/frame',{method:'POST',headers:{'Content-Type':'application/json'},
   body:JSON.stringify({keys:[...keys],dt:document.hidden?0:dt,look:movement})});
  keys.delete('Home');if(!response.ok)throw Error(await response.text());
  const next=URL.createObjectURL(await response.blob());view.src=next;
  if(url)URL.revokeObjectURL(url);url=next;
  status.textContent='Live · bounded pedestrian route';
  setTimeout(tick,document.hidden?500:0);
 }catch(e){status.textContent='Preview stopped: '+e.message}
}tick();
</script>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--world', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8766)
    args = parser.parse_args()
    for name in ('room.glb', 'room_ibl.ktx', 'room_skybox.ktx'):
        if not (args.world/name).is_file(): parser.error(f'Missing {name}')
    route = args.world/'navigation.json'
    walker, lock = Walker(json.loads(route.read_text()) if route.exists() else None), threading.Lock()
    renderer = Renderer(args.world, args.world/'interactive-preview.log')

    class Handler(BaseHTTPRequestHandler):
        def reply(self, code, data, content_type):
            try:
                self.send_response(code)
                self.send_header('Content-Type', content_type)
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Cache-Control', 'no-store')
                self.end_headers()
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError): pass

        def do_GET(self):
            if self.path != '/': self.reply(404, b'Not found', 'text/plain'); return
            self.reply(200, PAGE.encode(), 'text/html; charset=utf-8')

        def do_POST(self):
            if self.path != '/frame': self.reply(404, b'Not found', 'text/plain'); return
            # JSON-only same-origin requests; do not expose this local controller cross-origin.
            if self.headers.get('Content-Type') != 'application/json':
                self.reply(415, b'JSON required', 'text/plain'); return
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 4096: raise ValueError('Invalid request size')
                data = json.loads(self.rfile.read(size))
                keys, dt, look = data['keys'], float(data['dt']), data['look']
                if not isinstance(keys, list) or not all(isinstance(k,str) for k in keys):
                    raise ValueError('Invalid keys')
                if len(look) != 2 or not all(math.isfinite(float(v)) for v in [dt, *look]):
                    raise ValueError('Invalid movement')
                with lock:
                    walker.update(keys, dt, list(map(float, look)))
                    jpeg = renderer.frame(walker)
                self.reply(200, jpeg, 'image/jpeg')
            except (ValueError, KeyError, TypeError) as error:
                self.reply(400, str(error).encode(), 'text/plain')
            except (RuntimeError, BrokenPipeError) as error:
                self.reply(503, str(error).encode(), 'text/plain')

        def log_message(self, *_): pass

    def stop(*_): raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, stop)
    try:
        with ThreadingHTTPServer(('127.0.0.1', args.port), Handler) as server:
            print(f'Walking preview: http://127.0.0.1:{args.port}', flush=True)
            server.serve_forever()
    except KeyboardInterrupt: pass
    finally: renderer.close()


if __name__ == '__main__': main()
