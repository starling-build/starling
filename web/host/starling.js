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

import { createFontLoader } from './font-loader.js';
import { PHYSICAL, LOGICAL, LOGICAL_BY_LOCATION } from './keymap.js';

const WASI_ESUCCESS = 0;
const WASI_EBADF = 8;
const WASI_ENOSYS = 52;

// The Swift runtime's needs from WASI are small when nothing touches the
// filesystem: somewhere for print() to go, a clock, and random bytes for
// hashing seeds. Everything else answers ENOSYS rather than being absent,
// because a missing import fails instantiation outright.
function makeWasi(getMemory, args = []) {
  const decoder = new TextDecoder();
  const argv = ['starling', ...args].map((a) => new TextEncoder().encode(a));
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
      // stderr is not held for a newline: the runtime's last words before
      // a trap ("Could not allocate memory") end without one.
      if (fd === 2 && lines[fd]) {
        console.error(lines[fd]);
        lines[fd] = '';
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
    // The app's command line: `config.args` after an argv[0], the way
    // Swift's CommandLine.arguments reads them (it asks WASI directly, so
    // the argc/argv handed to main do not matter). Office starts in
    // Slides for `--slides`, as it does natively.
    args_sizes_get(argc, size) {
      view().setUint32(argc, argv.length, true);
      view().setUint32(size, argv.reduce((n, a) => n + a.length + 1, 0), true);
      return WASI_ESUCCESS;
    },
    args_get(argvPtr, bufPtr) {
      const bytes = new Uint8Array(getMemory().buffer);
      let p = bufPtr;
      argv.forEach((a, i) => {
        view().setUint32(argvPtr + 4 * i, p, true);
        bytes.set(a, p);
        bytes[p + a.length] = 0;
        p += a.length + 1;
      });
      return WASI_ESUCCESS;
    },
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

// Intl.v8BreakIterator's line-break opportunities (ICU's UAX #14, the
// same rules the native engine applies), each marked hard when the text
// before it ends in a newline, the way Flutter's
// breakLinesUsingV8BreakIterator classifies them. Returns [position,
// isHard] pairs. Nothing is added to what the iterator says: a first
// version also broke after every run of spaces, which ICU already does
// wherever the rules allow — so the only breaks it added were the ones
// ICU had refused ("encrypt / decrypt" broke before the slash, LB13),
// and the browser wrapped one line differently from the desktop.
const NEWLINES = new Set([0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0x2028, 0x2029]);

function lineBreaks(text) {
  const breaks = [];
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
    // Mandatory when the segment ends in a newline (CR LF is one break).
    let i = end;
    while (i > 0 && NEWLINES.has(text.charCodeAt(i - 1))) i--;
    push(end, i < end);
  }
  if (breaks.length === 0 || lastHard) breaks.push([text.length, true]);
  return breaks;
}

// The family fontCollection_create names as its default (skwasm/fonts.cpp).
const SKWASM_FALLBACK_FAMILY = 'Roboto';

// SkUnicode::LineBreakType.
const SOFT_LINE_BREAK = 0;
const HARD_LINE_BREAK = 100;

// Wraps a fetch so that `onProgress(loaded, total)` sees the bytes go by,
// without giving up streaming compilation: the body is re-wrapped, the
// headers (application/wasm among them) kept. `total` is unknown when HTTP
// compression makes the response length differ from the decoded stream.
//
// A URL ending in `.gz` is a gzip file the page inflates itself, with
// DecompressionStream, into a Response typed application/wasm so streaming
// compilation still applies. That is for a host that cannot be told to
// serve a precompressed file with Content-Encoding (GitHub Pages, where
// writer.starling.build lives): the 12 MB module travels as 4 MB, which
// is what a server with brotli_static would have done with the .br.
async function fetchWithProgress(url, onProgress) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`starling: ${url}: ${response.status}`);
  const gzipped = String(url).endsWith('.gz');
  if ((!onProgress && !gzipped) || !response.body) return response;
  // fetch exposes decoded bytes for HTTP compression, but Content-Length is
  // the compressed length. Do not report a fictitious percentage above 100%.
  const total = response.headers.get('Content-Encoding')
    ? 0 : Number(response.headers.get('Content-Length')) || 0;
  let loaded = 0;
  let body = response.body;
  if (onProgress) {
    body = body.pipeThrough(new TransformStream({
      transform(chunk, controller) {
        loaded += chunk.byteLength;
        onProgress(loaded, total);
        controller.enqueue(chunk);
      },
    }));
  }
  const headers = new Headers(response.headers);
  if (gzipped) {
    body = body.pipeThrough(new DecompressionStream('gzip'));
    headers.set('Content-Type', 'application/wasm');
    headers.delete('Content-Length');
    headers.delete('Content-Encoding');
  }
  return new Response(body, { headers, status: response.status });
}

