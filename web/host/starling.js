// The page's half of the browser build: loads skwasm and the Swift module,
// and is everything the two cannot be for each other.
//
//   skwasm.wasm   Flutter's renderer (Emscripten). Owns Skia, WebGL, and a
//                 linear memory of its own.
//   the app .wasm Swift, built for WASI. Imports skwasm's exports directly,
//                 so a draw call is wasm calling wasm with no JavaScript
//                 in between.
//
// What is left for JavaScript is what neither module can do alone: copy
// between the two memories, hold the externref a finished render arrives
// as, ask the browser where text may break, and drive frames and input.

const WASI_ESUCCESS = 0;
const WASI_EBADF = 8;
const WASI_ENOSYS = 52;

// The Swift runtime's needs from WASI are small when nothing touches the
// filesystem: somewhere for print() to go, a clock, and random bytes for
// hashing seeds. Everything else answers ENOSYS rather than being absent,
// because a missing import fails instantiation outright.
function makeWasi(getMemory) {
  const decoder = new TextDecoder();
  const lines = { 1: '', 2: '' };
  const view = () => new DataView(getMemory().buffer);
  const known = {
    fd_write(fd, iovs, iovsLen, nwritten) {
      if (fd !== 1 && fd !== 2) return WASI_EBADF;
      const v = view();
      let written = 0;
      for (let i = 0; i < iovsLen; i++) {
        const ptr = v.getUint32(iovs + i * 8, true);
        const len = v.getUint32(iovs + i * 8 + 4, true);
        lines[fd] += decoder.decode(new Uint8Array(getMemory().buffer, ptr, len));
        written += len;
      }
      let newline;
      while ((newline = lines[fd].indexOf('\n')) >= 0) {
        (fd === 1 ? console.log : console.error)(lines[fd].slice(0, newline));
        lines[fd] = lines[fd].slice(newline + 1);
      }
      v.setUint32(nwritten, written, true);
      return WASI_ESUCCESS;
    },
    clock_time_get(id, precision, out) {
      const ms = id === 0 ? Date.now() : performance.now();
      view().setBigUint64(out, BigInt(Math.round(ms * 1e6)), true);
      return WASI_ESUCCESS;
    },
    // Foundation asks for the clock's resolution while it initialises and
    // traps if it cannot have one. performance.now() is good to ~5µs at
    // best; claim a microsecond.
    clock_res_get(id, out) {
      view().setBigUint64(out, 1000n, true);
      return WASI_ESUCCESS;
    },
    random_get(ptr, len) {
      crypto.getRandomValues(new Uint8Array(getMemory().buffer, ptr, len));
      return WASI_ESUCCESS;
    },
    args_sizes_get(argc, size) {
      view().setUint32(argc, 0, true);
      view().setUint32(size, 0, true);
      return WASI_ESUCCESS;
    },
    args_get: () => WASI_ESUCCESS,
    environ_sizes_get(count, size) {
      view().setUint32(count, 0, true);
      view().setUint32(size, 0, true);
      return WASI_ESUCCESS;
    },
    environ_get: () => WASI_ESUCCESS,
    // No preopened directories: EBADF on the first probe ends libc's scan.
    fd_prestat_get: () => WASI_EBADF,
    fd_fdstat_get(fd, out) {
      if (fd > 2) return WASI_EBADF;
      const v = view();
      v.setUint8(out, 2); // character device
      v.setUint16(out + 2, 0, true);
      v.setBigUint64(out + 8, 0n, true);
      v.setBigUint64(out + 16, 0n, true);
      return WASI_ESUCCESS;
    },
    proc_exit(code) {
      throw new Error(`starling: the wasm module exited with code ${code}`);
    },
  };
  return new Proxy(known, {
    get: (target, name) => target[name] ?? (() => WASI_ENOSYS),
    has: () => true,
  });
}

// Intl.v8BreakIterator yields coarse break opportunities; this refines them
// the way Flutter's breakLinesUsingV8BreakIterator does — a break after every
// run of spaces, and a newline makes the break mandatory. Returns
// [position, isHard] pairs.
const NEWLINES = new Set([0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0x2028, 0x2029]);
const SPACES = new Set([0x20, 0x09, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
  0x2004, 0x2005, 0x2006, 0x2008, 0x2009, 0x200a, 0x205f, 0x3000]);

