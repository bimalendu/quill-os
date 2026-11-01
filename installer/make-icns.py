#!/usr/bin/env python3
"""Write an ICNS file from PNG renders: make-icns.py OUT.icns 128.png 256.png 512.png 1024.png

Each PNG goes in as one PNG-compressed icon entry (ic07 128, ic08 256, ic09 512,
ic10 1024), which is all the Asahi boot picker needs. Standard library only."""
import struct
import sys

TYPES = {128: b"ic07", 256: b"ic08", 512: b"ic09", 1024: b"ic10"}


def png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("not a PNG")
    w, h = struct.unpack(">II", data[16:24])
    if w != h:
        raise SystemExit("icon is not square: %dx%d" % (w, h))
    return w


def main(argv):
    if len(argv) < 3:
        raise SystemExit(__doc__)
    out, pngs = argv[1], argv[2:]
    body = b""
    for path in pngs:
        data = open(path, "rb").read()
        size = png_size(data)
        if size not in TYPES:
            raise SystemExit("%s: size %d has no ICNS type" % (path, size))
        body += TYPES[size] + struct.pack(">I", 8 + len(data)) + data
    with open(out, "wb") as f:
        f.write(b"icns" + struct.pack(">I", 8 + len(body)) + body)


main(sys.argv)
