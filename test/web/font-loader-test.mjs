import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createFontLoader } from '../../web/host/font-loader.js';

const entries = [
  { url: 'ui.ttf', families: ['UI'] },
  { url: 'serif.ttf', families: ['Serif', 'Alias'], lazy: true },
  { url: 'serif-bold.ttf', families: ['Serif', 'Alias'], lazy: true },
  { url: 'mono.ttf', families: ['Mono'], lazy: true },
];

test('unused families stay unfetched; concurrent requests and aliases share files', async () => {
  const fetched = [], registered = [], changes = [];
  const loader = createFontLoader(entries, {
    fetchBytes: async url => { fetched.push(url); return new Uint8Array([1]); },
    register: (_, family) => registered.push(family),
    changed: () => changes.push([...registered]),
  });
  await loader.load('UI');
  await loader.load('Unknown');
  assert.deepEqual(fetched, []);
  await Promise.all([loader.load('SERIF'), loader.load('Serif'), loader.load('Alias')]);
  await loader.load('serif');
  assert.deepEqual(fetched.sort(), ['serif-bold.ttf', 'serif.ttf']);
  assert.deepEqual(registered.sort(), ['Alias', 'Alias', 'Serif', 'Serif']);
  assert.ok(changes.every(faces => faces.length === 4), 'notify only after all faces register');
});

test('a slow bold face delays notification but not unrelated families', async () => {
  let finishBold;
  const bold = new Promise(resolve => { finishBold = resolve; });
  let changes = 0;
  const loader = createFontLoader(entries, {
    fetchBytes: url => url === 'serif-bold.ttf' ? bold : Promise.resolve(new Uint8Array([1])),
    register() {}, changed() { changes++; },
  });
  const serif = loader.load('Serif');
  await loader.load('Mono');
  assert.equal(changes, 1);
  finishBold(new Uint8Array([1]));
  await serif;
  assert.equal(changes, 2);
});

test('failure is visible, does not loop on repaint, and retries only missing files', async () => {
  const attempts = new Map();
  let status, fail = true, changes = 0;
  const loader = createFontLoader(entries, {
    fetchBytes: async url => {
      attempts.set(url, (attempts.get(url) ?? 0) + 1);
      if (url === 'serif-bold.ttf' && fail) throw Error('offline');
      return new Uint8Array([1]);
    },
    register() {}, changed() { changes++; }, status: value => { status = value; },
  });
  await assert.rejects(loader.load('Serif'), /offline/);
  assert.deepEqual(status, { pending: [], failed: ['serif'] });
  loader.request('Serif');
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(attempts.get('serif-bold.ttf'), 1);
  assert.equal(changes, 0);
  fail = false;
  await loader.retry();
  assert.equal(attempts.get('serif.ttf'), 1);
  assert.equal(attempts.get('serif-bold.ttf'), 2);
  assert.equal(changes, 1);
  assert.deepEqual(status, { pending: [], failed: [] });
});

test('invalid font bytes are retryable, not marked loaded', async () => {
  let fail = true, changes = 0;
  const loader = createFontLoader(entries, {
    fetchBytes: async () => new Uint8Array([1]),
    register() { if (fail) throw Error('invalid font'); },
    changed() { changes++; },
  });
  await assert.rejects(loader.load('Mono'), /invalid font/);
  assert.equal(changes, 0);
  fail = false;
  await loader.retry();
  assert.equal(changes, 1);
});

const script = [
  { url: 'cjk.ttc', lazy: true, weight: 400, scripts: ['cjk-sc', 'cjk-tc'], fallback: true, order: 1, gzip: true,
    faces: [{ index: 2, family: 'Noto Sans CJK SC' }, { index: 3, family: 'Noto Sans CJK TC' }] },
  { url: 'cjk-bold.ttc', lazy: true, weight: 700, scripts: ['cjk-sc', 'cjk-tc'], fallback: true, order: 1,
    faces: [{ index: 2, family: 'Noto Sans CJK SC' }, { index: 3, family: 'Noto Sans CJK TC' }] },
  { url: 'arabic.ttf', lazy: true, weight: 400, scripts: ['arabic'], fallback: true, order: 2, faces: [{ index: -1, family: 'Noto Sans Arabic' }] },
  { url: 'hebrew.ttf', lazy: true, weight: 400, scripts: ['hebrew'], fallback: true, order: 0, faces: [{ index: -1, family: 'Noto Sans Hebrew' }] },
];

test('a script loads its Regular file once, every face by index; Bold only when asked', async () => {
  const fetched = [], registered = [];
  const loader = createFontLoader(script, {
    fetchBytes: async url => { fetched.push(url); return new Uint8Array([9]); },
    inflate: async bytes => bytes,
    register: (bytes, family, index) => registered.push([family, index]),
    changed() {},
  });
  await Promise.all([loader.loadScript('cjk-sc'), loader.loadScript('cjk-tc'), loader.load('Noto Sans CJK TC')]);
  assert.deepEqual(fetched, ['cjk.ttc.gz'], 'one download, gzip suffix');
  assert.deepEqual(registered, [['Noto Sans CJK SC', 2], ['Noto Sans CJK TC', 3]]);
  await loader.loadScript('cjk-sc', { bold: true });
  assert.deepEqual(fetched, ['cjk.ttc.gz', 'cjk-bold.ttc']);
  await loader.loadScript('nothing');
});

test('the fallback chain is table order, not arrival order, and leaves out order 0 and Bold', () => {
  const loader = createFontLoader(script, { register() {}, changed() {} });
  assert.deepEqual(loader.fallbackChain(), ['Noto Sans CJK SC', 'Noto Sans CJK TC', 'Noto Sans Arabic']);
  assert.ok(loader.hasScript('arabic') && !loader.hasScript('thai'));
});