function lineBreaks(text) {
  const breaks = [];
  let start = 0;
  let lastHard = false;
  const push = (end, hard) => { breaks.push([end, hard]); lastHard = hard; };
  const opportunities = [];
  if (Intl.v8BreakIterator) {
    const it = new Intl.v8BreakIterator([], { type: 'line' });
    it.adoptText(text);
    it.first();
    while (it.next() !== -1) opportunities.push(it.current());
  } else {
    // Firefox and Safari have no line iterator. Word boundaries are a
    // serviceable stand-in for Latin text and wrong for CJK and Thai; the
    // heavy skwasm build, with ICU inside, is the real answer there.
    const words = new Intl.Segmenter([], { granularity: 'word' });
    for (const s of words.segment(text)) if (s.index > 0) opportunities.push(s.index);
    opportunities.push(text.length);
  }
  for (const end of opportunities) {
    let newlines = 0;
    let spaces = 0;
    for (let i = start; i < end; i++) {
      const unit = text.charCodeAt(i);
      if (NEWLINES.has(unit)) { newlines++; spaces++; }
      else if (SPACES.has(unit)) { spaces++; }
      else if (spaces > 0) { push(i, false); start = i; newlines = 0; spaces = 0; }
    }
    push(end, newlines > 0);
    start = end;
  }
  if (breaks.length === 0 || lastHard) breaks.push([text.length, true]);
  return breaks;
}

// The family fontCollection_create names as its default (skwasm/fonts.cpp).
const SKWASM_FALLBACK_FAMILY = 'Roboto';

// SkUnicode::LineBreakType.
const SOFT_LINE_BREAK = 0;
const HARD_LINE_BREAK = 100;

