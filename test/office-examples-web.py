#!/usr/bin/env python3
"""Check the public Office examples through real browser startup and Save.

Requires Node and Chrome, like build/tools/web-drive.mjs. Override --slides-url
and --sheets-url to check staged sites before publishing. No user files are used.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--slides-url', default='https://slides.starling.build/')
parser.add_argument('--sheets-url', default='https://sheets.starling.build/')
parser.add_argument('--load-ms', type=int, default=20000)
opts = parser.parse_args()

with tempfile.TemporaryDirectory(prefix='starling-office-examples-') as directory:
    out = Path(directory)
    for index, (app, name, url) in enumerate([
            ('slides', 'garden-presentation.pptx', opts.slides_url),
            ('sheets', 'garden-budget.xlsx', opts.sheets_url)]):
        downloads = out / app
        downloads.mkdir()
        # Read-only debug queries identify the document; Ctrl+S uses the editor's
        # real save command. Checking the saved package catches a named blank file.
        check = "(() => { const name = window.starling?.debug('name'); if (name !== " + json.dumps(name) + ") throw Error('Wrong startup document: ' + name); return name; })()"
        env = dict(os.environ, URL=url, PORT=str(int(os.environ.get('DEVTOOLS', '9347')) + index),
                   CHROME_PROFILE=str(out / (app + '-chrome')), W='1440', H='1000')
        subprocess.run(['node', str(ROOT / 'build/tools/web-drive.mjs'),
                        'wait', str(opts.load_ms), 'eval', check,
                        'downloads', str(downloads), 'chord', 'ctrl', 's', 'wait', '3000'],
                       env=env, check=True, timeout=opts.load_ms / 1000 + 90)
        with ZipFile(downloads / name) as archive:
            assert archive.testzip() is None
            if app == 'slides':
                slides = [n for n in archive.namelist() if re.fullmatch(r'ppt/slides/slide\d+\.xml', n)]
                assert len(slides) == 4, slides
                title = ''.join(ET.fromstring(archive.read('ppt/slides/slide1.xml')).itertext())
                assert 'Good things' in title and 'grow together.' in title, title
                assert 'ppt/charts/chart1.xml' in archive.namelist()
            else:
                ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
                sheet = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
                assert sheet.find('.//s:c[@r="D5"]/s:f', ns).text == 'B5-C5'
                assert sheet.find('.//s:c[@r="B5"]/s:v', ns).text == '2400'
                assert 'xl/charts/chart1.xml' in archive.namelist()
        print(f'PASS: {app} opens its populated example and saves its contents', flush=True)
