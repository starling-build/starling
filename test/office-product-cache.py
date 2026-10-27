#!/usr/bin/env python3
"""Check cache boundaries when independently releasing Office components."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('product', ROOT / 'build/office-product.py')
product = importlib.util.module_from_spec(spec)
spec.loader.exec_module(product)


class CacheBoundaries(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.stage = self.root / 'stage'
        self.stage.mkdir()
        self.serial = 0
        files = {
            'index.html': "skwasmBase: 'skwasm/'",
            'starling.js': 'export const supportsPreloadedAssets = true;\nexport const supportsRendererBrotli = true;',
            'font-loader.js': 'font loader', 'keymap.js': 'keys',
            'app.wasm.gz': 'app gzip fixture', 'app.wasm.br': 'app Brotli fixture',
            'skwasm/skwasm.js': 'renderer host', 'skwasm/skwasm.wasm': 'renderer fixture',
            'skwasm/skwasm.wasm.br': 'renderer Brotli fixture',
            'fonts/ui.ttf': 'font fixture', 'fonts/ui.ttf.br': 'font Brotli fixture',
            'fonts/manifest.json': json.dumps([{'url':'fonts/ui.ttf', 'brotli':'fonts/ui.ttf.br', 'families':['UI']}]),
        }
        for name, content in files.items():
            path = self.stage / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)

    def package(self):
        self.serial += 1
        out = self.root / str(self.serial)
        with contextlib.redirect_stdout(io.StringIO()):
            product.build(self.stage, out)
        config = json.loads((out / 'build-info.json').read_text())['runtime']
        for field in ['host', 'app', 'appBrotli', 'fonts', 'rendererBrotli']:
            if field in config:
                self.assertTrue((out / config[field].lstrip('/')).is_file())
        for font in json.loads((out / config['fonts'].lstrip('/')).read_text()):
            self.assertTrue(font['immutable'])
            for field in ['url', 'brotli']:
                self.assertTrue((out / font[field].lstrip('/')).is_file())
        return config

    def test_only_changed_components_get_new_urls(self):
        original = self.package()
        self.assertEqual(original, self.package())
        for filename, changed in [
            ('font-loader.js', {'host'}),
            ('fonts/ui.ttf', {'fonts'}),
            ('fonts/manifest.json', {'fonts'}),
            ('app.wasm.gz', {'app', 'appBrotli'}),
            ('skwasm/skwasm.js', {'renderer', 'rendererBrotli'}),
        ]:
            with self.subTest(filename=filename):
                path = self.stage / filename
                before = path.read_text()
                if filename.endswith('.json'):
                    data = json.loads(before); data[0]['lazy'] = True
                    path.write_text(json.dumps(data))
                else:
                    path.write_text(before + '\nchanged')
                current = self.package()
                self.assertEqual({key for key in original if original[key] != current[key]}, changed)
                path.write_text(before)

    def test_older_hosts_keep_original_representation(self):
        (self.stage / 'starling.js').write_text('older host')
        config = self.package()
        self.assertFalse(config['preloadResponses'])
        self.assertNotIn('appBrotli', config)
        self.assertNotIn('rendererBrotli', config)


if __name__ == '__main__':
    unittest.main()
