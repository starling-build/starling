#!/usr/bin/env python3
"""Exercise bookmark navigation through real browser pointer/keyboard events.

Build/serve OfficeApp first, then:
    python3 test/writer-links-web.py --out /tmp/writer-links-check
Each route opens a fresh browser; evidence includes screenshots and layout dumps.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def fixture(path):
    parts = {
        "[Content_Types].xml": '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
        "_rels/.rels": '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
        "word/_rels/document.xml.rels": '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com/" TargetMode="External"/></Relationships>',
        "word/document.xml": '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>'
            '<w:p><w:hyperlink w:anchor="destination"><w:r><w:rPr><w:color w:val="0000FF"/><w:u w:val="single"/></w:rPr><w:t>Jump to section</w:t></w:r></w:hyperlink></w:p>'
            '<w:p><w:hyperlink r:id="rId1"><w:r><w:rPr><w:color w:val="0000FF"/><w:u w:val="single"/></w:rPr><w:t>Open external website</w:t></w:r></w:hyperlink></w:p>'
            '<w:p><w:pPr><w:pageBreakBefore/></w:pPr><w:bookmarkStart w:id="1" w:name="destination"/><w:r><w:t>Destination section</w:t></w:r><w:bookmarkEnd w:id="1"/></w:p>'
            '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>',
    }
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, contents in parts.items():
            archive.writestr(name, contents)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8165/")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--load-ms", type=int, default=8000)
    parser.add_argument("--port", type=int, default=9780)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = out / "links.docx"
    fixture(source)
    routes = {
        "control-click": ["modclick", "ctrl", "468", "354"],
        "context-menu": ["rightclick", "468", "354", "click", "515", "371"],
        "touch": ["touchdrag", "468", "354", "0", "0"],
    }
    for index, (name, actions) in enumerate(routes.items()):
        layout = out / f"{name}.txt"
        check = 'if(window.linkOpens.length)throw Error("Bookmark opened browser");if(location.href!==window.initialURL)throw Error("Navigated away");if(window.starling.debug("name")!=="links.docx")throw Error("Document replaced");true'
        commands = [
            "wait", str(args.load_ms), "chord", "ctrl", "o", "wait", "500", "setfile", str(source), "wait", "2000",
            "eval", 'window.initialURL=location.href;window.linkOpens=[];const originalOpen=window.open;window.open=function(...args){window.linkOpens.push(args);return originalOpen.apply(this,args)};true',
            *actions, "wait", "500", "eval", check, "shot", str(out / f"{name}.png"),
            "type", "NAVIGATED ", "dump", "layout", str(layout),
        ]
        env = {**os.environ, "URL": args.url, "W": "1440", "H": "1000", "DPR": "1",
               "PORT": str(args.port + index), "CHROME_PROFILE": str(out / f"profile-{name}")}
        with (out / f"{name}.log").open("w") as log:
            subprocess.run(["node", str(ROOT / "build/tools/web-drive.mjs"), *commands],
                           cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=150)
        assert "|NAVIGATED Destination section|" in layout.read_text(), f"{name}: caret did not reach destination"
        print(f"PASS {name}: stayed in document and edited destination", flush=True)
    (out / "results.json").write_text(json.dumps({"url": args.url, "passed": list(routes)}, indent=2) + "\n")


if __name__ == "__main__":
    main()
