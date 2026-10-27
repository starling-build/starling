#!/usr/bin/env node
// Real WebKit checks for native Brotli decoding and gzip fallback. Requires
// Playwright + its WebKit browser in a separate test environment, not the app.
// PLAYWRIGHT_MODULE=/tmp/test-env/node_modules/playwright node ... --url URL
// Optional: --standalone URL --out /tmp/brotli-check.json
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const { webkit } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE || 'playwright');
const options = {};
for (let i = 2; i < process.argv.length; i += 2) options[process.argv[i].slice(2)] = process.argv[i + 1];
if (!options.url) throw Error('--url must be a Writer product page ending in ?start=new');
const browser = await webkit.launch();
const results = [];
try {
  for (const mode of ['brotli', 'unsupported', 'missing', 'corrupt', 'font-missing', 'font-corrupt', ...(options.standalone ? ['standalone'] : [])]) {
    const context = await browser.newContext({ viewport: {width:1440, height:1000} });
    try {
      if (mode === 'unsupported') await context.addInitScript(() => {
        const native = globalThis.DecompressionStream;
        globalThis.DecompressionStream = function(format) {
          if (format === 'brotli') throw new TypeError('Brotli not supported');
          return new native(format);
        };
      });
      await context.addInitScript(() => {
        window.addEventListener('starling-reader-ready', () => { window.__ready = true; });
      });
      const page = await context.newPage();
      const errors = [], requests = [], renderers = [], fonts = [];
      page.on('pageerror', error => errors.push(String(error)));
      page.on('request', request => {
        if (new URL(request.url()).pathname.match(/app\.wasm\.(br|gz)$/)) requests.push(request.url());
        if (new URL(request.url()).pathname.endsWith('/skwasm.wasm')) renderers.push(request.url());
        const path = new URL(request.url()).pathname;
        if (/\/fonts\/.*\.(ttf|otf)(\.br)?$/.test(path)) fonts.push(path);
      });
      if (mode === 'missing' || mode === 'corrupt') {
        await page.route('**/app.wasm.br*', route => route.fulfill({
          status: mode === 'missing' ? 404 : 200,
          contentType: 'application/octet-stream', body: 'invalid Brotli',
        }));
      }
      if (mode.startsWith('font-')) {
        await page.route('**/fonts/*.br', route => route.fulfill({
          status: mode === 'font-missing' ? 404 : 200,
          contentType: 'application/octet-stream', body: 'invalid Brotli',
        }));
      }
      await page.goto(mode === 'standalone' ? options.standalone : options.url);
      await page.waitForFunction(() => window.__ready && window.starling?.fontsPending() === 0, {}, {timeout:60000});
      const name = await page.evaluate(() => window.starling.debug('name'));
      assert.equal(name, mode === 'standalone' ? 'garden-brief.docx' : 'Document1');
      assert.deepEqual(errors, []);
      assert.equal(renderers.length, 1, 'renderer must be fetched once');
      const formats = requests.map(url => new URL(url).pathname.split('.').at(-1));
      assert.deepEqual(formats, mode === 'unsupported' ? ['gz']
        : mode === 'missing' || mode === 'corrupt' ? ['br', 'gz'] : ['br']);
      assert.ok(fonts.length > 0);
      assert.ok(fonts.every(path => !path.includes('NotoSansSC') && !path.includes('FangSong')),
        'Chinese fonts must remain optional');
      if (mode.startsWith('font-')) {
        const compressed = fonts.filter(path => path.endsWith('.br'));
        const originals = fonts.filter(path => !path.endsWith('.br'));
        assert.ok(compressed.length > 0);
        assert.deepEqual(compressed.map(path => path.slice(0,-3)).sort(), originals.sort());
      } else {
        assert.ok(fonts.every(path => path.endsWith('.br') === (mode !== 'unsupported')));
      }
      results.push({mode, name, formats, fontRequests:fonts.length});
      console.log(`PASS ${mode}: ${formats.join(' → ')}, ${name}`);
    } finally { await context.close(); }
  }
  // Mere visits to the introduction still do not download an editor.
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    const url = new URL(options.url); url.search = '';
    const runtimeRequests = [];
    page.on('request', request => { if (new URL(request.url()).pathname.includes('/runtime/')) runtimeRequests.push(request.url()); });
    await page.goto(url.href); await page.waitForTimeout(500);
    assert.deepEqual(runtimeRequests, []);
    console.log('PASS idle: no editor download');
  } finally { await context.close(); }
  if (options.out) writeFileSync(options.out, JSON.stringify(results, null, 2) + '\n');
} finally { await browser.close(); }
