#!/usr/bin/env python3
"""checkblit.py <log> <dir> <label>... - verify Hyprland screendumps of
tests/shm-pattern.c (tests/perf/hypr-shot.sh, test-blit.sh): inside the
window rectangle (SHOTWIN lines in the log) every pixel must match the
pattern (red = 255x/(w-1), green = 255y/(h-1), blue = checker, tolerance
2; the software cursor's box at the screen centre is skipped), and labels
"<x>" and "<x>_nb" (blit disabled) must give the same picture."""
import os
import re
import sys

TOL = 2


def load(path):
    d = open(path, 'rb').read()
    magic, dims, maxv, px = d.split(b'\n', 3)
    if magic != b'P6':
        sys.exit('%s: not a P6 PPM' % path)
    w, h = map(int, dims.split())
    return w, h, px


def check_pattern(path, win):
    x0, y0, w, h = win
    sw, sh, px = load(path)
    bad, worst = 0, None
    # wlroots' software cursor sits at the screen centre (hotspot top-left)
    cur = (sw // 2 - 4, sh // 2 - 4, sw // 2 + 32, sh // 2 + 32)
    for y in range(h):
        for x in range(w):
            if cur[0] <= x0 + x < cur[2] and cur[1] <= y0 + y < cur[3]:
                continue
            o = ((y0 + y) * sw + x0 + x) * 3
            got = px[o:o + 3]
            exp = (255 * x // max(w - 1, 1), 255 * y // max(h - 1, 1),
                   0 if (x // 32 + y // 32) & 1 else 255)
            if any(abs(g - e) > TOL for g, e in zip(got, exp)):
                bad += 1
                if worst is None:
                    worst = (x, y, tuple(got), exp)
    return bad, worst


def main():
    log, d, labels = sys.argv[1], sys.argv[2], sys.argv[3:]
    wins, used = {}, {}
    for line in open(log, errors='replace'):
        m = re.match(r'SHOTWIN (\S+) (-?\d+) (-?\d+) (\d+) (\d+)\s*$', line)
        if m:
            wins[m.group(1)] = tuple(int(v) for v in m.group(2, 3, 4, 5))
        m = re.match(r'BLITUSED (\S+) ([01])\s*$', line)
        if m:
            used[m.group(1)] = m.group(2) == '1'
    ok = True
    # The fast path must run for opaque windows - and only for them
    # ("argb" is translucent, "_nb" runs have it disabled).
    for L in labels:
        want = not (L.endswith('_nb') or L == 'argb')
        good = used.get(L) == want
        print('%s %s: blit path %s (want %s)' % ('ok  ' if good else 'FAIL', L,
              {True: 'used', False: 'unused', None: '?'}[used.get(L)],
              'used' if want else 'unused'))
        ok = ok and good
    for L in labels:
        path = os.path.join(d, L + '.ppm')
        if L not in wins or not os.path.exists(path):
            print('FAIL %s: no window geometry or screendump' % L)
            ok = False
            continue
        bad, worst = check_pattern(path, wins[L])
        print('%s %s: window %s, %d pixels off the pattern%s' % (
            'ok  ' if bad == 0 else 'FAIL', L, wins[L], bad,
            '' if worst is None else ' (first at %s: got %s want %s)' % (
                worst[:2], worst[2], worst[3])))
        ok = ok and bad == 0
    for L in labels:
        if L + '_nb' in labels:
            a = load(os.path.join(d, L + '.ppm'))
            b = load(os.path.join(d, L + '_nb.ppm'))
            diff = sum(1 for i in range(0, len(a[2]), 3)
                       if any(abs(a[2][i + k] - b[2][i + k]) > TOL for k in range(3)))
            print('%s %s vs %s_nb: %d pixels differ' % (
                'ok  ' if diff == 0 else 'FAIL', L, L, diff))
            ok = ok and diff == 0
    print('CHECKBLIT OK' if ok else 'CHECKBLIT BAD')
    sys.exit(0 if ok else 1)


main()