export async function startStarling({ canvas, app, skwasmBase, fonts = [] }) {
  // --- skwasm, single-threaded. Threads need a cross-origin-isolated page
  // (COOP/COEP headers); without them skwasm renders on the main thread,
  // which is also what Flutter does on an ordinary page.
  const skwasmUrl = new URL(`${skwasmBase}skwasm.js`, location.href).href;
  const skwasmModule = WebAssembly.compileStreaming(
    fetch(new URL(`${skwasmBase}skwasm.wasm`, location.href)));
  const factory = (await import(skwasmUrl)).default;
  const skwasm = await factory({
    skwasmSingleThreaded: true,
    mainScriptUrlOrBlob: skwasmUrl,
    instantiateWasm(imports, done) {
      (async () => {
        const module = await skwasmModule;
        done(await WebAssembly.instantiate(module, imports), module);
      })();
      return {};
    },
  });
  const sk = skwasm.wasmExports;
  // Looked up on every use: growing a memory replaces its buffer.
  const skBytes = () => new Uint8Array(skwasm.wasmMemory.buffer);
  const skView = () => new DataView(skwasm.wasmMemory.buffer);

  let swift; // the app instance's exports
  const appBytes = () => new Uint8Array(swift.memory.buffer);

  const screen = canvas.getContext('bitmaprenderer');

  // (callbackId, pointer, externref) -> void, in skwasm's table.
  const renderCallback = skwasm.addFunction((callbackId, pointer, result) => {
    if (result) {
      const [bitmap] = result.imageBitmaps;
      screen.transferFromImageBitmap(bitmap);
    }
    swift.starling_frame_presented();
  }, 'viie');

  const utf8 = new TextDecoder();
  const host = {
    write(dst, src, length) {
      skBytes().set(appBytes().subarray(src, src + length), dst);
    },
    read(dst, src, length) {
      appBytes().set(skBytes().subarray(src, src + length), dst);
    },
    render_callback: () => renderCallback,
    request_frame() {
      requestAnimationFrame((now) => swift.starling_begin_frame(now));
    },
    segment(builder) {
      const sp = sk.emscripten_stack_get_current();
      const outLength = sk._emscripten_stack_alloc(4);
      const data = sk.paragraphBuilder_getUtf8Text(builder, outLength);
      const length = skView().getUint32(outLength, true);
      sk._emscripten_stack_restore(sp);
      // slice, not subarray: TextDecoder refuses a view of shared memory.
      const text = data ? utf8.decode(skBytes().slice(data, data + length)) : '';

      for (const [granularity, set] of [
        ['grapheme', sk.paragraphBuilder_setGraphemeBreaksUtf16],
        ['word', sk.paragraphBuilder_setWordBreaksUtf16],
      ]) {
        const positions = [];
        const segmenter = new Intl.Segmenter([], { granularity });
        for (const s of segmenter.segment(text)) positions.push(s.index);
        positions.push(text.length);
        const buffer = sk.unicodePositionBuffer_create(positions.length);
        const base = sk.unicodePositionBuffer_getDataPointer(buffer);
        const v = skView();
        positions.forEach((p, i) => v.setUint32(base + i * 4, p, true));
        set(builder, buffer);
        sk.unicodePositionBuffer_free(buffer);
      }

      // Entry 0 is the break before the text and stays zeroed.
      const breaks = lineBreaks(text);
      const buffer = sk.lineBreakBuffer_create(breaks.length + 1);
      const base = sk.lineBreakBuffer_getDataPointer(buffer);
      const v = skView();
      breaks.forEach(([position, hard], i) => {
        v.setUint32(base + (i + 1) * 8, position, true);
        v.setInt32(base + (i + 1) * 8 + 4, hard ? HARD_LINE_BREAK : SOFT_LINE_BREAK, true);
      });
      sk.paragraphBuilder_setLineBreaksUtf16(builder, buffer);
      sk.lineBreakBuffer_free(buffer);
    },
  };

  // --- the Swift module
  const timers = new Map();
  host.set_timeout = (id, milliseconds) => {
    timers.set(id, setTimeout(() => {
      timers.delete(id);
      swift.starling_timer_fired(id);
    }, milliseconds));
  };
  host.now = () => performance.now();

  const { instance } = await WebAssembly.instantiateStreaming(fetch(app), {
    wasi_snapshot_preview1: makeWasi(() => swift.memory),
    skwasm: sk,
    starling: host,
  });
  swift = instance.exports;
  swift._initialize();

  // --- fonts, before the app builds its first frame. skwasm cannot see
  // system fonts: every face is fetched and handed over as bytes, written
  // straight into an SkData in skwasm's memory. A font may be registered
  // under several family names — the first entry is also given skwasm's
  // fallback name, so text in a family nobody loaded still draws.
  const encoder = new TextEncoder();
  const registerFont = (bytes, family) => {
    const data = sk.skData_create(bytes.length);
    skBytes().set(bytes, sk.skData_getPointer(data));
    const name = encoder.encode(family ?? '');
    const namePointer = name.length ? swift.starling_alloc(name.length) : 0;
    if (namePointer) appBytes().set(name, namePointer);
    const ok = swift.starling_font_loaded(data, namePointer, name.length);
    if (namePointer) swift.starling_free(namePointer);
    if (!ok) console.error(`starling: font for '${family}' did not parse`);
  };
  await Promise.all(fonts.map(async ({ url, families }, index) => {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`starling: ${url}: ${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    for (const family of families) registerFont(bytes, family);
    if (index === 0) registerFont(bytes, SKWASM_FALLBACK_FAMILY);
  }));

  // --- size, before the app mounts, so its first layout is the real one.
  const resize = () => {
    const ratio = window.devicePixelRatio || 1;
    const { width, height } = canvas.getBoundingClientRect();
    canvas.width = Math.max(1, Math.round(width * ratio));
    canvas.height = Math.max(1, Math.round(height * ratio));
    swift.starling_resize(width, height, ratio);
  };
  resize();
  new ResizeObserver(resize).observe(canvas);

  // --- the app's main. It mounts the widget tree and returns.
  swift.__main_argc_argv(0, 0);

  // --- input. Event numbers are WebHost.PointerEvent's.
  const MOVE = 0, DOWN = 1, UP = 2, LEAVE = 3, CANCEL = 4;
  const KINDS = { touch: 0, mouse: 1, pen: 2 };
  const pointer = (event) => (dom) => {
    const box = canvas.getBoundingClientRect();
    if (event === DOWN) canvas.setPointerCapture(dom.pointerId);
    swift.starling_pointer(
      event, dom.pointerId, KINDS[dom.pointerType] ?? 1,
      dom.clientX - box.left, dom.clientY - box.top, dom.buttons, dom.timeStamp);
    dom.preventDefault();
  };
  canvas.addEventListener('pointermove', pointer(MOVE));
  canvas.addEventListener('pointerdown', pointer(DOWN));
  canvas.addEventListener('pointerup', pointer(UP));
  canvas.addEventListener('pointerleave', pointer(LEAVE));
  canvas.addEventListener('pointercancel', pointer(CANCEL));
  canvas.addEventListener('contextmenu', (dom) => dom.preventDefault());
  canvas.addEventListener('wheel', (dom) => {
    const box = canvas.getBoundingClientRect();
    // deltaMode 1 is lines, 2 is pages; the framework wants pixels.
    const unit = dom.deltaMode === 1 ? 16 : dom.deltaMode === 2 ? box.height : 1;
    swift.starling_scroll(
      0, dom.clientX - box.left, dom.clientY - box.top,
      dom.deltaX * unit, dom.deltaY * unit, dom.timeStamp);
    dom.preventDefault();
  }, { passive: false });

  return { skwasm, swift };
}
