#!/usr/bin/env python3
"""Extract everything OpenLF2 needs from an LF2 executable into a folder (default: lf2_exe).

  python3 extract_lf2_exe.py lf2.exe [OUT_DIR]

Writes
  OUT_DIR/<NAME>.bmp     every named RT_BITMAP resource (original RLE8 kept; OpenLF2 decodes it)
  OUT_DIR/recording.txt  line 1: recording version (decimal), line 2: recording key digits
Works for the original LF2 v2.0a lf2.exe and for LF2 Darkfiren's exe (whose layout differs).
"""
import re, struct, sys
from pathlib import Path

def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]

class Pe:
    def __init__(self, data):
        self.b = data
        if data[:2] != b'MZ': raise SystemExit('not a PE executable')
        pe = u32(data, 0x3c)
        if data[pe:pe+4] != b'PE\0\0' or u16(data, pe+24) != 0x10b: raise SystemExit('expected PE32')
        opt = u16(data, pe+20)
        self.base = u32(data, pe+24+28)
        so = pe+24+opt
        self.secs = []
        for i in range(u16(data, pe+6)):
            _, vs, va, rs, rp = struct.unpack_from('<8sIIII', data, so+i*40)
            self.secs.append((va, vs, rp, rs))
        self.rsrc_rva = u32(data, pe+24+112)
        self.rsrc_size = u32(data, pe+24+116)
        self.root = self.off(self.rsrc_rva) if self.rsrc_size else None

    def off(self, rva):
        for va, vs, rp, rs in self.secs:
            if va <= rva < va + max(vs, rs): return rp + rva - va
        raise ValueError('rva outside sections: %#x' % rva)

    def va_of_offset(self, offset):
        for va, vs, rp, rs in self.secs:
            if rp <= offset < rp + rs: return self.base + va + offset - rp
        return None

    def entries(self, d):
        b, o = self.b, self.root + d
        n = u16(b, o+12) + u16(b, o+14)
        for i in range(n):
            key, tgt = struct.unpack_from('<II', b, o+16+i*8)
            yield key, tgt

    def name(self, key):
        o = self.root + (key & 0x7fffffff)
        n = u16(self.b, o)
        return self.b[o+2:o+2+n*2].decode('utf-16le')

def bitmaps(pe):
    if pe.root is None: return
    for tkey, ttgt in pe.entries(0):
        if tkey != 2 or not ttgt & 0x80000000: continue          # RT_BITMAP
        for nkey, ntgt in pe.entries(ttgt & 0x7fffffff):
            label = pe.name(nkey) if nkey & 0x80000000 else 'ID%d' % nkey
            if not ntgt & 0x80000000: continue
            for lkey, ltgt in pe.entries(ntgt & 0x7fffffff):
                if ltgt & 0x80000000: continue
                rva, size = struct.unpack_from('<II', pe.b, pe.root + ltgt)
                dib = pe.b[pe.off(rva):pe.off(rva)+size]
                yield label, dib
                break

def dib_to_bmp(dib):
    hdr, w, h, planes, bpp, comp, img, _, _, used, _ = struct.unpack_from('<IiiHHIIiiII', dib, 0)
    colors = used or (1 << bpp if bpp <= 8 else 0)
    pixels = 14 + hdr + colors * 4
    return b'BM' + struct.pack('<IHHI', 14 + len(dib), 0, 0, pixels) + dib

def recording_constants(pe):
    """Key = the one long run of ASCII digits in initialised data; version = u32 0x764 bytes before it."""
    runs = [m for m in re.finditer(rb'[0-9]{1000,}', pe.b)]
    if len(runs) != 1: raise SystemExit('expected exactly one recording key digit run, found %d' % len(runs))
    m = runs[0]
    va = pe.va_of_offset(m.start())
    ver_va = va - 0x764                      # same distance in the original (0x44d7a0/0x44d03c) and in Darkfiren
    ver = u32(pe.b, m.start() - 0x764)
    return ver, m.group(0).decode(), va, ver_va

def main():
    if len(sys.argv) < 2: raise SystemExit(__doc__)
    data = Path(sys.argv[1]).read_bytes()
    out = Path(sys.argv[2] if len(sys.argv) > 2 else 'lf2_exe')
    out.mkdir(parents=True, exist_ok=True)
    pe = Pe(data)
    count = 0
    for name, dib in bitmaps(pe):
        (out / (name.upper() + '.bmp')).write_bytes(dib_to_bmp(dib)); count += 1
    ver, key, va, ver_va = recording_constants(pe)
    (out / 'recording.txt').write_text('%d\n%s\n' % (ver, key))
    print('%d bitmaps -> %s; recording key %d digits at %#x, version %d at %#x' % (count, out, len(key), va, ver, ver_va))

if __name__ == '__main__': main()
