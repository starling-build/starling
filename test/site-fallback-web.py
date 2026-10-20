#!/usr/bin/env python3
"""Published text, navigation and downloads survive web runtime failures.

Builds a temporary publication and uses isolated headless Chrome on localhost.
Requires the native OfficeApp and a current web stage.
"""
import copy
import json
import os
from pathlib import Path
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


with tempfile.TemporaryDirectory(prefix="starling-fallback-web-") as folder:
    root = Path(folder)
    artifacts = Path(os.environ.get("ARTIFACT_DIR", root))
    artifacts.mkdir(parents=True, exist_ok=True)
    repo, output = root / "repo", root / "www/handbook"
    (repo / "pages").mkdir(parents=True)
    output.parent.mkdir()
    config = {"title": "Reader handbook", "base": "/handbook/", "home": "intro", "pages": [
        {"slug": "intro", "title": "Introduction"}, {"slug": "chapter", "title": "Chapter"},
        {"slug": "empty", "title": "Empty page"}],
        "details": {"version": 1, "byline": "An author", "language": "en"}}
    (repo / "site.json").write_text(json.dumps(config))
    source = json.loads((ROOT / "examples/site/pages/about.json").read_text())
    for slug, title in [("intro", "A readable introduction"), ("chapter", "Another chapter"), ("empty", "")]:
        page = copy.deepcopy(source)
        paragraphs = page["document"]["paragraphs"]
        paragraphs[0]["text"] = title
        paragraphs[0]["runs"] = [{"length": len(title), "style": {}}]
        if slug == "empty":
            page["document"]["paragraphs"] = paragraphs[:1]
        else:
            paragraphs[0]["bookmarks"] = ["opening"]
            paragraphs.extend([
                {"id": 52, "text": "Read the source", "style": {},
                 "runs": [{"length": 15, "style": {"link": "https://example.org/reference?x=1&y=2"}}]},
                {"id": 53, "text": "Jump to heading", "style": {},
                 "runs": [{"length": 15, "style": {"link": "#opening"}}]},
                {"id": 54, "text": "Unsafe reference stays text", "style": {},
                 "runs": [{"length": 27, "style": {"link": "javascript:alert(1)"}}]},
            ])
            for paragraph in paragraphs[-3:]:
                paragraph.update(bookmarks=[], inlineImages={})
        (repo / "pages" / (slug + ".json")).write_text(json.dumps(page))
    subprocess.run([str(APP), "--site-build", str(repo), "--out", str(output), "--web", str(STAGE)],
                   check=True, capture_output=True, text=True, timeout=90)
    port = free_port()
    origin = f"http://127.0.0.1:{port}"
    server = subprocess.Popen(["python3", str(ROOT / "build/tools/web-serve.py"), str(output.parent), str(port)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try:
                with urllib.request.urlopen(origin + "/handbook/manifest.json", timeout=1):
                    break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError("Local server did not start")

        def drive(name, path="/handbook/", blocked=None, scripts=True, actions=()):
            env = dict(os.environ, URL=origin + path, PORT=str(free_port()), W="1000", H="800",
                       CHROME_PROFILE=str(root / ("chrome-" + name)),
                       BLOCK_URLS=json.dumps(blocked or []), DISABLE_SCRIPTS="0" if scripts else "1")
            result = subprocess.run(["node", str(ROOT / "build/tools/web-drive.mjs"), *actions],
                                    env=env, text=True, capture_output=True, timeout=60)
            assert result.returncode == 0, result.stdout + result.stderr
            # Startup failures intentionally log exceptions. Assertions inspect usable output.
            return [json.loads(line[6:]) for line in result.stdout.splitlines() if line.startswith("eval: ")]

        state = """(() => {
          const main = document.getElementById('starling-text'), rect = main.getBoundingClientRect();
          return { readable:rect.width > 300 && rect.height > 100 && getComputedStyle(main).clip === 'auto',
            text:main.innerText, interactive:document.body.classList.contains('starling-interactive'),
            canvas:getComputedStyle(document.getElementById('starling')).visibility,
            nav:[...main.querySelectorAll('nav a')].map(a => a.href),
            downloads:[...main.querySelectorAll('.starling-downloads a')].map(a => a.href),
            references:[...main.querySelectorAll('#starling-article > p:not(.starling-downloads) a')].map(a => a.href),
            anchors:[...main.querySelectorAll('#starling-article [id]')].map(p => p.id),
            title:document.title };
        })()"""

        cases = [
            ("missing-module", ["*/starling.js"], True),
            ("missing-app", ["*/app.wasm"], True),
            ("missing-renderer", ["*/skwasm.wasm"], True),
            ("missing-font", ["*/fonts/*.ttf"], True),
            ("scripts-off", [], False),
        ]
        for name, blocked, scripts in cases:
            value = drive(name, blocked=blocked, scripts=scripts, actions=("wait", "8000", "eval", state))[-1]
            assert value["readable"] and not value["interactive"], (name, value)
            assert value["canvas"] == "hidden", (name, value)
            assert "A readable introduction" in value["text"] and "An author" in value["text"], (name, value)
            assert value["title"] == "Introduction — Reader handbook", (name, value)
            assert len(value["nav"]) == 3 and len(value["downloads"]) == 2, (name, value)
            assert len(value["references"]) == 2, (name, value)
            assert value["references"][0] == "https://example.org/reference?x=1&y=2", (name, value)
            assert value["references"][1] in [origin + "/handbook/intro/#p=1511220328",
                                              origin + "/handbook/intro/?reader=text#p=1511220328"], (name, value)
            assert "p=1511220328" in value["anchors"], (name, value)
            for link in value["downloads"]:
                with urllib.request.urlopen(link) as response:
                    data = response.read()
                    assert data.startswith(b"%PDF") if link.endswith(".pdf") else data.startswith(b"PK"), link
            # Follow the rendered link with the same failure, including its text preference.
            chapter = value["nav"][1].removeprefix(origin)
            next_page = drive(name + "-chapter", path=chapter, blocked=blocked, scripts=scripts,
                              actions=("wait", "1000", "eval", state))[-1]
            assert next_page["readable"] and "Another chapter" in next_page["text"], (name, next_page)
            assert next_page["references"][1] in [origin + "/handbook/chapter/#p=1511220328",
                                                 origin + "/handbook/chapter/?reader=text#p=1511220328"], (name, next_page)
            print("PASS:", name, "leaves readable text, navigation and PDF/Word downloads", flush=True)

        for name, path in [("empty", "/handbook/empty/"), ("unknown", "/handbook/404.html")]:
            value = drive(name, path=path, scripts=False, actions=("eval", state))[-1]
            assert value["readable"] and len(value["nav"]) == 3, value
            if name == "empty":
                assert len(value["downloads"]) == 2, value
            else:
                assert "could not be found" in value["text"], value
            print("PASS:", name, "remains navigable without scripts", flush=True)

        values = drive("healthy", actions=(
            "wait", "12000", "eval", state,
            "eval", "document.getElementById('starling-reader-toggle').click(); true",
            "eval", state,
            "shot", str(artifacts / "publication-text-view.png"),
            "eval", "document.getElementById('starling-reader-toggle').click(); true",
            "eval", state,
            "eval", "window.dispatchEvent(new ErrorEvent('error', { message:'simulated runtime failure' })); true",
            "eval", state))
        assert values[0]["interactive"] and not values[0]["readable"], values
        assert values[2]["readable"] and "A readable introduction" in values[2]["text"], values
        assert values[2]["references"][0] == "https://example.org/reference?x=1&y=2", values
        assert "p=1511220328" in values[2]["anchors"], values
        assert "reader=text" in values[2]["nav"][1], values
        assert values[4]["interactive"], values
        assert values[6]["readable"] and not values[6]["interactive"], values
        print("PASS: healthy reader switches between interactive/text and recovers from a runtime error", flush=True)
        values = drive("text-preference", path="/handbook/chapter/?reader=text",
                       actions=("wait", "12000", "eval", state,
                                "eval", "document.getElementById('starling-reader-toggle').focus(); true",
                                "press", "Tab", "eval", "[document.activeElement.tagName, document.activeElement.href]"))
        value = values[0]
        assert value["readable"] and not value["interactive"] and "Another chapter" in value["text"], value
        assert values[-1] == ["A", origin + "/handbook/?reader=text"], values
        print("PASS: text preference survives navigation with a healthy runtime", flush=True)
        print("PASS: keyboard focus reaches visible publication links in text view", flush=True)
        values = drive("bookmark", path="/handbook/chapter/?reader=text", actions=(
            "wait", "12000",
            "eval", "document.querySelector('#starling-article a[href*=\"#p=\"]').focus(); true",
            "press", "Enter", "wait", "3000",
            "eval", "[location.pathname, location.hash, new URLSearchParams(location.search).get('reader')]",
            "eval", state))
        assert values[-2] == ["/handbook/chapter/", "#p=1511220328", "text"], values
        assert values[-1]["readable"] and "Another chapter" in values[-1]["text"], values
        print("PASS: a document bookmark stays on its chapter and preserves text view", flush=True)
    finally:
        server.terminate()
        server.wait(timeout=5)
