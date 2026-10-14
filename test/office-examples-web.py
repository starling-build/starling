#!/usr/bin/env python3
"""Check the public Office examples through real browser startup and Save.

Requires Node and Chrome, like build/tools/web-drive.mjs. Override --writer-url,
--slides-url and --sheets-url to check staged sites. No user files are used.
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
parser.add_argument('--writer-url', default='https://writer.starling.build/')
parser.add_argument('--slides-url', default='https://slides.starling.build/')
parser.add_argument('--sheets-url', default='https://sheets.starling.build/')
parser.add_argument('--load-ms', type=int, default=20000)
opts = parser.parse_args()

with tempfile.TemporaryDirectory(prefix='starling-office-examples-') as directory:
    out = Path(directory)
    for index, (app, name, url) in enumerate([
            ('writer', 'garden-brief.docx', opts.writer_url),
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
            if app == 'writer':
                ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
                document = ET.fromstring(archive.read('word/document.xml'))
                assert 'Care for the season ahead' in ''.join(document.itertext())
                assert len(document.findall('.//w:tbl', ns)) == 2
                assert document.findall('.//w:drawing', ns), 'Picture lost'
                assert document.findall('.//w:hyperlink', ns), 'Link lost'
                assert any(n.startswith('word/header') for n in archive.namelist())
                assert any(n.startswith('word/footer') for n in archive.namelist())
            elif app == 'slides':
                slides = [n for n in archive.namelist() if re.fullmatch(r'ppt/slides/slide\d+\.xml', n)]
                assert len(slides) == 9, slides
                title = ''.join(ET.fromstring(archive.read('ppt/slides/slide1.xml')).itertext())
                assert 'Good things' in title and 'grow together.' in title, title
                charts = [n for n in archive.namelist() if re.fullmatch(r'ppt/charts/chart\d+\.xml', n)]
                assert len(charts) == 7, charts
                ns = {'p': 'http://schemas.openxmlformats.org/presentationml/2006/main',
                      'a': 'http://schemas.openxmlformats.org/drawingml/2006/main'}
                animated = ET.fromstring(archive.read('ppt/slides/slide3.xml'))
                assert animated.find('.//p:timing//p:cTn[@presetID="22"]', ns) is not None, 'Wipe entrance lost'
                assert 'ppt/diagrams/data1.xml' in archive.namelist(), 'SmartArt lost'
                assert ET.fromstring(archive.read('ppt/slides/slide9.xml')).find('.//a:prstTxWarp', ns) is not None
                assert sum(n.startswith('ppt/notesSlides/notesSlide') and n.endswith('.xml') for n in archive.namelist()) == 9
            else:
                ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
                workbook = ET.fromstring(archive.read('xl/workbook.xml'))
                assert [s.attrib['name'] for s in workbook.findall('s:sheets/s:sheet', ns)] == [
                    'Garden budget', 'Season', 'Volunteers', 'Explore', 'Protected plan']
                sheet = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
                assert sheet.find('.//s:c[@r="D5"]/s:f', ns).text == 'B5-C5'
                assert sheet.find('.//s:c[@r="B5"]/s:v', ns).text == '2400'
                assert 'xl/charts/chart1.xml' in archive.namelist()
                assert sheet.find('s:conditionalFormatting', ns) is not None
                assert sheet.find('s:dataValidations', ns) is not None
                assert sheet.find('s:tableParts', ns) is not None
                assert sheet.find('.//s:pane', ns) is not None
                explore = ET.fromstring(archive.read('xl/worksheets/sheet4.xml'))
                for cell, value in [('B5', '24'), ('B6', '9'), ('B13', '48'), ('B14', '24')]:
                    assert explore.find(f'.//s:c[@r="{cell}"]/s:v', ns).text == value, cell
                assert 'UNIQUE' in explore.find('.//s:c[@r="A18"]/s:f', ns).text
                protected = ET.fromstring(archive.read('xl/worksheets/sheet5.xml'))
                assert protected.find('s:sheetProtection', ns) is not None
                for path in [n for n in archive.namelist() if re.fullmatch(r'xl/worksheets/sheet\d+\.xml', n)]:
                    errors = ET.fromstring(archive.read(path)).findall('.//s:c[@t="e"]', ns)
                    assert not errors, (path, [e.attrib['r'] for e in errors])
        print(f'PASS: {app} opens its populated example and saves its contents', flush=True)
