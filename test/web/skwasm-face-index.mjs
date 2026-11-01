// The skwasm we build exports typeface_createWithIndex (a face of a font
// collection by index) and the probe starling_typeface_faceIndexSupported.
// Runs the module in node (single-threaded, no GL: fonts need neither) and
// opens every face of a .ttc. Skips when the pieces are not on this box.
//   SKWASM_DIR=<engine>/src/out/wasm_release/flutter_web_sdk/canvaskit \
//   TTC=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc node test/web/skwasm-face-index.mjs
import fs from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const dir = (process.env.SKWASM_DIR ?? '').replace(/\/?$/, '/');
const ttc = process.env.TTC ?? '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';
const skip = !process.env.SKWASM_DIR || !fs.existsSync(dir + 'skwasm.wasm') || !fs.existsSync(ttc);

test('typeface_createWithIndex opens each face of a collection and refuses the rest', { skip }, async () => {
  const factory = (await import(dir + 'skwasm.js')).default;
  const module = await WebAssembly.compile(fs.readFileSync(dir + 'skwasm.wasm'));
  const skwasm = await factory({
    skwasmSingleThreaded: true, mainScriptUrlOrBlob: dir + 'skwasm.js',
    instantiateWasm(imports, done) { WebAssembly.instantiate(module, imports).then(i => done(i, module)); return {}; },
  });
  const sk = skwasm.wasmExports;
  assert.equal(sk.starling_typeface_faceIndexSupported(), 1);
  const bytes = fs.readFileSync(ttc);
  const data = sk.skData_create(bytes.length);
  new Uint8Array(skwasm.wasmMemory.buffer).set(bytes, sk.skData_getPointer(data));
  // Noto CJK collections: 0 JP, 1 KR, 2 SC, 3 TC, 4 HK, then the Mono five.
  for (let index = 0; index < 10; index++) {
    const face = sk.typeface_createWithIndex(data, index);
    assert.notEqual(face, 0, `face ${index}`);
    sk.typeface_dispose(face);
  }
  assert.equal(sk.typeface_createWithIndex(data, 10), 0);
  assert.equal(sk.typeface_createWithIndex(data, -1), 0);
});
