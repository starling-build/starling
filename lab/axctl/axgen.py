#!/usr/bin/env python3
"""Generate MS Forms ActiveX control .bin files (OLE compound files) and a pptx lab deck.

MorphData family (TextBox, CheckBox, OptionButton, ComboBox, ListBox, ToggleButton):
  contents = version(2) size(2) mask(8) small ints (aligned) [pair] strings(4-aligned) | font block
Layout is the inverse of apps/OfficeApp/.../Slides/ActiveXControl.swift's reader (from LibreOffice oox/ole).
"""
import struct, sys, os, zipfile, shutil, re

# ---------------------------------------------------------------- compound file writer
def cfb(streams):
    """streams: list of (name, bytes). All go to the mini stream (<4096 each). Returns bytes."""
    SS, MSS = 512, 64
    # mini stream
    mini = b''; mfat = []; starts = []
    for name, data in streams:
        n = (len(data) + MSS - 1) // MSS
        starts.append(len(mfat))
        for i in range(n): mfat.append(len(mfat) + 1 if i < n - 1 else 0xFFFFFFFE)
        mini += data + b'\0' * (n * MSS - len(data))
    nmini = len(mfat)
    mfat += [0xFFFFFFFF] * (-len(mfat) % 128)
    minifat = struct.pack('<%dI' % len(mfat), *mfat)
    # directory
    def ent(name, typ, left, right, child, start, size, clsid=b'\0' * 16, color=1):
        nm = name.encode('utf-16le') + b'\0\0'
        e = nm.ljust(64, b'\0') + struct.pack('<H', len(nm)) + bytes([typ, color])
        e += struct.pack('<III', left, right, child) + clsid + struct.pack('<IIIII', 0, 0, 0, 0, 0)
        e += struct.pack('<IQ', start, size)[0:4] + struct.pack('<Q', size)
        return e
    co = [d for n, d in streams if 'CompObj' in n]
    ents = [ent('Root Entry', 5, 0xFFFFFFFF, 0xFFFFFFFF, 1 if streams else 0xFFFFFFFF, 0, 0, clsid=co[0][12:28] if co else b'\0' * 16)]  # start/size patched below
    # chain the streams as a simple right-sibling list: 1 -> 2 -> 3 ...
    for i, (name, data) in enumerate(streams):
        right = i + 2 if i + 1 < len(streams) else 0xFFFFFFFF
        ents.append(ent(name, 2, 0xFFFFFFFF, right, 0xFFFFFFFF, starts[i], len(data)))
    while len(ents) % 4: ents.append(b'\0' * 128)
    # sector plan: 0 FAT, 1 directory (ents/4 sectors), then minifat, then ministream
    ndir = len(ents) // 4
    nmf = len(minifat) // SS
    nms = len(mini) // SS if len(mini) % SS == 0 else len(mini) // SS + 1
    mini += b'\0' * (nms * SS - len(mini))
    dir_start = 1; mf_start = 1 + ndir; ms_start = mf_start + nmf
    total = ms_start + nms
    fat = [0xFFFFFFFD] + [0] * (total - 1)
    def link(a, n):
        for i in range(n): fat[a + i] = a + i + 1 if i < n - 1 else 0xFFFFFFFE
    link(dir_start, ndir); link(mf_start, nmf); link(ms_start, nms)
    fat += [0xFFFFFFFF] * (128 - len(fat)); assert total <= 128
    # root entry: start of mini stream and its size
    root = bytearray(ents[0]); root[116:120] = struct.pack('<I', ms_start); root[120:128] = struct.pack('<Q', nmini * MSS)
    ents[0] = bytes(root)
    hdr = bytes.fromhex('D0CF11E0A1B11AE1') + b'\0' * 16 + struct.pack('<HHHHH', 0x3E, 3, 0xFFFE, 9, 6) + b'\0' * 6
    hdr += struct.pack('<IIIIIIIII', 0, 1, dir_start, 0, 4096, mf_start, nmf, 0xFFFFFFFE, 0)
    hdr += struct.pack('<I', 0) + struct.pack('<108I', *([0xFFFFFFFF] * 108))
    hdr = hdr[:76] + struct.pack('<I', 0) + hdr[80:]
    # DIFAT[0] = sector 0 (the FAT)
    hdr = hdr[:76] + struct.pack('<I', 0) + struct.pack('<108I', *([0xFFFFFFFF] * 108))
    assert len(hdr) == 76 + 4 + 432 == 512, len(hdr)
    out = hdr + struct.pack('<128I', *fat) + b''.join(ents) + minifat + mini
    return out

# ---------------------------------------------------------------- MorphData writer
class W:
    def __init__(s): s.b = bytearray()
    def al(s, n): s.b += b'\0' * (-len(s.b) % n)
    def put(s, n, v, al=True):
        if al: s.al(n)
        s.b += int(v).to_bytes(n, 'little')

