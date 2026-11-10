#!/usr/bin/env python3
"""psdiff.py <log> [secs] - per-process CPU over the PSDUMP1/PSDUMP2 window
of tests/perf/hypr-fps.sh (PSDUMP=1): TIME delta of each process (servers
included) as a share of the wall-clock window (default 20 s)."""
import re
import sys


def parse_time(t):
    m = re.match(r'(?:(\d+):)?(\d+)\.(\d+)$', t)
    return int(m.group(1) or 0) * 60 + int(m.group(2)) + int(m.group(3)) / 100.0


def main():
    log, secs = sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 20.0
    dumps, cur = {}, None
    for line in open(log, errors='replace'):
        line = line.rstrip('\r\n')
        m = re.match(r'(PSDUMP[12]) (\S+)$', line)
        if m:
            cur = (m.group(2), m.group(1)); dumps[cur] = {}; continue
        if line.startswith('PSDUMPEND'):
            cur = None; continue
        if cur and not line.startswith('UID'):
            f = line.split(None, 12)
            if len(f) >= 13:
                dumps[cur][f[1]] = (parse_time(f[11]), f[12][:28])
    for label in dict.fromkeys(k[0] for k in dumps):
        a, b = dumps.get((label, 'PSDUMP1'), {}), dumps.get((label, 'PSDUMP2'), {})
        rows = []
        for pid, (t2, cmd) in b.items():
            d = t2 - a.get(pid, (0.0, ''))[0]
            if d > 0:
                rows.append((d, pid, cmd))
        rows.sort(reverse=True)
        tot = sum(r[0] for r in rows)
        print('== %s: %.1f s CPU in %.0f s window (%.0f%%)' % (label, tot, secs, 100 * tot / secs))
        for d, pid, cmd in rows[:12]:
            print('  %5.1f%%  %6.2fs  %5s %s' % (100 * d / secs, d, pid, cmd))


main()
