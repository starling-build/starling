#!/usr/bin/env python3
"""Package office.starling.build with an existing, tested Office web runtime.

Usage: python3 build/office-product.py --runtime /path/to/deployed-writer --out /tmp/office-product
Accepts a staged web build or a deployment checkout. Does not publish anything.
"""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil
import sys
from string import Template

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'build/tools'))
from office_web_fonts import prepare_manifest
SOURCE = ROOT / 'ui/office'
ORIGIN = 'https://office.starling.build'
APPS = {
    'writer': dict(label='Writer', office='Word', extension='docx', args=[],
                 example='garden-brief.docx', icon='writer',
                 title='Starling Writer — Free Online Document Editor',
                 description='Open, edit, and save Word (.docx) documents in your browser for free. No account or cloud upload. Your files stay on your device.',
                 question='Can I edit a Word document without Microsoft Word?',
                 answer='Yes. Open a .docx file, edit it in Starling Writer, and use Save to download a Word-format copy. You do not need Microsoft Word installed.'),
    'sheets': dict(label='Sheets', office='Excel', extension='xlsx', args=['--sheets'],
                  example='garden-budget.xlsx', icon='sheets',
                  title='Starling Sheets — Free Online Spreadsheet Editor',
                  description='Open, edit, and save Excel (.xlsx) spreadsheets online for free. Work with formulas and charts on your device. No account or cloud upload.',
                  question='Can I open an Excel spreadsheet without Excel?',
                  answer='Yes. Open a .xlsx workbook in Starling Sheets to edit cells, work with formulas, and save an Excel-format copy. Excel macros and older .xls files are not supported here.'),
    'slides': dict(label='Slides', office='PowerPoint', extension='pptx', args=['--slides'],
                       example='garden-presentation.pptx', icon='slides',
                       title='Starling Slides — Free Online Presentation Editor',
                       description='Open, edit, and save PowerPoint (.pptx) presentations for free in your browser. No login or cloud upload. Your files stay on your device.',
                       question='Can I edit a PowerPoint file without PowerPoint?',
                       answer='Yes. Open a .pptx file in Starling Slides, edit the presentation, and save a PowerPoint-format copy. Older .ppt files are not supported here.'),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(runtime, out):
    if out.exists():
        raise ValueError(f'Output already exists: {out}; choose a fresh directory')
    app = 'app.wasm.gz' if (runtime / 'app.wasm.gz').is_file() else 'app.wasm'
    index = (runtime / 'index.html').read_text()
    match = re.search(r"skwasmBase:\s*['\"]([^'\"]+)['\"]", index)
    if not match:
        raise ValueError('Runtime index must specify a local skwasmBase')
    renderer = Path(match[1].rstrip('/'))
    if renderer.is_absolute() or '..' in renderer.parts or ':' in str(renderer):
        raise ValueError('Renderer must be a directory inside the runtime')
    required = [app, 'starling.js', 'font-loader.js', 'keymap.js', 'fonts/manifest.json',
                str(renderer / 'skwasm.js'), str(renderer / 'skwasm.wasm')]
    for name in required:
        if not (runtime / name).is_file():
            raise ValueError(f'Missing runtime dependency: {name}')
    shared_responses = 'export const supportsPreloadedAssets = true;' in (runtime / 'starling.js').read_text()
    # Independently version components so a loader or font update does not
    # discard a cached, unchanged app/renderer (or vice versa).
    fonts = prepare_manifest(json.loads((runtime / 'fonts/manifest.json').read_text()))
    for font in fonts:
        font['immutable'] = True

    def package_group(label, roots):
        files = sorted(p for name in roots for p in
                       ((runtime / name).rglob('*') if (runtime / name).is_dir() else [runtime / name]) if p.is_file())
        identity = hashlib.sha256()
        for file in files:
            identity.update(str(file.relative_to(runtime)).encode())
            identity.update(hashlib.sha256(json.dumps(fonts, sort_keys=True).encode()).digest()
                            if file == runtime / 'fonts/manifest.json' else bytes.fromhex(digest(file)))
        prefix = '/runtime/' + label + '-' + identity.hexdigest()[:16] + '/'
        target = out / prefix.strip('/')
        target.mkdir(parents=True)
        for name in roots:
            source = runtime / name
            if source.is_dir():
                shutil.copytree(source, target / name)
            else:
                shutil.copy2(source, target / name)
        return prefix, target

    host_prefix, _ = package_group('host', ['starling.js', 'font-loader.js', 'keymap.js'])
    app_files = [app]
    if shared_responses and (runtime / 'app.wasm.br').is_file():
        app_files.append('app.wasm.br')
    app_prefix, _ = package_group('app', app_files)
    renderer_prefix, _ = package_group('renderer', [str(renderer)])
    font_roots = ['fonts']
    if (runtime / 'fonts-word').exists():
        font_roots.append('fonts-word')
    font_prefix, font_target = package_group('fonts', font_roots)
    for font in fonts:
        for field in ['url', 'brotli']:
            if field not in font:
                continue
            url = font[field]
            if url.startswith(('/', 'http:', 'https:')) or '..' in Path(url).parts:
                raise ValueError(f'Expected a bundled font URL: {url}')
            if not (font_target / url).is_file():
                raise ValueError(f'Missing font: {url}')
            font[field] = font_prefix + url
    (font_target / 'fonts/manifest.json').write_text(json.dumps(fonts))
    runtime_config = dict(host=host_prefix + 'starling.js', app=app_prefix + app,
                          renderer=renderer_prefix + str(renderer) + '/', fonts=font_prefix + 'fonts/manifest.json',
                          preloadResponses=shared_responses, immutableAssets=True)
    if 'app.wasm.br' in app_files:
        runtime_config['appBrotli'] = app_prefix + 'app.wasm.br'
    if ('export const supportsRendererBrotli = true;' in (runtime / 'starling.js').read_text()
            and (runtime / renderer / 'skwasm.wasm.br').is_file()):
        runtime_config['rendererBrotli'] = renderer_prefix + str(renderer / 'skwasm.wasm.br')
    (out / 'assets').mkdir()
    (out / 'examples').mkdir()
    for info in APPS.values():
        shutil.copy2(ROOT / 'ui/img/office' / f"starling-{info['icon']}.svg", out / 'assets')
        shutil.copy2(ROOT / 'ui/openoffice/images' / f"{info['icon']}-sample.png", out / 'assets')
        shutil.copy2(ROOT / 'web/office/examples' / info['example'], out / 'examples')
    for name in ['site.css', 'launch.js']:
        shutil.copy2(SOURCE / name, out / name)
    shutil.copy2(ROOT / 'ui/cloudflare-analytics.js', out / 'cloudflare-analytics.js')
    template = Template((SOURCE / 'page.html').read_text())
    for kind in [None, *APPS]:
        info = APPS.get(kind)
        selected = {kind: info} if kind else APPS
        path = f'/{kind}/' if kind else '/'
        navigation = '<a href="/"' + (' aria-current="page"' if not kind else '') + '><span class="home-symbol" aria-hidden="true">⌂</span>All apps</a>'
        navigation += ''.join(f'<a href="/{key}/"' + (' aria-current="page"' if key == kind else '')
                              + f'><img src="/assets/starling-{data["icon"]}.svg" width="24" height="24" alt="">{data["label"]}</a>' for key, data in APPS.items())
        actions = ''.join(f'<a class="create-card" href="/{key}/?start=new" data-app="{key}" data-start="new"><img src="/assets/starling-{data["icon"]}.svg" width="40" height="40" alt=""><span><strong>Blank {dict(writer="document", sheets="spreadsheet", slides="presentation")[key]}</strong><small>{data["label"]} · .{data["extension"]}</small></span><span class="plus" aria-hidden="true">+</span></a>' for key, data in selected.items())
        examples = ''
        for key, data in selected.items():
            sample = dict(writer='Garden handbook', sheets='Garden budget', slides='Garden presentation')[key]
            detail = dict(writer='Text, tables, pictures & links', sheets='Formulas, charts & five worksheets', slides='Nine slides, charts & speaker notes')[key]
            examples += f'<a class="example-row" href="/{key}/?start=example" data-app="{key}" data-start="example"><img src="/assets/starling-{data["icon"]}.svg" width="28" height="28" alt=""><span><strong>{sample}</strong><small>{detail}</small></span><span class="file-type">.{data["extension"]}</span><span class="example-open">Open <span aria-hidden="true">↗</span></span></a>'
        faq = [(info['question'], info['answer'])] if info else [('Which files can I open?', 'Open .docx documents, .xlsx spreadsheets, and .pptx presentations. Choose a file and Starling opens the matching editor. Older .doc, .xls, and .ppt formats are not supported here.')]
        faq += [('Is it free? Do I need an account?', 'The editors are free and open source. No account, subscription, or credit card is required.'),
                ('Are my documents uploaded?', 'No. The browser downloads the editor and fonts. Your selected document is opened and edited locally on your device; it is not uploaded to our servers.'),
                ('Will the formatting match Microsoft Office?', 'Starling supports many familiar Office features, and compatibility is improving. Complex layouts, charts, fonts, or unsupported features can still differ. Keep your original and check important documents after saving.'),
                ('Where does my edited file go?', 'Use Save in the editor to download your edited file. Your browser may ask for a location or save it to Downloads. Save before closing the tab: this site does not store a cloud copy.'),
                ('Can I use the desktop apps?', 'Yes. Follow the Desktop apps link at the bottom of this page for downloads and installation instructions.')]
        config = dict(kind=kind, runtime=runtime_config,
                      apps={k: {field: data[field] for field in ['label', 'args', 'example']} for k, data in APPS.items()})
        values = dict(
            title=info['title'] if info else 'Free Online Office Suite — No Login | Starling Office',
            description=info['description'] if info else 'Starling Writer, Slides, and Sheets: free online document, presentation, and spreadsheet editors. No account or cloud uploads. Your files stay on your device.',
            canonical=ORIGIN + path, path=path, navigation=navigation,
            heading=f'Starling {info["label"]}' if info else 'Your free online office',
            lead=f'Create and edit {dict(writer="documents", sheets="spreadsheets", slides="presentations")[kind]} in your browser. Open and save {info["office"]} (.{info["extension"]}) files with Starling {info["label"]}.' if info else 'Write with Writer, present with Slides, and work with spreadsheets in Sheets. Open and save .docx, .pptx, and .xlsx files in your browser.',
            open_heading=f'Open a {dict(writer="document", sheets="spreadsheet", slides="presentation")[kind]}' if info else 'Open from your device',
            file_hint=f'Choose a .{info["extension"]} file from your device.' if info else '.docx, .xlsx, .pptx',
            accept='.' + info['extension'] if info else '.docx,.xlsx,.pptx',
            new_actions=actions, examples=examples,
            faq=''.join(f'<details><summary>{html.escape(q)}</summary><p>{html.escape(a)}</p></details>' for q, a in faq),
            config=json.dumps(config).replace('<', '\\u003c'),
            css_version=digest(SOURCE / 'site.css')[:16], js_version=digest(SOURCE / 'launch.js')[:16],
            analytics_version=digest(ROOT / 'ui/cloudflare-analytics.js')[:16])
        page = out / path.strip('/') / 'index.html'
        page.parent.mkdir(exist_ok=True)
        page.write_text(template.substitute(values))
    (out / 'CNAME').write_text('office.starling.build\n')
    (out / '.nojekyll').touch()
    (out / 'robots.txt').write_text(f'User-agent: *\nAllow: /\n\nSitemap: {ORIGIN}/sitemap.xml\n')
    (out / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + ''.join(f'  <url><loc>{ORIGIN}{path}</loc></url>\n' for path in ['/', '/writer/', '/slides/', '/sheets/']) + '</urlset>\n')
    provenance = json.loads((runtime / 'build-info.json').read_text()) if (runtime / 'build-info.json').exists() else {}
    (out / 'build-info.json').write_text(json.dumps(dict(runtime=runtime_config, runtime_provenance=provenance), indent=2) + '\n')
    print(f'Packaged product site: {out}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    options = parser.parse_args()
    build(options.runtime.resolve(), options.out.resolve())
