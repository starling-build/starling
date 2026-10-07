// Deferred families are fetched as a unit so regular/bold/italic metrics arrive
// together. Keep successful files across retries; never cache a failed request.
export function createFontLoader(entries, { register, changed, status = () => {}, fetchBytes = async url => {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
} }) {
  const families = new Map();
  for (const entry of entries.filter(entry => entry.lazy)) {
    for (const family of entry.families) {
      const key = family.toLowerCase();
      if (!families.has(key)) families.set(key, []);
      families.get(key).push(entry);
    }
  }
  const files = new Map(), pending = new Map(), loaded = new Set(), failed = new Map();
  const report = () => status({ pending: [...pending.keys()], failed: [...failed.keys()] });
  function load(family) {
    const key = family.toLowerCase();
    if (!families.has(key) || loaded.has(key)) return Promise.resolve();
    if (pending.has(key)) return pending.get(key);
    // Defer work to a microtask: the request can originate inside Swift layout.
    const promise = Promise.resolve().then(async () => {
      await Promise.all(families.get(key).map(entry => {
        if (!files.has(entry.url)) {
          const file = fetchBytes(entry.url).then(bytes => {
            for (const alias of entry.families) register(bytes, alias);
          }).catch(error => { files.delete(entry.url); throw error; });
          files.set(entry.url, file);
        }
        return files.get(entry.url);
      }));
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
  return {
    load,
    // Layout may ask repeatedly while a download is failing. Retry only on an
    // explicit user action, rather than turning every frame into a new request.
    request(family) {
      if (!failed.has(family.toLowerCase())) load(family).catch(error => console.warn('starling: font download failed', error));
    },
    retry() { return Promise.all([...failed.keys()].map(load)); },
  };
}
