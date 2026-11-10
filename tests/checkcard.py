#!/usr/bin/env python3
"""Check a QEMU screendump (PPM P6) for the test97 test card:
800x600, quadrants red / green (top), blue / white (bottom)."""
import sys


def read_ppm(path):
    data = open(path, "rb").read()
    fields, pos = [], 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            while data[pos:pos + 1] != b"\n":
                pos += 1
            continue
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos])
    pos += 1
    magic, w, h, maxval = fields[0], int(fields[1]), int(fields[2]), int(fields[3])
    assert magic == b"P6" and maxval == 255, (magic, maxval)
    return w, h, data[pos:pos + w * h * 3]


def main():
    w, h, px = read_ppm(sys.argv[1])
    print(f"screendump {w}x{h}")
    if (w, h) != (800, 600):
        print("FAIL: unexpected size")
        return 1
    want = {
        (200, 150): (255, 0, 0), (600, 150): (0, 255, 0),
        (200, 450): (0, 0, 255), (600, 450): (255, 255, 255),
        (5, 5): (255, 0, 0), (795, 595): (255, 255, 255),
    }
    bad = 0
    for (x, y), rgb in want.items():
        i = (y * w + x) * 3
        got = tuple(px[i:i + 3])
        ok = got == rgb
        bad += not ok
        print(f"  ({x},{y}) = {got} {'ok' if ok else 'WANT ' + str(rgb)}")
    print("CARD OK" if not bad else "CARD FAIL")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