def color(c):
    """'RRGGBB' -> COLORREF int; int stays (system colours as 0x80000005 etc.)."""
    if isinstance(c, int): return c
    r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    return r | g << 8 | b << 16

def morph(flags=0x2C80481B, back=0x80000005, text=0x80000008, border=0, bcolor=0x80000006, effect=0,
          value='', caption='', pw=0, align=1, font='Arial', pts=14.25, picpos=None, extra=None,
          group='', rows=None, match=None, multi=None, drop=None, ncols=None, maxlen=0, scroll=None,
          style=None, bound=None, tcol=None):
    """MorphData `contents` stream. Properties that are None/default are omitted (mask bit clear)."""
    ms = [1 << 0 if flags is not None else 0]
    mask = 0; w = W()
    # order of the small properties (bit index): see ActiveXControl.swift
    w.b = bytearray(b'\x00\x02\x00\x00')  # version 0x0200, size patched
    mask_pos = len(w.b); w.b += b'\0' * 8
    def bit(i): nonlocal mask; mask |= 1 << i
    # 0 flags 1 back 2 text 3 maxlen 4 border 5 scroll 6 display 7 mouse 8 pair 9 pw 10 listwidth
    # 11-13 bound/tcol/ncols 14 rows 15 colinfo 16 match 17 liststyle 18 dropbutton 19 undef 20 dropstyle 21 multi
    # 22 value 23 caption 24 picpos 25 bcolor 26 effect 27 mouseicon 28 picture 29 accel 30 undef 31 bool 32 group
    if flags is not None: bit(0); w.put(4, flags)
    if back is not None: bit(1); w.put(4, back)
    if text is not None: bit(2); w.put(4, text)
    if maxlen: bit(3); w.put(4, maxlen)
    if border: bit(4); w.put(1, border)
    if scroll is not None: bit(5); w.put(1, scroll)
    if pw: bit(9); w.put(2, pw)
    if bound is not None: bit(11); w.put(2, bound)
    if tcol is not None: bit(12); w.put(2, tcol)
    if ncols is not None: bit(13); w.put(2, ncols)
    if rows is not None: bit(14); w.put(2, rows)
    if match is not None: bit(16); w.put(1, match)
    if style is not None: bit(17); w.put(1, style)
    if drop is not None: bit(18); w.put(1, drop)
    if multi is not None: bit(21); w.put(1, multi)
    strs = []
    if value: bit(22); w.put(4, len(value) | 0x80000000); strs.append(value.encode('latin1'))
    if caption: bit(23); w.put(4, len(caption) | 0x80000000); strs.append(caption.encode('latin1'))
    if picpos is not None: bit(24); w.put(4, picpos)
    if bcolor is not None and border: bit(25); w.put(4, bcolor)
    if effect: bit(26); w.put(4, effect)
    w.al(4)
    for s in strs:
        w.b += s; w.al(4)
    size = len(w.b) - 4
    w.b[2:4] = struct.pack('<H', size)
    w.b[mask_pos:mask_pos + 8] = struct.pack('<Q', mask)
    # font block: version 0x0200? (corpus: 00 02 1c 00 + mask32)
    f = W(); f.b = bytearray(b'\x00\x02\x00\x00'); fm = 0; fmp = len(f.b); f.b += b'\0' * 4
    fbit = lambda i: None
    name = font.encode('latin1')
    fm |= 1; f.put(4, len(name) | 0x80000000)
    fm |= 4; f.put(4, int(round(pts * 20)))
    fm |= 1 << 4; f.put(1, 238)       # charset
    fm |= 1 << 5; f.put(1, 2)       # pitch
    fm |= 1 << 6; f.put(1, align)   # halign
    f.al(4); f.b += name; f.al(4)
    f.b[2:4] = struct.pack('<H', len(f.b) - 4); f.b[fmp:fmp + 4] = struct.pack('<I', fm)
    return bytes(w.b) + bytes(f.b)

if False:
    sys.path.insert(0, '/data/amd-6/tools')
    import cfb as rd, axtb
    # round trip: rebuild contents of the corpus textbox #2 and compare field by field
    s = rd.read(sys.argv[1])
    print(axtb.parse(s['contents']))


# ---------------------------------------------------------------- lab decks
TYPES = {  # name -> (classid, corpus dir)
    'textbox': '{8BD21D10-EC42-11CE-9E0D-00AA006002F3}',
    'listbox': '{8BD21D20-EC42-11CE-9E0D-00AA006002F3}',
    'combobox': '{8BD21D30-EC42-11CE-9E0D-00AA006002F3}',
    'checkbox': '{8BD21D40-EC42-11CE-9E0D-00AA006002F3}',
    'optionbutton': '{8BD21D50-EC42-11CE-9E0D-00AA006002F3}',
    'togglebutton': '{8BD21D60-EC42-11CE-9E0D-00AA006002F3}',
}
TEMPLATE = '/data/amd-6/w/sl/x'
CORPUS = '/tmp'  # /tmp/ax_<type>/ppt/activeX/activeX1.bin (unzipped corpus decks)

