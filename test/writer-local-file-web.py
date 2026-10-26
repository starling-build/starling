#!/usr/bin/env python3
"""Exercise local Word import, real keyboard edits, download, and fresh-session reopen.

Uses a copy of the Microsoft Word fixture, never a user's document. Requires
Chrome and Node like web-drive.mjs. Evidence stays in a new --out directory.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'apps/OfficeApp/Tests/OfficeAppTests/Fixtures/word-boringcrypto.docx'
NAME = 'word-workflow.docx'
TITLE = 'Browser workflow verification.'
BODY = 'Opened locally, edited online, and saved as a Word document.'
SECOND = 'Reopened copy - second edit.'
NS = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_package(original, saved, second=False):
    with ZipFile(original) as before, ZipFile(saved) as after:
        assert after.testzip() is None, 'Corrupt downloaded DOCX'
        a = ET.fromstring(before.read('word/document.xml'))
        b = ET.fromstring(after.read('word/document.xml'))
        text = lambda root: ''.join(n.text or '' for n in root.findall('.//w:t', NS))
        prefix = (SECOND if second else '') + TITLE + BODY
        assert text(b) == prefix + text(a), 'Original text changed or edits missing/duplicated'
        assert len(a.findall('.//w:tbl', NS)) == len(b.findall('.//w:tbl', NS)), 'Tables lost'
        assert len(a.findall('.//w:drawing', NS)) == len(b.findall('.//w:drawing', NS)), 'Pictures lost'
        for name in before.namelist():
            if name.startswith(('word/media/', 'word/header', 'word/footer')):
                assert before.read(name) == after.read(name), f'Changed or missing {name}'
        def links(archive):
            rels = ET.fromstring(archive.read('word/_rels/document.xml.rels'))
            return {r.get('Target') for r in rels if r.get('Type', '').endswith('/hyperlink')}
        assert links(before) == links(after), 'Hyperlink destinations changed'
        for label, bold in [(TITLE, True), (BODY, False)]:
            paragraph = next(p for p in b.findall('w:body/w:p', NS) if text(p) == label)
            runs = [r for r in paragraph.findall('w:r', NS) if text(r)]
            assert runs, label
            for run in runs:
                value = run.find('w:rPr/w:b', NS)
                actual = value is not None and value.get('{'+NS['w']+'}val', '1') not in ('0', 'false', 'off')
                assert actual == bold, f'Bold formatting changed: {label}'
        return {'original_characters': len(text(a)), 'tables': len(a.findall('.//w:tbl', NS)),
                'pictures': len(a.findall('.//w:drawing', NS))}


def drive(out, phase, index, source, actions, url, port, load_ms, entry_page=False):
    check = '(() => { const name = window.starling?.debug("name"); if (name !== ' + json.dumps(NAME) + ') throw Error("Wrong file: " + name); return name; })()'
    env = dict(os.environ, URL=url, PORT=str(port + index), W='1440', H='1000',
               CHROME_PROFILE=str(out / (phase + '-profile')))
    opening = (['wait', '1000', 'setfile', str(source), 'wait', str(load_ms)] if entry_page else
               ['wait', str(load_ms), 'chord', 'ctrl', 'o', 'wait', '400', 'setfile', str(source), 'wait', '6000'])
    cmd = ['node', str(ROOT / 'build/tools/web-drive.mjs'), *opening,
           'eval', check, *map(str, actions)]
    with (out / (phase + '.log')).open('w') as log:
        subprocess.run(cmd, env=env, check=True, timeout=150, stdout=log, stderr=subprocess.STDOUT)


def run(out, url, port, load_ms, entry_page=False):
    out.mkdir(parents=True, exist_ok=False)
    for directory in ['input', 'first-save', 'second-save']:
        (out / directory).mkdir()
    original = out / 'input' / NAME
    first, second = out / 'first-save' / NAME, out / 'second-save' / NAME
    original_hash = digest(SOURCE)
    shutil.copyfile(SOURCE, original)
    drive(out, 'edit', 0, original, [
        'click', 410, 351, 'chord', 'ctrl', 'Home', 'chord', 'ctrl', 'b',
        'type', TITLE, 'chord', 'ctrl', 'b', 'press', 'Enter', 'type', BODY, 'wait', 800,
        'dump', 'layout', out/'edited-layout.txt', 'downloads', first.parent,
        'chord', 'ctrl', 's', 'wait', 3000, 'shot', out/'saved.png'], url, port, load_ms, entry_page)
    result = check_package(original, first)
    print('PASS first download: edits, bold, original text, tables, images, footer and links', flush=True)
    drive(out, 'reopen-edit', 1, first, [
        'dump', 'layout', out/'reopened-layout.txt', 'shot', out/'reopened.png',
        'click', 410, 351, 'chord', 'ctrl', 'Home', 'type', SECOND, 'press', 'Enter', 'wait', 800,
        'dump', 'layout', out/'second-edited-layout.txt', 'downloads', second.parent,
        'chord', 'ctrl', 's', 'wait', 3000, 'shot', out/'second-saved.png'], url, port, load_ms, entry_page)
    assert (out/'edited-layout.txt').read_bytes() == (out/'reopened-layout.txt').read_bytes(), 'First reopen changed layout'
    check_package(original, second, second=True)
    print('PASS fresh-session reopen and second edit/save', flush=True)
    drive(out, 'final-reopen', 2, second, [
        'dump', 'layout', out/'final-layout.txt', 'shot', out/'final-reopened.png'], url, port, load_ms, entry_page)
    assert (out/'second-edited-layout.txt').read_bytes() == (out/'final-layout.txt').read_bytes(), 'Second reopen changed layout'
    assert digest(SOURCE) == digest(original) == original_hash, 'Original file was modified'
    result.update(url=url, original_sha256=original_hash, first_save_sha256=digest(first),
                  second_save_sha256=digest(second), fresh_browser_sessions=3,
                  saved_layout_preserved=True, original_unchanged=True)
    (out/'results.json').write_text(json.dumps(result, indent=2)+'\n')
    print('PASS second fresh-session reopen; both saved layouts and original file preserved', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True, help='New directory for downloads, screenshots and logs')
    parser.add_argument('--url', default='https://writer.starling.build/')
    parser.add_argument('--port', type=int, default=9752)
    parser.add_argument('--load-ms', type=int, default=18000)
    parser.add_argument('--entry-page', action='store_true', help='Choose the file on the product page before the editor loads')
    args = parser.parse_args()
    run(args.out.resolve(), args.url, args.port, args.load_ms, args.entry_page)
