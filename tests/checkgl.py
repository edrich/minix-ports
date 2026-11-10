#!/usr/bin/env python3
"""checkgl.py <screendump.ppm> - Phase 7 gate: the screen shows egl-gate's
last GBM frame, a red triangle (upright) on a blue background."""
import sys

d = open(sys.argv[1], 'rb').read()
parts = d.split(b'\n', 3)
w, h = map(int, parts[1].split())
px = parts[3]


def at(x, y):
    i = (y * w + x) * 3
    return tuple(px[i:i + 3])


ok = True
# NDC -> pixel: x = (n + 1) / 2 * w, y = (1 - n) / 2 * h
checks = [
    ("center", w // 2, h // 2, (255, 0, 0)),
    ("near apex", w // 2, int((1 - 0.5) / 2 * h), (255, 0, 0)),
    ("left of base", int((1 - 0.45) / 2 * w), int((1 + 0.45) / 2 * h), (255, 0, 0)),
    ("top-left", 5, 5, (0, 0, 255)),
    ("bottom-right", w - 5, h - 5, (0, 0, 255)),
    ("beside apex", int((1 + 0.3) / 2 * w), int((1 - 0.5) / 2 * h), (0, 0, 255)),
]
for name, x, y, want in checks:
    got = at(x, y)
    good = all(abs(a - b) <= 8 for a, b in zip(got, want))
    print("  %-13s (%d,%d) = %s %s" % (name, x, y, got, "ok" if good else "WANT %s" % (want,)))
    ok = ok and good
print("GL-SCREEN OK" if ok else "GL-SCREEN FAIL")
sys.exit(0 if ok else 1)
