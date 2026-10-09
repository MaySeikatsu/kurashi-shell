#!/usr/bin/env python3
"""Writes the picker test library (mods/wallpaper/test/real-shell.sh): decodable PNGs with known colours.

    make-pictures.py <folder>

Pictures: a teal, a red and a blue-green one (colourful, each with its own hue), a grey gradient (monochrome: the
theme falls back), a light/dark pair (wall-light / wall-dark), a sunset in a subfolder, and one file that is not a
picture. Stdlib only (zlib + struct), so the test needs no image tools.
"""
import pathlib
import struct
import sys
import zlib

W, H = 320, 180


def write_png(path, px):
    rows = bytearray()
    for y in range(H):
        rows.append(0)  # filter: none
        for x in range(W):
            rows.extend(px(x, y))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)  # 8-bit RGB
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(bytes(rows), 6)) + chunk(b"IEND", b""))
    path.write_bytes(data)


def main(folder):
    root = pathlib.Path(folder)
    (root / "sub").mkdir(parents=True, exist_ok=True)
    write_png(root / "01-teal.png", lambda x, y: (20 + x * 40 // W, 120 + y * 60 // H, 130))
    write_png(root / "02-red.png", lambda x, y: (200 - y * 60 // H, 40 + x * 40 // W, 40))
    write_png(root / "03-blue.png", lambda x, y: (40, 80 + x * 100 // W, 200 - y * 80 // H))
    write_png(root / "04-grey.png", lambda x, y: (x * 255 // (W - 1),) * 3)
    write_png(root / "05-wall-dark.png", lambda x, y: (30 + x // 10, 40 + y // 8, 70))
    write_png(root / "06-wall-light.png", lambda x, y: (220, 230 - x // 10, 240))
    write_png(root / "sub" / "07-sunset.png", lambda x, y: (230 - y * 100 // H, 120 + x * 50 // W, 60))
    (root / "zz-broken.png").write_bytes(b"this is not a picture")


if __name__ == "__main__":
    main(sys.argv[1])