def variants():
    """(label, kwargs) for the MorphData family."""
    v = []
    for en in (1, 0):
        for al in (1, 3, 2):
            for bd in (0, 1):
                fl = 0x2C80481B if en else 0x2C804819
                v.append((f"{'en' if en else 'dis'}-{'LCR'[ [1,3,2].index(al)]}-b{bd}",
                          dict(flags=fl, align=al, border=bd, bcolor=0xFF if bd else 0x80000006)))
    base = 0x2C80481B
    v.append(('back-green-opaque', dict(flags=base, back=0xC000, border=1, bcolor=0xFF, align=3)))
    v.append(('back-green-clear', dict(flags=base & ~8, back=0xC000, border=1, bcolor=0xFF, align=3)))
    v.append(('font-times-10', dict(flags=base, font='Times New Roman', pts=10.5, align=1)))
    v.append(('text-red', dict(flags=base, text=0xFF, align=1)))
    return v

def make_deck(path, typ, items):
    """items: up to 4 (label, kwargs); writes a pptx whose controls 1..4 are `typ` with those settings."""
    import tempfile
    sys.path.insert(0, '/data/amd-6/tools')
    import cfb as rd
    work = tempfile.mkdtemp(prefix='axdeck')
    shutil.copytree(TEMPLATE, work + '/d')
    d = work + '/d'
    co = rd.read(f'{CORPUS}/ax_{typ}/ppt/activeX/activeX1.bin')['\x01CompObj']
    for i in range(1, 5):
        it = items[i - 1] if i <= len(items) else items[-1]
        kw = dict(it[1])
        key = 'value' if typ == 'textbox' else 'caption'
        if typ in SEQ:
            if typ in ('commandbutton', 'label'): kw.setdefault('caption', 'Some Text')
            c = fcontrol(typ, **kw)
        else:
            kw.setdefault(key, 'Some Text')
            if typ == 'textbox' and 'pw' not in kw: kw['pw'] = 0
            c = morph(**kw)
        open(f'{d}/ppt/activeX/activeX{i}.bin', 'wb').write(cfb([('\x01CompObj', co), ('contents', c)]))
        x = open(f'{d}/ppt/activeX/activeX{i}.xml').read()
        x = re.sub(r'ax:classid="[^"]*"', f'ax:classid="{TYPES[typ]}"', x)
        open(f'{d}/ppt/activeX/activeX{i}.xml', 'w').write(x)
    # label each slot's shape name so the print is identifiable
    s = open(f'{d}/ppt/slides/slide1.xml').read()
    for i, it in enumerate(items[:4], 1):
        s = s.replace(f'name="TextBox{i}"', f'name="{typ}-{it[0]}"')
    open(f'{d}/ppt/slides/slide1.xml', 'w').write(s)
    if os.path.exists(path): os.remove(path)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        # [Content_Types].xml first
        z.write(d + '/[Content_Types].xml', '[Content_Types].xml')
        for root, _, files in os.walk(d):
            for f in files:
                full = os.path.join(root, f); arc = os.path.relpath(full, d)
                if arc != '[Content_Types].xml': z.write(full, arc)
    shutil.rmtree(work)

def lab(outdir):
    os.makedirs(outdir, exist_ok=True)
    n = 0
    for typ in TYPES:
        vs = variants()
        for k in range(0, len(vs), 4):
            make_deck(f'{outdir}/axctl-{typ}-{k // 4 + 1}.pptx', typ, vs[k:k + 4]); n += 1
    print(n, 'decks in', outdir)


# ---------------------------------------------------------------- the other layouts (32-bit mask)
SEQ = {
  'commandbutton': [('i4','text'),('i4','back'),('i4','flags'),('s','caption'),('i4','picpos'),('pair','size'),('i1','mouse'),('pic','pic'),('i2','accel'),('bool','nofocus'),('pic','mouseicon')],
  'label': [('i4','text'),('i4','back'),('i4','flags'),('s','caption'),('i4','picpos'),('pair','size'),('i1','mouse'),('i4','bcolor'),('i2','bstyle'),('i2','effect'),('pic','pic'),('i2','accel'),('pic','mouseicon')],
  'spinbutton': [('i4','arrow'),('i4','back'),('i4','flags'),('pair','size'),('i4','unused'),('i4','min'),('i4','max'),('i4','pos'),('i4','prev'),('i4','next'),('i4','small'),('i4','orient'),('i4','delay'),('pic','mouseicon'),('i1','mouse')],
  'scrollbar': [('i4','arrow'),('i4','back'),('i4','flags'),('pair','size'),('i1','mouse'),('i4','min'),('i4','max'),('i4','pos'),('i4','unused'),('i4','prev'),('i4','next'),('i4','small'),('i4','large'),('i4','orient'),('i2','thumb'),('i4','delay'),('pic','mouseicon')],
}
HASFONT = {'commandbutton': True, 'label': True, 'spinbutton': False, 'scrollbar': False}

