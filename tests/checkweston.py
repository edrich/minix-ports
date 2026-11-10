#!/usr/bin/env python3
"""checkweston.py <screendump.ppm> - verify a Weston desktop screendump
(test-weston.sh): 1024x768 (not VGA text mode), background colour
0x1f4f6f from the gate's weston.ini, a dark panel at the top, and the
weston-terminal window (white title bar, black text area) in the middle."""
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

w, h, px = load(sys.argv[1])
at = lambda x, y: tuple(px[(y * w + x) * 3:(y * w + x) * 3 + 3])
checks = [
    ('size 1024x768', (w, h) == (1024, 768)),
]
if (w, h) == (1024, 768):
    checks += [
        ('background bottom-right', near(at(900, 700), (0x1f, 0x4f, 0x6f))),
        ('background left', near(at(50, 600), (0x1f, 0x4f, 0x6f))),
        ('panel (dark)', sum(at(500, 10)) < 120),
        ('terminal title bar', near(at(300, 260), (255, 255, 255), 30)),
        ('terminal text area', near(at(560, 500), (0, 0, 0))),
    ]
ok = True
for name, good in checks:
    print(('ok   ' if good else 'FAIL ') + name)
    ok = ok and good
print('WESTON-SCREEN OK' if ok else 'WESTON-SCREEN BAD')
sys.exit(0 if ok else 1)
