#!/usr/bin/env python3
"""A copied home-page passage link survives choosing a different home.

Uses the native app, current web stage and headless Chrome; serves only localhost.
"""
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
APP = Path(os.environ.get("OFFICE_APP", ROOT / "apps/OfficeApp/.build/debug/OfficeApp"))
STAGE = Path(os.environ.get("STAGE", ROOT / ".stage-web-OfficeApp"))


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


with tempfile.TemporaryDirectory(prefix="starling-home-web-") as folder:
    root = Path(folder)
    repo, output = root / "repo", root / "www"
    shutil.copytree(ROOT / "examples/site", repo)
    config_path = repo / "site.json"
    config = json.loads(config_path.read_text())
    config["home"] = "sample-paper"
    config_path.write_text(json.dumps(config))

    def build():
        subprocess.run([str(APP), "--site-build", str(repo), "--out", str(output), "--web", str(STAGE)],
                       check=True, capture_output=True, text=True, timeout=90)

    build()
    port = free_port()
    origin = f"http://127.0.0.1:{port}"
    server = subprocess.Popen(["python3", str(ROOT / "build/tools/web-serve.py"), str(output), str(port)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try:
                with urllib.request.urlopen(origin + "/manifest.json", timeout=1) as response:
                    assert json.load(response)["home"] == "sample-paper"
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("Local reader server did not start")

        def drive(url, *actions):
            env = dict(os.environ, URL=url, PORT=str(free_port()), W="1400", H="900",
                       CHROME_PROFILE=str(root / "chrome"))
            result = subprocess.run(["node", str(ROOT / "build/tools/web-drive.mjs"), *actions],
                                    env=env, text=True, capture_output=True, timeout=60)
            assert result.returncode == 0, result.stdout + result.stderr
            assert "exception:" not in result.stdout, result.stdout
            return [json.loads(line[6:]) for line in result.stdout.splitlines() if line.startswith("eval: ")]

        values = drive(origin + "/", "wait", "12000",
                       "eval", "navigator.clipboard.writeText = t => { window.__copied = t; return Promise.resolve(); }; 'ready'",
                       "click", "843", "597", "wait", "300", "click", "643", "220", "wait", "500",
                       "eval", "[location.pathname, location.hash, window.__copied, starling.debug('slug'), starling.debug('caret')]")
        path, fragment, copied, slug, paragraph = values[-1]
        assert path == "/sample-paper/", values
        assert slug == "sample-paper" and fragment == "#p=" + paragraph, values
        assert copied == origin + path + fragment, values
        config["home"] = "index"
        config_path.write_text(json.dumps(config))
        build()
        assert json.loads((output / "manifest.json").read_text())["home"] == "index"
        values = drive(copied, "wait", "12000",
                       "eval", "[starling.debug('slug'), starling.debug('caret'), location.pathname]")
        assert values[-1] == ["sample-paper", paragraph, "/sample-paper/"], values
        print("PASS: a home-page passage link still opens the same paragraph after home changes")
    finally:
        server.terminate()
        server.wait(timeout=5)
