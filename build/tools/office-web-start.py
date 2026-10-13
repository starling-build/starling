#!/usr/bin/env python3
"""Configure a staged Office page to open its bundled, editable example."""
import argparse
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]
EXAMPLES = {
    'writer': 'garden-brief.docx',
    'slides': 'garden-presentation.pptx',
    'sheets': 'garden-budget.xlsx',
}

def configure(site: Path, app: str) -> None:
    name = EXAMPLES[app]
    page = site / 'index.html'
    html = page.read_text()
    # Use Office's normal file-opening path and the host's startup-file bridge.
    # The first argument chooses the correct editor from the file extension.
    config = ('args: ' + json.dumps([name]) + ',\n    initialFiles: '
              + json.dumps([{'name': name, 'url': 'examples/' + name}]) + ',')
    html = re.sub(r'\s*initialFiles: \[[^\n]*\],', '', html)
    html, count = re.subn(r'args: \[[^\n]*\],', lambda _: config, html)
    if count != 1:
        raise ValueError('Expected exactly one args array in the staged index.html')
    (site / 'examples').mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'web/office/examples' / name, site / 'examples' / name)
    page.write_text(html)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('site', type=Path)
    parser.add_argument('app', choices=EXAMPLES)
    opts = parser.parse_args()
    configure(opts.site, opts.app)
