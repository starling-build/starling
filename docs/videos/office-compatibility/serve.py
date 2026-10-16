#!/usr/bin/env python3
"""Serve only the video review assets, including byte ranges for mobile Safari."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import re
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[3] / 'artifacts/office-compatibility'
FILES = {
    '/video.mp4': ('starling-office-compatibility.mp4', 'video/mp4'),
    '/script.txt': ('script.txt', 'text/plain; charset=utf-8'),
    '/captions.srt': ('captions.srt', 'application/x-subrip'),
    '/poster.png': ('frames/v2-01-problem.png', 'image/png'),
}
PAGE = b'''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Starling Office compatibility video</title>
<style>body{margin:0;background:#f5f7fc;color:#16243c;font:17px/1.5 system-ui,sans-serif}
main{max-width:1000px;margin:auto;padding:24px 16px}h1{font-size:clamp(24px,5vw,38px);line-height:1.15}
.brand{color:#2849df;font-weight:750;font-size:15px}video{display:block;width:100%;aspect-ratio:16/9;background:#15233b;border-radius:12px}
nav{display:flex;gap:12px;flex-wrap:wrap;margin-top:22px}a{color:#2849df;padding:10px 14px;background:white;border:1px solid #dce2ef;border-radius:8px;text-decoration:none}
p{color:#64718a}</style><main><div class="brand">STARLING OFFICE</div>
<h1>Compatibility, one document at a time.</h1><p>__DURATION__ &middot; Revised walkthrough &middot; Captions included</p>
<video controls playsinline preload="metadata" poster="/poster.png"><source src="/video.mp4?v=2" type="video/mp4"></video>
<nav><a href="/video.mp4?v=2">Open video directly</a><a href="/video.mp4?v=2" download="starling-office-compatibility.mp4">Download video</a><a href="/script.txt">Read the script</a></nav>
<p>Microsoft reference PDFs, Starling exports, the actual comparison command, and red difference masks showing improvements and remaining gaps.</p>
<p>Real Word, PowerPoint and Excel comparisons. Development snapshot: October 16, 2026. Synthetic narration.</p></main></html>'''
timeline = json.loads((ROOT / 'timeline.json').read_text())
seconds = round(timeline[-1]['start'] + timeline[-1]['duration'])
PAGE = PAGE.replace(b'__DURATION__', f'{seconds//60}:{seconds%60:02}'.encode())

class Handler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.respond(False)

    def do_GET(self):
        self.respond(True)

    def respond(self, body):
        route = urlsplit(self.path).path
        if route == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(PAGE)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            if body:
                self.wfile.write(PAGE)
            return
        if route not in FILES:
            self.send_error(404)
            return
        name, mime = FILES[route]
        path = ROOT / name
        size = path.stat().st_size
        start, end, status = 0, size - 1, 200
        requested = self.headers.get('Range')
        if requested:
            match = re.fullmatch(r'bytes=(\d*)-(\d*)', requested.strip())
            if not match or not any(match.groups()):
                self.send_error(400, 'Expected one byte range')
                return
            first, last = match.groups()
            if first:
                start = int(first)
                end = min(int(last), size - 1) if last else size - 1
            else:
                start = max(0, size - int(last))
            if start >= size or end < start:
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{size}')
                self.send_header('Content-Length', '0')
                self.end_headers()
                return
            status = 206
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Content-Length', str(end - start + 1))
        self.send_header('Cache-Control', 'no-cache')
        if status == 206:
            self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.end_headers()
        if body:
            try:
                with path.open('rb') as source:
                    source.seek(start)
                    remaining = end - start + 1
                    while remaining:
                        chunk = source.read(min(remaining, 256 * 1024))
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                pass

if __name__ == '__main__':
    ThreadingHTTPServer(('0.0.0.0', 8095), Handler).serve_forever()
