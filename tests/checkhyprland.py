#!/usr/bin/env python3
"""checkhyprland.py <screendump.ppm> - verify the Hyprland screendump
(test-hyprland.sh): 1024x768; weston-simple-egl tiled as the only window,
so the active border colour (0xffcc00 from the gate's config) runs along
the window edges inside the outer gaps; and the client's triangle shows
(saturated pixels, red-, green- and blue-dominant ones)."""
import sys

def load(path):
    d = open(path, 'rb').read()
    magic, dims, maxv, px = d.split(b'\n', 3)
    if magic != b'P6':
        sys.exit('not a P6 PPM')
    w, h = map(int, dims.split())
    return w, h, px

def near(a, b, tol=40):
    return all(abs(x - y) <= tol for x, y in zip(a, b))

BORDER = (0xff, 0xcc, 0x00)
w, h, px = load(sys.argv[1])
at = lambda x, y: tuple(px[(y * w + x) * 3:(y * w + x) * 3 + 3])
checks = [('size 1024x768', (w, h) == (1024, 768))]
if (w, h) == (1024, 768):
    border = sum(1 for x in range(0, w, 4) for y in range(0, 24)
                 if near(at(x, y), BORDER))
    border += sum(1 for y in range(0, h, 4) for x in range(0, 24)
                  if near(at(x, y), BORDER))
    tri, dominant = 0, set()
    for y in range(24, h - 24, 2):
        for x in range(24, w - 24, 2):
            p = at(x, y)
            if max(p) - min(p) > 110 and not near(p, BORDER):
                tri += 1
                dominant.add(p.index(max(p)))
    print('border samples: %d, saturated samples: %d, dominant %s' %
          (border, tri, ''.join('RGB'[c] for c in sorted(dominant))))
    checks += [
        ('active border drawn', border > 100),
        ('client triangle drawn', tri > 100 and len(dominant) == 3),
    ]
ok = True
for name, good in checks:
    print(('ok   ' if good else 'FAIL ') + name)
    ok = ok and good
print('HYPRLAND-SCREEN OK' if ok else 'HYPRLAND-SCREEN BAD')
sys.exit(0 if ok else 1)
