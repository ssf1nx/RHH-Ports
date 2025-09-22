#!/usr/bin/env python3

import sys
import zlib
import os

def crc32_file(path: str) -> str:
    """Return the CRC32 of a file as 8-digit uppercase hex."""
    with open(path, 'rb') as f:
        buf = f.read()
    return f"{zlib.crc32(buf) & 0xFFFFFFFF:08X}"

def main():
    if len(sys.argv) < 2:
        print("Usage: crc32sum.py <file> [file ...]", file=sys.stderr)
        sys.exit(1)

    for path in sys.argv[1:]:
        if not os.path.isfile(path):
            print(f"{path}: not a regular file", file=sys.stderr)
            continue
        try:
            print(f"{crc32_file(path)}  {path}")
        except Exception as e:
            print(f"{path}: error ({e})", file=sys.stderr)

if __name__ == "__main__":
    main()
