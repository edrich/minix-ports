#!/usr/bin/env python3
"""sprof-report.py <sprof.PID file>... - resolve tests/sprof.c samples.

Each PC is attributed to the loaded object with the highest base <= PC
(the main program is linked at its final addresses, base 0) and resolved
with addr2line against the unstripped copy: the ports tree
(rootfs/usr/pkg) or the OS destdir.  Prints per-object and per-function
shares of the samples."""
import collections
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PORTS = os.path.dirname(HERE)
ROOTFS = os.path.join(PORTS, 'rootfs')
DESTDIR = os.path.join(PORTS, '..', 'obj.docker.i386', 'destdir.i386')
A2L = os.path.join(PORTS, 'tc', 'bin', 'i586-elf32-minix-addr2line')
SEARCH = ['usr/pkg/lib', 'usr/pkg/lib/dri', 'usr/pkg/bin', 'usr/pkg/libexec',
          'usr/lib', 'usr/libexec', 'lib', 'bin', 'usr/bin']


def host_path(name, main):
    if name == '(main)':
        name = main
    cands = []
    if name.startswith('/'):
        cands += [ROOTFS + name, DESTDIR + name]
    else:
        for d in SEARCH:
            cands += [os.path.join(ROOTFS, d, name), os.path.join(DESTDIR, d, name)]
    for c in cands:
        if os.path.isfile(c):
            return c
    return soname_index().get(os.path.basename(name))


_SONAMES = None


def soname_index():
    """SONAME -> file, for objects reported by SONAME (Mesa's megadriver is
    libgallium_dri.so inside dri/swrast_dri.so)."""
    global _SONAMES
    if _SONAMES is None:
        _SONAMES = {}
        re_ = os.path.join(PORTS, 'tc', 'bin', 'i586-elf32-minix-readelf')
        for top in (ROOTFS, DESTDIR):
            for d in SEARCH:
                full = os.path.join(top, d)
                if not os.path.isdir(full):
                    continue
                for f in os.listdir(full):
                    fp = os.path.join(full, f)
                    if '.so' not in f or not os.path.isfile(fp) or os.path.islink(fp):
                        continue
                    out = subprocess.run([re_, '-d', fp], capture_output=True,
                                         text=True).stdout
                    for line in out.split('\n'):
                        if '(SONAME)' in line and '[' in line:
                            _SONAMES.setdefault(line.split('[')[1].rstrip(']'), fp)
    return _SONAMES


def report(path, main, top):
    objs, pcs, total = [], collections.Counter(), 0
    for line in open(path):
        f = line.split()
        if len(f) >= 4 and f[1] == 'obj':
            objs.append((int(f[2], 16), f[3]))
        elif len(f) >= 4 and f[1] == 'pc':
            pcs[int(f[2], 16)] += int(f[3])
        elif len(f) >= 3 and f[1] == 'total':
            total = int(f[2])
    objs.sort()
    by_obj = collections.defaultdict(list)
    for pc, n in pcs.items():
        owner = None
        for base, name in objs:
            if base <= pc:
                owner = (base, name)
        if owner is None:
            owner = (0, '?')
        by_obj[owner].append((pc, n))
    funcs = collections.Counter()
    objtot = collections.Counter()
    for (base, name), lst in by_obj.items():
        short = os.path.basename(main if name == '(main)' else name)
        objtot[short] += sum(n for _, n in lst)
        hp = host_path(name, main)
        if hp is None:
            for _, n in lst:
                funcs[(short, '??')] += n
            continue
        addrs = ['%#x' % (pc - base) for pc, _ in lst]
        out = subprocess.run([A2L, '-f', '-C', '-e', hp] + addrs,
                             capture_output=True, text=True).stdout.split('\n')
        for i, (_, n) in enumerate(lst):
            fn = out[2 * i] if 2 * i < len(out) else '??'
            funcs[(short, fn)] += n
    total = total or sum(pcs.values())
    print('== %s (%d samples, main %s)' % (os.path.basename(path), total, main))
    for o, n in objtot.most_common(12):
        print('  %5.1f%%  %s' % (100.0 * n / total, o))
    print('  -- functions')
    for (o, fn), n in funcs.most_common(top):
        print('  %5.1f%%  %-22s %s' % (100.0 * n / total, o, fn[:90]))


if __name__ == '__main__':
    args = sys.argv[1:]
    top = 30
    if args and args[0].startswith('--top='):
        top = int(args[0][6:]); args = args[1:]
    for p in args:
        main = '?'
        for line in open(p):
            if line.startswith('SPROF main '):
                main = line.split()[2]
        report(p, main, top)
