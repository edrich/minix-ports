#!/usr/bin/env python3
"""checkweston-gl.py <screendump.ppm> - verify the Weston GL-renderer
screendump (test-weston-gl.sh): 1024x768, the desktop background colour
0x1f4f6f from the gate's weston.ini (composited by gl-renderer), a dark
panel at the top, and the weston-simple-egl window: a block of strongly
saturated pixels (its red/green/blue interpolated triangle).  simple-egl
spins the triangle about the Y axis, so its area on screen swings from
~1950 samples down to nearly nothing when edge-on: require a modest count
plus red-, green- and blue-dominant pixels (all three vertex colours)."""
import sys

def load(path):
    d = open(path, 'rb').read()
    magic, dims, maxv, px = d.split(b'\n', 3)
    if magic != b'P6':
        sys.exit('not a P6 PPM')
    w, h = map(int, dims.split())
    return w, h, px

def near(a, b, tol=12):
    return all(abs(x - y) <= tol for x, y in zip(a, b))

BG = (0x1f, 0x4f, 0x6f)
w, h, px = load(sys.argv[1])
at = lambda x, y: tuple(px[(y * w + x) * 3:(y * w + x) * 3 + 3])
checks = [('size 1024x768', (w, h) == (1024, 768))]
if (w, h) == (1024, 768):
    tri = 0
    dominant = set()
    for y in range(40, h, 2):
        for x in range(0, w, 2):
            p = at(x, y)
            if max(p) - min(p) > 110 and not near(p, BG, 20):
                tri += 1
                dominant.add(p.index(max(p)))
    print('saturated (triangle) samples: %d, dominant channels %s' %
          (tri, ''.join('RGB'[c] for c in sorted(dominant))))
    checks += [
        ('background bottom-right', near(at(1000, 740), BG)),
        ('background left', near(at(20, 600), BG)),
        ('panel (dark)', sum(at(500, 10)) < 120),
        ('simple-egl triangle drawn', tri > 100 and len(dominant) == 3),
    ]
ok = True
for name, good in checks:
    print(('ok   ' if good else 'FAIL ') + name)
    ok = ok and good
print('WESTON-GL-SCREEN OK' if ok else 'WESTON-GL-SCREEN BAD')
sys.exit(0 if ok else 1)