def fcontrol(typ, font='Arial', pts=14.25, align=1, **vals):
    w = W(); w.b = bytearray(b'\x00\x02\x00\x00'); mp = len(w.b); w.b += b'\0' * 4
    mask = 0; large = []
    for i, (kind, key) in enumerate(SEQ[typ]):
        v = vals.get(key)
        if v is None: continue
        mask |= 1 << i
        if kind in ('i4', 'i2', 'i1'): w.put(int(kind[1]), v if v >= 0 else v + (1 << (8 * int(kind[1]))))
        elif kind == 's': w.put(4, len(v) | 0x80000000); large.append(('s', v))
        elif kind == 'pair': large.append(('pair', v))
    w.al(4)
    for k, v in large:
        if k == 's': w.b += v.encode('latin1')
        else: w.b += struct.pack('<ii', *v)
        w.al(4)
    w.b[2:4] = struct.pack('<H', len(w.b) - 4); w.b[mp:mp + 4] = struct.pack('<I', mask)
    out = bytes(w.b)
    if HASFONT[typ]:
        f = W(); f.b = bytearray(b'\x00\x02\x00\x00'); fmp = len(f.b); f.b += b'\0' * 4
        name = font.encode('latin1'); fm = 1 | 4 | (1 << 4) | (1 << 5) | (1 << 6)
        f.put(4, len(name) | 0x80000000); f.put(4, int(round(pts * 20))); f.put(1, 238); f.put(1, 2); f.put(1, align)
        f.al(4); f.b += name; f.al(4)
        f.b[2:4] = struct.pack('<H', len(f.b) - 4); f.b[fmp:fmp + 4] = struct.pack('<I', fm)
        out += bytes(f.b)
    return out

TYPES.update({
  'commandbutton': '{D7053240-CE69-11CD-A777-00DD01143C57}',
  'label': '{978C9E23-D4B0-11CE-BF2D-00AA003F40D0}',
  'scrollbar': '{DFD181E0-5E2F-11CE-A449-00AA004A803D}',
  'spinbutton': '{79176FB0-B7F2-11CE-97EF-00AA006D2776}',
})

def fvariants(typ):
    v = []
    if typ in ('commandbutton', 'label'):
        base = 0x0000001B if typ == 'commandbutton' else 0x0080001B
        for en in (1, 0):
            for al in (1, 3, 2):
                v.append((f"{'en' if en else 'dis'}-{'LCR'[[1,3,2].index(al)]}", dict(flags=base if en else base & ~2, align=al)))
        v.append(('back-green', dict(flags=base, back=0xC000, align=3)))
        v.append(('text-red', dict(flags=base, text=0xFF, align=3)))
        v.append(('font-times-10', dict(flags=base, font='Times New Roman', pts=10.5, align=1)))
        if typ == 'label':
            for bs in (1,):
                v.append(('border1-red', dict(flags=base, bstyle=1, bcolor=0xFF, align=3)))
                v.append(('border1-red-back', dict(flags=base, bstyle=1, bcolor=0xFF, back=0xC000, align=1)))
            v.append(('sunken', dict(flags=base, effect=2, align=1)))
            v.append(('raised', dict(flags=base, effect=1, align=1)))
        else:
            v.append(('picpos-left', dict(flags=base, picpos=0, align=1)))
            v.append(('picpos-right', dict(flags=base, picpos=1, align=1)))
    else:
        base = 0x0000001B
        for en in (1, 0):
            for o in (0, 1):
                v.append((f"{'en' if en else 'dis'}-{'V' if o == 0 else 'H'}", dict(flags=base if en else base & ~2, orient=o, min=0, max=100, pos=30)))
        v.append(('arrow-red', dict(flags=base, arrow=0xFF, orient=1, min=0, max=100, pos=30)))
        v.append(('back-green', dict(flags=base, back=0xC000, orient=1, min=0, max=100, pos=30)))
        v.append(('pos-min', dict(flags=base, orient=1, min=0, max=100, pos=0)))
        v.append(('pos-max', dict(flags=base, orient=1, min=0, max=100, pos=100)))
    return v

def lab2(outdir):
    for typ in ('commandbutton', 'label', 'scrollbar', 'spinbutton'):
        vs = fvariants(typ)
        for k in range(0, len(vs), 4):
            make_deck(f'{outdir}/axctl-{typ}-{k // 4 + 1}.pptx', typ, vs[k:k + 4])
