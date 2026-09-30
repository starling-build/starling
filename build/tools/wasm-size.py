#!/usr/bin/env python3
"""What a wasm module weighs, and why.

    wasm-size.py app.wasm                      section sizes
    wasm-size.py app.wasm --why why.tsv        + which of OUR objects pulled
                                               in the archives we refuse
    wasm-size.py app.wasm --budget 20000000    exit 1 if larger
    wasm-size.py app.wasm --by-module          code bytes per Swift module
                                               (needs the name section:
                                               a debug build, or a release
                                               built with STARLING_WASM_NAMES=1)

`why.tsv` is what wasm-ld writes for `--why-extract=`: one line per archive
member it extracted, with the object that referenced it and the symbol. The
archives refused are the legacy Foundation module and everything ICU: on
this target they cost 40 MB of tables and are reached only by accident
(docs/plans/wasm-size.md). The check walks each extraction back to the first
object of ours, so the report names the call to change, not the archive.
"""
import argparse
import collections
import re
import shutil
import subprocess
import sys

REFUSED = ("lib_FoundationICU.a", "libFoundationInternationalization.a", "libFoundation.a")

SECTION_NAMES = {
    1: "type", 2: "import", 3: "function", 4: "table", 5: "memory", 6: "global",
    7: "export", 8: "start", 9: "elem", 10: "code", 11: "data", 12: "datacount",
}


def leb(b, i):
    result = shift = 0
    while True:
        byte = b[i]
        i += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return result, i


def sections(path):
    b = open(path, "rb").read()
    sizes = collections.OrderedDict()
    i = 8
    while i < len(b):
        sid = b[i]
        n, i = leb(b, i + 1)
        if sid == 0:
            length, j = leb(b, i)
            name = "custom:" + b[j:j + length].decode(errors="replace")
        else:
            name = SECTION_NAMES.get(sid, str(sid))
        sizes[name] = sizes.get(name, 0) + n
        i += n
    return len(b), sizes


def code_by_module(path):
    """Code bytes per module, from function names. Swift names carry their
    module; C++ and C are grouped by prefix."""
    b = open(path, "rb").read()
    i = 8
    sizes = []
    names = {}
    imports = 0
    while i < len(b):
        sid = b[i]
        n, i = leb(b, i + 1)
        end = i + n
        if sid == 2:
            count, j = leb(b, i)
            for _ in range(count):
                length, j = leb(b, j); j += length
                length, j = leb(b, j); j += length
                kind = b[j]; j += 1
                if kind == 0:
                    _, j = leb(b, j); imports += 1
                elif kind == 1:
                    j += 1; flags, j = leb(b, j); _, j = leb(b, j)
                    if flags & 1: _, j = leb(b, j)
                elif kind == 2:
                    flags, j = leb(b, j); _, j = leb(b, j)
                    if flags & 1: _, j = leb(b, j)
                elif kind == 3:
                    j += 2
        elif sid == 10:
            count, j = leb(b, i)
            for _ in range(count):
                size, j = leb(b, j)
                sizes.append(size)
                j += size
        elif sid == 0:
            length, j = leb(b, i)
            if b[j:j + length] == b"name":
                j += length
                while j < end:
                    sub = b[j]
                    sublen, j = leb(b, j + 1)
                    subend = j + sublen
                    if sub == 1:
                        count, j = leb(b, j)
                        for _ in range(count):
                            index, j = leb(b, j)
                            length, j = leb(b, j)
                            names[index] = b[j:j + length].decode(errors="replace")
                            j += length
                    j = subend
        i = end
    if not names:
        return None
    by_module = collections.Counter()
    for k, size in enumerate(sizes):
        name = names.get(k + imports, "")
        m = re.match(r"\$[sS](\d+)([A-Za-z_][A-Za-z0-9_]*)", name)
        if m:
            module = m.group(2)[: int(m.group(1))]
        elif name.startswith("$s") or name.startswith("$S"):
            module = "Swift"
        elif "::" in name or name.startswith("_Z"):
            module = "C++"
        else:
            module = "C"
        by_module[module] += size
    return sum(sizes), by_module


def member(path):
    """'libFoo.a(bar.o)' for an archive member, else the object's basename."""
    m = re.search(r"(lib[^/(]+\.a)\(([^)]+)\)", path)
    return (m.group(1), m.group(2)) if m else (path.rsplit("/", 1)[-1], None)


def refused_chains(why_path):
    """For each refused archive: the first object of ours that leads to it,
    and the symbol it wanted, by walking wasm-ld's extraction chain back."""
    parent = {}
    with open(why_path) as f:
        next(f)
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 3:
                continue
            ref, extracted, symbol = parts
            parent.setdefault(member(extracted), (member(ref), symbol))

    def root(node):
        seen = set()
        symbol = None
        while node in parent and node not in seen:
            seen.add(node)
            node, symbol = parent[node], parent[node][1]
            node = node[0]
        return node, symbol

    found = collections.defaultdict(collections.Counter)
    for node in parent:
        lib, _ = node
        if lib in REFUSED:
            origin, symbol = root(node)
            if origin[1] is None:  # one of our objects, not an archive
                found[lib][(origin[0], symbol)] += 1
    return found


def demangle(symbols):
    """Swift names, readable, when a toolchain is on PATH; as given if not."""
    tool = shutil.which("swift-demangle")
    if tool is None:
        return dict(zip(symbols, symbols))
    out = subprocess.run(
        [tool, "--simplified"], input="\n".join(symbols), capture_output=True, text=True
    ).stdout.splitlines()
    return dict(zip(symbols, out)) if len(out) == len(symbols) else dict(zip(symbols, symbols))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wasm")
    ap.add_argument("--why", help="wasm-ld --why-extract output")
    ap.add_argument("--budget", type=int, help="fail if the file is larger")
    ap.add_argument("--by-module", action="store_true", help="code bytes per module")
    args = ap.parse_args()

    total, sizes = sections(args.wasm)
    print(f"  {total / 1e6:7.2f} MB  {args.wasm.rsplit('/', 1)[-1]}")
    for name, n in sorted(sizes.items(), key=lambda kv: -kv[1]):
        if n >= 100_000:
            print(f"  {n / 1e6:7.2f} MB    {name}")

    if args.by_module:
        result = code_by_module(args.wasm)
        if result is None:
            print("\n  no name section (build with STARLING_WASM_NAMES=1, or debug)")
        else:
            total_code, by_module = result
            print(f"\n  code by module ({total_code / 1e6:.1f} MB):")
            for module, n in by_module.most_common(20):
                print(f"  {n / 1e6:7.2f} MB    {module}")

    failed = False
    if args.why:
        found = refused_chains(args.why)
        names = demangle(sorted({s for c in found.values() for (_, s) in c}))
        for lib in REFUSED:
            if lib in found:
                failed = True
                print(f"\n  {lib} is linked. Reached from:")
                for (obj, symbol), n in found[lib].most_common(8):
                    print(f"    {obj:32s} {names[symbol][:100]}")
        if not failed:
            print("\n  none of the refused archives is linked")

    if args.budget is not None and total > args.budget:
        failed = True
        print(f"\n  over budget: {total} > {args.budget} bytes")

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
