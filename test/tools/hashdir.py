#!/usr/bin/env python3
"""hashdir.py DIR EXT — the set hash docx-pair.sh's refhash/dochash print: sha256 over "<name> <sha256 of file>\n" lines
(names sorted bytewise), first 32 hex digits. A file's sha256 is remembered by (name, size, mtime_ns) in
$HASH_CACHE (default ~/.cache/docx-hashes.json), so a gate hashes only files that changed (gates took ~150 s per pass
over the whole corpus before). Same value as the old sha256sum loop."""
import hashlib, json, os, sys
d, ext = sys.argv[1], sys.argv[2]
cp = os.environ.get('HASH_CACHE') or os.path.expanduser('~/.cache/docx-hashes.json')
try: cache = json.load(open(cp))
except Exception: cache = {}
new = {}; out = hashlib.sha256()
try: names = sorted(n for n in os.listdir(d) if n.endswith(ext))
except OSError: sys.exit(0)
for n in names:
    p = os.path.join(d, n); st = os.stat(p); k = f'{p}|{st.st_size}|{st.st_mtime_ns}'
    h = cache.get(k)
    if h is None: h = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    new[k] = h; out.update(f'{n} {h}\n'.encode())
if new != {k: v for k, v in cache.items() if k in new} or len(cache) > 4 * len(new) + 2000:
    try:
        os.makedirs(os.path.dirname(cp), exist_ok=True)
        cache.update(new); tmp = f'{cp}.{os.getpid()}'; json.dump(cache, open(tmp, 'w')); os.replace(tmp, cp)
    except OSError: pass
print(out.hexdigest()[:32])
