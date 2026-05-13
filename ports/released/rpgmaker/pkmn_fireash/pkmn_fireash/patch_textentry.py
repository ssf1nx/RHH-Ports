#!/usr/bin/env python3
import sys, zlib


def enc_fixnum(n):
    if n == 0:
        return b"\x00"
    if 0 < n < 123:
        return bytes([n + 5])
    if -123 < n < 0:
        return bytes([(n - 5) & 0xff])
    if n > 0:
        out = bytearray()
        x = n
        while x > 0:
            out.append(x & 0xff)
            x >>= 8
        return bytes([len(out)]) + bytes(out)
    out = bytearray()
    x = n
    while x != -1 and len(out) < 4:
        out.append(x & 0xff)
        x >>= 8
    return bytes([(256 - len(out)) & 0xff]) + bytes(out)


class R:
    def __init__(self, data):
        self.d = data
        self.p = 0
        self.syms = []
        self.objs = []

    def b(self):
        c = self.d[self.p]
        self.p += 1
        return c

    def n(self, k):
        out = self.d[self.p:self.p + k]
        self.p += k
        return out

    def fix(self):
        c = self.b()
        if c == 0:
            return 0
        sc = c - 256 if c >= 128 else c
        if sc > 4:
            return sc - 5
        if sc < -4:
            return sc + 5
        nb = abs(sc)
        if sc > 0:
            v = 0
            for i in range(nb):
                v |= self.b() << (8 * i)
            return v
        v = -1
        for i in range(nb):
            v &= ~(0xff << (8 * i))
            v |= self.b() << (8 * i)
        return v

    def val(self):
        c = self.b()
        if c == 0x30: return None
        if c == 0x46: return False
        if c == 0x54: return True
        if c == 0x69: return self.fix()
        if c == 0x22:
            ln = self.fix()
            s = bytes(self.n(ln))
            self.objs.append(("STR", s))
            return ("STR", s)
        if c == 0x49:
            inner = self.val()
            ic = self.fix()
            ivars = []
            for _ in range(ic):
                k = self.val()
                v = self.val()
                ivars.append((k, v))
            return ("IVAR", inner, ivars)
        if c == 0x5b:
            ln = self.fix()
            arr = []
            self.objs.append(("ARR", arr))
            for _ in range(ln):
                arr.append(self.val())
            return ("ARR", arr)
        if c == 0x3a:
            ln = self.fix()
            s = bytes(self.n(ln))
            self.syms.append(s)
            return ("SYM", s)
        if c == 0x3b:
            i = self.fix()
            return ("SYM", self.syms[i])
        if c == 0x40:
            i = self.fix()
            return self.objs[i]
        raise NotImplementedError(f"type 0x{c:02x} at {self.p - 1}")


class W:
    def __init__(self):
        self.o = bytearray()
        self.sym_idx = {}
        self.objs = []

    def write(self, v):
        if v is None: self.o.append(0x30); return
        if v is False: self.o.append(0x46); return
        if v is True: self.o.append(0x54); return
        if isinstance(v, int):
            self.o.append(0x69); self.o += enc_fixnum(v); return
        if not isinstance(v, tuple):
            raise NotImplementedError(type(v))
        tag = v[0]
        if tag == "STR":
            s = v[1]
            self.o.append(0x22); self.o += enc_fixnum(len(s)); self.o += s
            self.objs.append(v)
            return
        if tag == "IVAR":
            self.o.append(0x49)
            self.write(v[1])
            self.o += enc_fixnum(len(v[2]))
            for k, val in v[2]:
                self.write(k); self.write(val)
            return
        if tag == "ARR":
            arr = v[1]
            self.o.append(0x5b); self.o += enc_fixnum(len(arr))
            self.objs.append(v)
            for item in arr:
                self.write(item)
            return
        if tag == "SYM":
            sym = v[1]
            if sym in self.sym_idx:
                self.o.append(0x3b); self.o += enc_fixnum(self.sym_idx[sym])
            else:
                self.sym_idx[sym] = len(self.sym_idx)
                self.o.append(0x3a); self.o += enc_fixnum(len(sym)); self.o += sym
            return
        raise NotImplementedError(tag)


def find_str(v):
    if isinstance(v, tuple):
        if v[0] == "STR":
            return v, lambda new: ("STR", new)
        if v[0] == "IVAR":
            inner, setter = find_str(v[1])
            if inner is None:
                return None, None
            ivars = v[2]
            return inner, lambda new: ("IVAR", setter(new), ivars)
    return None, None


def patch(path):
    with open(path, "rb") as f:
        raw = f.read()
    if raw[:2] != b"\x04\x08":
        sys.stderr.write("not Marshal v4.8\n"); return 1
    r = R(raw[2:])
    top = r.val()
    if not (isinstance(top, tuple) and top[0] == "ARR"):
        sys.stderr.write("top-level not Array\n"); return 1
    arr = top[1]
    patched = 0
    for entry in arr:
        if not (isinstance(entry, tuple) and entry[0] == "ARR"):
            continue
        items = entry[1]
        if len(items) < 3:
            continue
        s_val, setter = find_str(items[2])
        if s_val is None:
            continue
        try:
            src = zlib.decompress(s_val[1])
        except zlib.error:
            continue
        if b"USEKEYBOARD=true" not in src and b"USEKEYBOARD = true" not in src:
            continue
        new_src = src.replace(b"USEKEYBOARD=true", b"USEKEYBOARD=false")
        new_src = new_src.replace(b"USEKEYBOARD = true", b"USEKEYBOARD = false")
        items[2] = setter(zlib.compress(new_src, 6))
        patched += 1
    if patched == 0:
        sys.stderr.write("USEKEYBOARD=true not found; nothing to patch\n")
        return 0
    w = W()
    w.write(top)
    with open(path + ".bak", "wb") as f:
        f.write(raw)
    with open(path, "wb") as f:
        f.write(b"\x04\x08" + bytes(w.o))
    sys.stderr.write(f"patched {patched} section(s)\n")
    return 0


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "Data/Scripts.rxdata"
    sys.exit(patch(path))
