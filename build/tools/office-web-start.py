#!/usr/bin/env python3
"""Configure a staged Office page to open its bundled, editable example."""
import argparse
import hashlib
import html as html_module
import json
from pathlib import Path
import re
import shutil
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from office_web_fonts import prepare_manifest

ROOT = Path(__file__).resolve().parents[2]
EXAMPLES = {
    'writer': 'garden-brief.docx',
    'slides': 'garden-presentation.pptx',
    'sheets': 'garden-budget.xlsx',
}

def configure(site: Path, app: str) -> None:
    manifest = site / 'fonts/manifest.json'
    manifest.write_text(json.dumps(prepare_manifest(json.loads(manifest.read_text())), indent=2) + '\n')
    name = EXAMPLES[app]
    page = site / 'index.html'
    html = page.read_text()
    example = ROOT / 'web/office/examples' / name
    example_version = hashlib.sha256(example.read_bytes()).hexdigest()[:16]
    # Use Office's normal file-opening path and the host's startup-file bridge.
    # The first argument chooses the correct editor from the file extension.
    config = ('args: ' + json.dumps([name]) + ',\n    initialFiles: '
              + json.dumps([{'name': name, 'url': 'examples/' + name + '?v=' + example_version}]) + ',')
    html = re.sub(r'\s*initialFiles: \[[^\n]*\],', '', html)
    html, count = re.subn(r'args: \[[^\n]*\],', lambda _: config, html)
    if count != 1:
        raise ValueError('Expected exactly one args array in the staged index.html')
    # A cached pre-example host or WASM cannot receive the startup file. Tie
    # both URLs to the bytes being published so a new page loads a matching pair.
    def version(match):
        asset = match['asset']
        digest = hashlib.sha256((site / asset).read_bytes()).hexdigest()[:16]
        return match['prefix'] + asset + '?v=' + digest + match['quote']
    html = re.sub(
        r"(?P<prefix>app:\s*['\"])(?P<asset>app\.wasm(?:\.gz)?)(?:\?[^'\"]*)?(?P<quote>['\"])",
        version, html)
    html = re.sub(
        r"(?P<prefix>from\s*['\"]\./)(?P<asset>starling\.js)(?:\?[^'\"]*)?(?P<quote>['\"])",
        version, html)
    html = re.sub(
        r"(?P<prefix>fonts:\s*['\"])(?P<asset>fonts/manifest\.json)(?:\?[^'\"]*)?(?P<quote>['\"])",
        version, html)
    # Match the final, versioned fetch URLs exactly. Refresh on every configure
    # so a previously staged page cannot preload an obsolete app or manifest.
    html = re.sub(r'<!-- office-preloads -->.*?<!-- /office-preloads -->\n?', '', html, flags=re.S)
    app_url = re.search(r"app:\s*['\"]([^'\"]+)['\"]", html).group(1)
    renderer = re.search(r"skwasmBase:\s*['\"]([^'\"]+)['\"]", html).group(1)
    fonts_url = re.search(r"fonts:\s*['\"]([^'\"]+)['\"]", html).group(1)
    preloads = '<!-- office-preloads -->\n' + ''.join(
        '<link rel="preload" as="fetch" crossorigin="anonymous" href="'
        + html_module.escape(url, quote=True) + '">\n'
        for url in [app_url, renderer + 'skwasm.wasm', fonts_url]
    ) + '<!-- /office-preloads -->\n'
    html = html.replace('</head>', preloads + '</head>', 1)
    (site / 'examples').mkdir(exist_ok=True)
    shutil.copy2(example, site / 'examples' / name)
    page.write_text(html)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('site', type=Path)
    parser.add_argument('app', choices=EXAMPLES)
    opts = parser.parse_args()
    configure(opts.site, opts.app)