let unsaved = false;
window.addEventListener('beforeunload', (event) => {
  if (!unsaved) return;
  event.preventDefault();
  event.returnValue = '';
});

export async function startStarling({ canvas, app, skwasmBase, fonts = [], args = [], onProgress, onPhase, onFontStatus, initialRoute, initialFiles = [], captureTab = true }) {
  const startupFiles = Promise.all(initialFiles.map(async file => {
    const response = await fetch(file.url);
    if (!response.ok) throw new Error(`starling: ${file.url}: ${response.status}`);
    return { name: file.name, bytes: new Uint8Array(await response.arrayBuffer()) };
  }));
  startupFiles.catch(() => {});
  onPhase?.('Loading editor and fonts…');
  // --- skwasm, single-threaded. Threads need a cross-origin-isolated page
  // (COOP/COEP headers); without them skwasm renders on the main thread,
  // which is also what Flutter does on an ordinary page.
  const skwasmUrl = new URL(`${skwasmBase}skwasm.js`, location.href).href;
  // Both modules compile in parallel; fonts also begin fetching immediately.
  // Progress counts the module streams; phases cover font preparation.
  const progress = { app: [0, 0], skwasm: [0, 0] };
  const report = (which) => (loaded, total) => {
    progress[which] = [loaded, total];
    if (onProgress) {
      const known = progress.app[1] > 0 && progress.skwasm[1] > 0;
      onProgress(progress.app[0] + progress.skwasm[0], known ? progress.app[1] + progress.skwasm[1] : 0);
    }
  };
  const skwasmModule = WebAssembly.compileStreaming(
    fetchWithProgress(new URL(`${skwasmBase}skwasm.wasm`, location.href), report('skwasm')));
  // Compile independently: only instantiation needs the renderer's imports.
  const appModule = WebAssembly.compileStreaming(fetchWithProgress(app, report('app')));
  appModule.catch(() => {}); // observed below even if the renderer fails first
  const fontManifest = typeof fonts === 'string'
    ? fetch(fonts).then(response => {
        if (!response.ok) throw new Error(`starling: ${fonts}: ${response.status}`);
        return response.json();
      }) : Promise.resolve(fonts);
  const fontFiles = fontManifest.then(entries => Promise.all(entries.filter(entry => !entry.lazy).map(async entry => {
    const response = await fetch(entry.url);
    if (!response.ok) throw new Error(`starling: ${entry.url}: ${response.status}`);
    return { ...entry, bytes: new Uint8Array(await response.arrayBuffer()) };
  })));
  fontFiles.catch(() => {});
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
    // Files: the browser's picker in, a download out. The picker needs a
    // user gesture; it is opened from the click that asked for it, which
    // is the case when the app calls from a button's handler.
    open_file(pointer, length) {
      const accept = utf8.decode(appBytes().subarray(pointer, pointer + length))
        .split(',').filter(Boolean).map((ext) => '.' + ext).join(',');
      // One input, kept in the document: a picker is only openable from a
      // real element, and a test can hand this one a file.
      let input = document.getElementById('starling-file');
      if (!input) {
        input = Object.assign(document.createElement('input'), { type: 'file', id: 'starling-file' });
        input.style.display = 'none';
        document.body.append(input);
      }
      input.accept = accept;
      input.value = '';
      const answer = (name, bytes) => {
        const nameBytes = encoder.encode(name);
        const namePointer = nameBytes.length ? swift.starling_alloc(nameBytes.length) : 0;
        if (namePointer) appBytes().set(nameBytes, namePointer);
        const dataPointer = bytes.length ? swift.starling_alloc(bytes.length) : 0;
        if (dataPointer) appBytes().set(bytes, dataPointer);
        swift.starling_file_opened(namePointer, nameBytes.length, dataPointer, bytes.length);
        if (namePointer) swift.starling_free(namePointer);
      };
      // No cancel handler: the browser's `cancel` is not to be trusted (a
      // headless one fires it as the dialog opens), and a pick that never
      // comes costs the app nothing — the next open supersedes it.
      input.onchange = async () => {
        const file = input.files[0];
        if (!file) return;
        answer(file.name, new Uint8Array(await file.arrayBuffer()));
      };
      input.click();
    },
    download(namePointer, nameLength, bytesPointer, byteCount) {
      const name = utf8.decode(appBytes().subarray(namePointer, namePointer + nameLength));
      const bytes = appBytes().slice(bytesPointer, bytesPointer + byteCount);
      const url = URL.createObjectURL(new Blob([bytes]));
      const a = Object.assign(document.createElement('a'), { href: url, download: name });
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 10000);
    },
    set_title(pointer, length) {
      document.title = utf8.decode(appBytes().subarray(pointer, pointer + length));
      // Office marks unsaved work in its title ("Name • — Writer", "… — Slides")
      // — the one signal a tab has, since there is no recovery copy here:
      // leaving the page with it set asks first.
      unsaved = document.title.includes(' \u2022');
    },
    // The browser decodes what skwasm cannot (the light build has no
    // codecs). The bytes are copied out before returning — the app may
    // free them — and the bitmap becomes a texture in skwasm's context,
    // which is why the surface comes along.
    decode_image(requestId, bytes, length, surface) {
      const copy = appBytes().slice(bytes, bytes + length);
      createImageBitmap(new Blob([copy]), { premultiplyAlpha: 'premultiply' })
        .then((bitmap) => {
          const image = sk.image_createFromTextureSource(bitmap, bitmap.width, bitmap.height, surface);
          swift.starling_image_decoded(requestId, image, bitmap.width, bitmap.height);
        })
        .catch((error) => {
          console.warn('starling: image did not decode:', error.message);
          swift.starling_image_decoded(requestId, 0, 0, 0);
        });
    },
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
  host.timezone_offset = seconds => new Date(seconds * 1000).getTimezoneOffset() * 60;

  let fontLoader;
  host.request_font = (pointer, length) => {
    const family = utf8.decode(appBytes().subarray(pointer, pointer + length));
    fontLoader.request(family);
  };

  const instance = await WebAssembly.instantiate(await appModule, {
    wasi_snapshot_preview1: makeWasi(() => swift.memory, args),
    skwasm: sk,
    starling: host,
  });
  swift = instance.exports;
  swift._initialize();

  // --- fonts, before the app builds its first frame. skwasm cannot see
  // system fonts: eager faces are fetched and handed over as bytes, written
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
    if (!ok) throw new Error(`starling: font for '${family}' did not parse`);
  };
  // `fonts` is a list of {url, families}, or the URL of a JSON file holding
  // one (build/web-app.sh writes fonts/manifest.json). An empty families
  // list registers the face under the family name inside the file.
  onPhase?.('Preparing fonts…');
  fonts = await fontFiles;
  // Register in manifest order so fallback choice is independent of network timing.
  const defaultFamily = fonts[0]?.families[0];
  for (const { families, bytes } of fonts) {
    if (families.length === 0) registerFont(bytes, null);
    for (const family of families) registerFont(bytes, family);
    if (defaultFamily && families.includes(defaultFamily)) registerFont(bytes, SKWASM_FALLBACK_FAMILY);
  }
  // Glyph fallback: the families marked `fallback` are tried, in manifest
  // order, for characters the requested family lacks (⌘ in a UI face).
  for (const { families, fallback } of fonts) {
    if (!fallback) continue;
    const name = encoder.encode(families[0]);
    const pointer = swift.starling_alloc(name.length);
    appBytes().set(name, pointer);
    swift.starling_font_fallback(pointer, name.length);
    swift.starling_free(pointer);
  }

  const manifest = await fontManifest;
  if (manifest.some(entry => entry.lazy) && !swift.starling_fonts_changed) {
    throw new Error('starling: deferred fonts require a rebuilt app.wasm');
  }
  fontLoader = createFontLoader(manifest, {
    register: registerFont,
    changed: () => swift.starling_fonts_changed(),
    status: onFontStatus,
  });

  const transfer = (bytes, callback) => {
    const pointer = swift.starling_alloc(bytes.length);
    try { appBytes().set(bytes, pointer); return callback(pointer, bytes.length); }
    finally { swift.starling_free(pointer); }
  };
  if (initialRoute) transfer(encoder.encode(initialRoute), (pointer, length) => swift.starling_initial_route(pointer, length));
  for (const file of await startupFiles) {
    transfer(encoder.encode(file.name), (name, nameLength) =>
      transfer(file.bytes, (pointer, length) => swift.starling_startup_file(name, nameLength, pointer, length)));
  }

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
  onPhase?.('Drawing document…');
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

  // Keys. The framework wants what every engine embedder gives it: a
  // physical id (the key's position, from `code`), a logical id (its
  // meaning, from `key`), and the character it types, if any. The two
  // tables are the web engine's own. A key neither knows gets an id in the
  // "web" plane made from the name, as Flutter's web engine does, so that
  // down and up at least agree.
  const WEB_PLANE = 0x1700000000n;
  const hashName = (name) => {
    let h = 0;
    for (const c of name) h = (h * 31 + c.codePointAt(0)) & 0xffffffff;
    return WEB_PLANE + BigInt(h >>> 0);
  };
  const KEY_DOWN = 0, KEY_UP = 1, KEY_REPEAT = 2;
  const pressed = new Set();
  const key = (dom) => {
    if (!captureTab && dom.key === "Tab") return;
    const physical = BigInt(PHYSICAL.get(dom.code) ?? 0) || hashName(dom.code || dom.key);
    const isCharacter = dom.key.length === 1 || [...dom.key].length === 1;
    let logical = LOGICAL.get(dom.key);
    if (logical === undefined && LOGICAL_BY_LOCATION.has(dom.key)) {
      logical = LOGICAL_BY_LOCATION.get(dom.key)[dom.location] ?? LOGICAL_BY_LOCATION.get(dom.key)[0];
    }
    if (logical === undefined && isCharacter) {
      // Printable: the code point of the lower-case character, Flutter's
      // "unicode plane".
      logical = BigInt(dom.key.toLowerCase().codePointAt(0));
    }
    if (logical === undefined) logical = hashName(dom.key);

    let type;
    if (dom.type === 'keyup') {
      if (!pressed.has(dom.code)) return;  // an up we never saw the down of
      pressed.delete(dom.code);
      type = KEY_UP;
    } else {
      type = pressed.has(dom.code) ? KEY_REPEAT : KEY_DOWN;
      pressed.add(dom.code);
    }
    // The character typed, on down and repeat, unless a modifier makes
    // it a shortcut rather than text.
    const character = type !== KEY_UP && isCharacter && !dom.ctrlKey && !dom.metaKey ? dom.key : '';
    const bytes = encoder.encode(character);
    const pointer = bytes.length ? swift.starling_alloc(bytes.length) : 0;
    if (pointer) appBytes().set(bytes, pointer);
    swift.starling_key(type, physical, logical, pointer, bytes.length, dom.timeStamp);
    if (pointer) swift.starling_free(pointer);
    // The browser's own shortcuts (reload, new tab, find) stay the
    // browser's; everything else is the app's, so Tab and Space do not
    // scroll or move focus out of the canvas.
    if (!dom.metaKey && !dom.ctrlKey) dom.preventDefault();
  };
  canvas.tabIndex = 0;
  canvas.addEventListener('keydown', key);
  canvas.addEventListener('keyup', key);
  canvas.addEventListener('pointerdown', () => canvas.focus());
  canvas.focus();
  // Keys held while the tab loses focus never send an up; release them.
  window.addEventListener('blur', () => {
    for (const code of [...pressed]) key({ type: 'keyup', code, key: 'Unidentified', location: 0, timeStamp: performance.now() });
  });
  canvas.addEventListener('wheel', (dom) => {
    const box = canvas.getBoundingClientRect();
    // deltaMode 1 is lines, 2 is pages; the framework wants pixels.
    const unit = dom.deltaMode === 1 ? 16 : dom.deltaMode === 2 ? box.height : 1;
    swift.starling_scroll(
      0, dom.clientX - box.left, dom.clientY - box.top,
      dom.deltaX * unit, dom.deltaY * unit, dom.timeStamp);
    dom.preventDefault();
  }, { passive: false });

  // A debugging door for scripts: `starling.debug('layout')` in Office
  // returns the document's lines and pages as text, the same text
  // `OfficeApp --layout` prints natively. null for a kind the app does
  // not answer.
  const debug = (kind) => {
    const name = encoder.encode(kind);
    const namePointer = swift.starling_alloc(name.length);
    appBytes().set(name, namePointer);
    const lengthPointer = swift.starling_alloc(4);
    const pointer = swift.starling_debug(namePointer, name.length, lengthPointer);
    swift.starling_free(namePointer);
    let text = null;
    if (pointer) {
      const length = new DataView(swift.memory.buffer).getInt32(lengthPointer, true);
      text = utf8.decode(appBytes().subarray(pointer, pointer + length));
      swift.starling_free(pointer);
    }
    swift.starling_free(lengthPointer);
    return text;
  };

  return { skwasm, swift, debug, loadFonts: families => Promise.all(families.map(fontLoader.load)), retryFonts: fontLoader.retry };
}
