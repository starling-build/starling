// Deferred fonts are fetched as a unit so regular/bold/italic metrics arrive
// together. Keep successful files across retries; never cache a failed request.
//
// An entry is one DOWNLOAD. A plain file has `families` (aliases). A script
// file or a collection has `faces` [{index, family}] — `index` -1 for a plain
// file — and `scripts` (the character scripts it is the glyph fallback for, as
// Resources/fonts/fonts.tsv names them: cjk-sc, arabic…), `weight` (400 | 700),
// `order` (position in the glyph-fallback chain, 0 = not in it) and `gzip`
// (fetch url + '.gz' and inflate it here: GitHub Pages sends no
// Content-Encoding for fonts). docs/plans/web-lazy-fonts.md has the design.
//
// A weight-700 entry is never fetched because its family was NAMED (a Bold
// CJK collection is 20 MB) — only by `loadScript(script, {bold: true})`.
//
// `registerFile(bytes, faces)` takes all of a collection's faces at once, to
// share one copy of the bytes; without it `register(bytes, family, faceIndex)`
// runs once per face.
export async function inflateGzip(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

export function createFontLoader(entries, { register, registerFile, changed, status = () => {}, inflate = inflateGzip, fetchBytes = async url => {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
} }) {
  const lazy = entries.filter(entry => entry.lazy);
  const facesOf = entry => entry.faces ?? entry.families.map(family => ({ index: -1, family }));
  const families = new Map(), scripts = new Map();
  for (const entry of lazy) {
    if (entry.weight !== 700) {
      for (const { family } of facesOf(entry)) {
        const key = family.toLowerCase();
        if (!families.has(key)) families.set(key, []);
        if (!families.get(key).includes(entry)) families.get(key).push(entry);
      }
    }
    for (const script of entry.scripts ?? []) {
      if (!scripts.has(script)) scripts.set(script, []);
      scripts.get(script).push(entry);
    }
  }
  // Entries asked for, synchronously, by name or by script: a script's fallback
  // is only fetched when nothing of that script is wanted already (a document
  // that names 宋体 has the Serif collection, which has the characters).
  const wanted = new Set();
  const files = new Map(), pending = new Map(), loaded = new Set(), failed = new Map(), retries = new Map();
  const report = () => status({ pending: [...pending.keys()], failed: [...failed.keys()] });

  function fetchEntry(entry) {
    if (!files.has(entry.url)) {
      const file = (async () => {
        const raw = await fetchBytes(entry.gzip ? entry.url + '.gz' : entry.url);
        const bytes = entry.gzip ? await inflate(raw) : raw;
        if (entry.faces && registerFile) registerFile(bytes, entry.faces);
        else for (const { family, index } of facesOf(entry)) register(bytes, family, index);
      })().catch(error => { files.delete(entry.url); throw error; });
      files.set(entry.url, file);
    }
    return files.get(entry.url);
  }

  function run(key, group) {
    if (!group?.length || loaded.has(key)) return Promise.resolve();
    for (const entry of group) wanted.add(entry);
    if (pending.has(key)) return pending.get(key);
    retries.set(key, () => run(key, group));
    // Defer work to a microtask: the request can originate inside Swift layout.
    const promise = Promise.resolve().then(async () => {
      await Promise.all(group.map(fetchEntry));
      loaded.add(key);
      failed.delete(key);
      changed();
    }).catch(error => {
      failed.set(key, error);
      throw error;
    }).finally(() => { pending.delete(key); report(); });
    pending.set(key, promise);
    failed.delete(key);
    report();
    return promise;
  }

  const load = family => { const key = family.toLowerCase(); return run(key, families.get(key)); };
  // Every file that is the fallback for `script` (Regular; Bold when asked).
  const loadScript = (script, { bold = false } = {}) => {
    const all = scripts.get(script) ?? [];
    const here = all.filter(entry => entry.weight === (bold ? 700 : 400));
    // Regular: the fallback face (every face of a script outside the chain, such
    // as Thai), unless a face of this script is wanted already.
    const group = bold ? here : here.some(entry => wanted.has(entry)) ? [] : (here.some(entry => entry.fallback && entry.order > 0) ? here.filter(entry => entry.fallback && entry.order > 0) : here);
    return run(`script:${script}${bold ? ':bold' : ''}`, group);
  };
  // The glyph-fallback chain, as family names in table order — declared to the
  // app at start-up whether or not the files are loaded, so which face wins for
  // a character never depends on which download finished first.
  const fallbackChain = () => {
    const chain = [];
    const ordered = lazy.filter(entry => entry.fallback && entry.order > 0 && entry.weight !== 700)
      .map((entry, position) => ({ entry, position })).sort((a, b) => a.entry.order - b.entry.order || a.position - b.position);
    for (const { entry } of ordered) for (const { family } of facesOf(entry)) if (!chain.includes(family)) chain.push(family);
    return chain;
  };
  return {
    load,
    loadScript,
    fallbackChain,
    // The scripts a manifest can serve (the page asks by these).
    hasScript: script => scripts.has(script),
    // Layout may ask repeatedly while a download is failing. Retry only on an
    // explicit user action, rather than turning every frame into a new request.
    request(family) {
      if (!failed.has(family.toLowerCase())) load(family).catch(error => console.warn('starling: font download failed', error));
    },
    requestScript(script, options) {
      const key = `script:${script}${options?.bold ? ':bold' : ''}`;
      if (!failed.has(key)) loadScript(script, options).catch(error => console.warn('starling: font download failed', error));
    },
    retry() { return Promise.all([...failed.keys()].map(key => retries.get(key)())); },
  };
}
