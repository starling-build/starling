#!/usr/bin/env python3
"""Serves the staged web app the way a real host should.

    web-serve.py DIR [PORT]

http.server with two things added. Precompressed files: a request for
app.wasm is answered with app.wasm.br or app.wasm.gz when the browser
accepts that encoding and the file is beside the original — which is what
build/web-app.sh puts there, and what a CDN would do. And the two headers
that let skwasm use a worker thread if it ever wants to (cross-origin
isolation); harmless otherwise.
"""
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ENCODINGS = (("br", ".br"), ("gzip", ".gz"))


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def send_head(self):
        path = self.translate_path(self.path)
        accepted = self.headers.get("Accept-Encoding", "")
        for encoding, suffix in ENCODINGS:
            if encoding in accepted and os.path.isfile(path + suffix):
                self.encoding = encoding
                self.path += suffix
                return super().send_head()
        self.encoding = None
        return super().send_head()

    def end_headers(self):
        if getattr(self, "encoding", None):
            self.send_header("Content-Encoding", self.encoding)
            self.send_header("Vary", "Accept-Encoding")
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def guess_type(self, path):
        # The type of what was asked for, not of the .br beside it:
        # compileStreaming insists on application/wasm.
        for _, suffix in ENCODINGS:
            if path.endswith(suffix):
                path = path[: -len(suffix)]
        if path.endswith(".wasm"):
            return "application/wasm"
        return super().guess_type(path)

    def log_message(self, format, *args):
        # One line per request, without the date http.server prints.
        sys.stderr.write("%s %s\n" % (self.address_string(), format % args))


if __name__ == "__main__":
    DIRECTORY = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8137
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
