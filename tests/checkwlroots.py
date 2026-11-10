#!/usr/bin/env python3
"""checkwlroots.py <screendump.ppm> - verify the tinywl screendump
(test-wlroots.sh): 1024x768, the empty scene is black, and the
weston-simple-egl toplevel shows its spinning triangle: saturated pixels
with red-, green- and blue-dominant ones (all three vertex colours)."""
import sys

def load(path):
    d = open(path, 'rb').read()
    magic, dims, maxv, px = d.split(b'\n', 3)
    if magic != b'P6':
        sys.exit('not a P6 PPM')
    w, h = map(int, dims.split())
    return w, h, px

w, h, px = load(sys.argv[1])
at = lambda x, y: tuple(px[(y * w + x) * 3:(y * w + x) * 3 + 3])
checks = [('size 1024x768', (w, h) == (1024, 768))]
if (w, h) == (1024, 768):
    tri, dominant = 0, set()
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            p = at(x, y)
            if max(p) - min(p) > 110:
                tri += 1
                dominant.add(p.index(max(p)))
    print('saturated samples: %d, dominant channels %s' %
          (tri, ''.join('RGB'[c] for c in sorted(dominant))))
    checks += [
        ('background black (bottom-right)', sum(at(1000, 740)) < 30),
        ('triangle drawn', tri > 100 and len(dominant) == 3),
    ]
ok = True
for name, good in checks:
    print(('ok   ' if good else 'FAIL ') + name)
    ok = ok and good
print('WLROOTS-SCREEN OK' if ok else 'WLROOTS-SCREEN BAD')
sys.exit(0 if ok else 1)
