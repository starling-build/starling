#!/usr/bin/env node
// Serve two packaged releases on one origin, with the first/second Writer
// HTML at separate URLs. A loader-only release must reuse app/renderer/fonts.
// Optional --stale true verifies this even under Cache-Control: max-age=0.
import { createRequire } from 'node:module';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';
const {webkit, chromium} = createRequire(import.meta.url)(process.env.PLAYWRIGHT_MODULE || 'playwright');
const options = {};
for (let i=2; i<process.argv.length; i+=2) options[process.argv[i].slice(2)] = process.argv[i+1];
if (!options.before || !options.after) throw Error('--before and --after URLs are required');
const chrome = options.engine === 'chromium';
// A normal disk-backed profile: private contexts can decline to cache large
// responses, which would test private-mode limits rather than release reuse.
const profile = mkdtempSync(join(tmpdir(), 'starling-release-cache-'));
const context = await (chrome ? chromium : webkit).launchPersistentContext(profile, {
  viewport:{width:1440,height:1000},
  ...(chrome ? {channel:'chrome', args:['--enable-unsafe-swiftshader']} : {}),
});
const large = path => /\.wasm(\.(br|gz))?$/.test(path) || /\.(ttf|otf)(\.br)?$/.test(path);
try {
  await context.addInitScript(() => {
    window.addEventListener('starling-reader-ready', () => { window.__readyMs = performance.now(); });
  });
  const page = await context.newPage(), errors = [], cacheHeaders = [];
  page.on('pageerror', error => errors.push(String(error)));
  page.on('response', response => {
    if (large(new URL(response.url()).pathname)) cacheHeaders.push(response.headers()['cache-control']);
  });
  const results = [];
  for (const url of [options.before, options.after]) {
    await page.goto(url);
    await page.waitForFunction(() => window.__readyMs && window.starling?.fontsPending() === 0, {}, {timeout:60000});
    results.push(await page.evaluate(() => ({
      readyMs:window.__readyMs, name:starling.debug('name'),
      runtime:JSON.parse(document.querySelector('#office-config').textContent).runtime,
      resources:performance.getEntriesByType('resource').map(r => ({path:new URL(r.name).pathname,
        transfer:r.transferSize, encoded:r.encodedBodySize})),
    })));
  }
  assert.deepEqual(errors, []);
  assert.notEqual(results[0].runtime.host, results[1].runtime.host, 'test must actually update the loader');
  for (const key of ['app','appBrotli','renderer','rendererBrotli','fonts']) {
    assert.equal(results[0].runtime[key], results[1].runtime[key], key);
  }
  for (const result of results) {
    assert.equal(result.name, 'Document1');
    // WebKit can report a header-only transferSize of 300 for disk-cache hits
    // with encodedBodySize=0; Chrome reports transferSize=0. Count payloads.
    result.largeTransfer = result.resources.filter(r => large(r.path)).reduce((sum,r) => sum+(r.transfer ? r.encoded : 0),0);
  }
  if (options.out) writeFileSync(options.out, JSON.stringify({engine:options.engine || 'webkit', stale:options.stale === 'true', results},null,2)+'\n');
  assert.ok(results[0].largeTransfer > 0);
  assert.equal(results[1].largeTransfer, 0, 'unchanged binary/font assets must not transfer again');
  if (options.stale === 'true') assert.ok(cacheHeaders.length && cacheHeaders.every(value => value?.includes('max-age=0')));
  console.log(`PASS ${chrome ? 'Chrome' : 'WebKit'}: ${results[0].largeTransfer} → 0 binary/font bytes after loader update; first frame ${results[1].readyMs} ms`);
} finally {
  await context.close();
  rmSync(profile, {recursive:true, force:true, maxRetries:3, retryDelay:200});
}
