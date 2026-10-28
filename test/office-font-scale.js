// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Evaluated by web-drive.mjs after Office has loaded. Linear advances must
// scale with the requested size, including sizes between 1/64 pixels. At
// 11pt screen size the old FreeType truncation made Carlito 0.071% too narrow
// and changed word-boringcrypto's line breaks. Each probe uses a fresh page.
(async () => {
  const mod = window.starling.skwasm, sk = mod.wasmExports;
  const u8 = () => new Uint8Array(mod.wasmMemory.buffer);
  const u32 = () => new Uint32Array(mod.wasmMemory.buffer);
  const str = (s) => {
    const bytes = new TextEncoder().encode(s), p = sk.skString_allocate(bytes.length);
    u8().set(bytes, sk.skString_getData(p));
    return p;
  };
  const response = await fetch('fonts/Carlito-Regular.ttf');
  if (!response.ok) throw new Error(`Carlito fetch failed: ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  const data = sk.skData_create(bytes.length);
  u8().set(bytes, sk.skData_getPointer(data));
  const face = sk.typeface_create(data);
  if (!face) throw new Error('Carlito could not be decoded');
  const family = str('ScaleProbeCarlito'), fc = sk.fontCollection_create();
  sk.fontCollection_registerTypeface(fc, face, family);
  const familyData = sk.skData_create(4), familyArray = sk.skData_getPointer(familyData);
  u32()[familyArray / 4] = family;
  const samples = [
    'MMMMMMMM', 'iiiiiiii',
    'Modules specifies requirements for cryptographic modules to be deployed in a Sensitive but Unclassified',
  ];
  const rows = [];
  for (const size of [14, 14.5, 44 / 3, 14.667, 15, 220, 220.005]) {
    for (const text of samples) {
      const ps = sk.paragraphStyle_create(), ts = sk.textStyle_create();
      sk.textStyle_setFontSize(ts, size);
      sk.textStyle_addFontFamilies(ts, familyArray, 1);
      sk.paragraphStyle_setTextStyle(ps, ts);
      const builder = sk.paragraphBuilder_create(ps, fc);
      const string = sk.skString16_allocate(text.length);
      new Uint16Array(mod.wasmMemory.buffer).set(
        Array.from(text, c => c.charCodeAt(0)), sk.skString16_getData(string) / 2);
      sk.paragraphBuilder_addText(builder, string);
      // ASCII probes, on one very wide line: supply the client ICU buffers
      // explicitly so this checks font advances independently of segmentation.
      const graphemes = sk.unicodePositionBuffer_create(text.length + 1);
      u32().set(Array.from({ length: text.length + 1 }, (_, i) => i),
        sk.unicodePositionBuffer_getDataPointer(graphemes) / 4);
      sk.paragraphBuilder_setGraphemeBreaksUtf16(builder, graphemes);
      sk.unicodePositionBuffer_free(graphemes);
      const words = sk.unicodePositionBuffer_create(2);
      u32().set([0, text.length], sk.unicodePositionBuffer_getDataPointer(words) / 4);
      sk.paragraphBuilder_setWordBreaksUtf16(builder, words);
      sk.unicodePositionBuffer_free(words);
      const breaks = sk.lineBreakBuffer_create(1);
      u32().set([text.length, 0], sk.lineBreakBuffer_getDataPointer(breaks) / 4);
      sk.paragraphBuilder_setLineBreaksUtf16(builder, breaks);
      sk.lineBreakBuffer_free(breaks);
      const paragraph = sk.paragraphBuilder_build(builder);
      sk.paragraph_layout(paragraph, 100000);
      const width = sk.paragraph_getLongestLine(paragraph);
      if (!Number.isFinite(width) || width <= 0) throw new Error(`Invalid advance: ${width}`);
      rows.push({ size, width, text });
      sk.paragraph_dispose(paragraph);
      sk.paragraphBuilder_dispose(builder);
      sk.skString16_free(string);
      sk.textStyle_dispose(ts);
      sk.paragraphStyle_dispose(ps);
    }
  }
  const reference = rows.filter(r => r.size === 220);
  for (const row of rows) {
    const expected = reference.find(r => r.text === row.text).width * row.size / 220;
    // Float positions accumulate: allow 0.002px at screen scale, far below
    // the 0.44px error in the long line before the fix.
    const tolerance = 0.002 * Math.max(1, row.size / 15);
    if (Math.abs(row.width - expected) > tolerance) {
      throw new Error(`linear advance at ${row.size}px: ${row.width}, expected ${expected}: ${row.text}`);
    }
  }
  return { measurements: rows.length, fractionalFontAdvances: 'pass' };
})()
