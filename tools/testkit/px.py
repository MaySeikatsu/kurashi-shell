"""The suites' PPM reader (W89): the P6 frame `grim -t ppm` writes, for the pixel checks. Stdlib only.

  read_ppm(path) -> (w, h, pixels)     pixels: the raw RGB raster, row by row, 3 bytes a pixel
  parse_ppm(data) -> (w, h, pixels)    the same from bytes already read
  pixel(w, pixels, x, y) -> (r, g, b)
  near(colour, ref, tol) -> bool       every channel within tol of ref

The suites run python3 -I, which ignores PYTHONPATH, so an analysis script puts the kit on sys.path itself:
    sys.path.insert(0, os.environ["KIT"])     # frontend/test-lib.sh exports KIT
    from px import read_ppm
"""


def parse_ppm(data):
    # Four whitespace-separated fields (magic, width, height, maxval), one whitespace byte, the raster.
    fields, i = [], 0
    while len(fields) < 4:
        while data[i:i + 1].isspace():
            i += 1
        j = i
        while j < len(data) and not data[j:j + 1].isspace():
            j += 1
        fields.append(data[i:j])
        i = j
    if fields[0] != b"P6" or fields[3] != b"255":
        raise SystemExit(f"not an 8-bit P6 image: {fields}")
    return int(fields[1]), int(fields[2]), data[i + 1:]


def read_ppm(path):
    with open(path, "rb") as f:
        return parse_ppm(f.read())


def pixel(w, pixels, x, y):
    o = (y * w + x) * 3
    return pixels[o], pixels[o + 1], pixels[o + 2]


def near(colour, ref, tol):
    return all(abs(colour[k] - ref[k]) <= tol for k in range(3))
