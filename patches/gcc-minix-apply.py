#!/usr/bin/env python3
"""Apply the gcc-13.3.0 i586-elf32-minix target edits to the extracted tree
in CWD. Each string replacement is anchor-checked exactly once."""

import os
import shutil
import sys

edits = []


def sub(path, old, new):
    edits.append((path, old, new))


# gcc/config.gcc: minix target entry (before the bare-elf entries)
sub("gcc/config.gcc",
    """i[34567]86-*-elfiamcu)
	tm_file="${tm_file} i386/unix.h i386/att.h elfos.h newlib-stdint.h i386/iamcu.h"
	;;
""",
    """i[34567]86-*-minix*)
	tm_file="${tm_file} i386/unix.h i386/att.h elfos.h i386/i386elf.h netbsd-stdint.h minix.h i386/minix.h"
	use_gcc_stdint=wrap
	extra_options="${extra_options} minix.opt"
	tmake_file="${tmake_file} t-slibgcc"
	;;
i[34567]86-*-elfiamcu)
	tm_file="${tm_file} i386/unix.h i386/att.h elfos.h newlib-stdint.h i386/iamcu.h"
	;;
""")

# libgcc/config.host: like bare elf, crtstuff + pic variants, plus a shared
# libgcc_s as on NetBSD: with threads, emutls must exist once per process
# (each DSO's static copy kept its own pthread key, so TLS shared between
# libraries - Mesa's current GL context - read back NULL).
sub("libgcc/config.host",
    """i[34567]86-*-elf*)
	tmake_file="$tmake_file i386/t-crtstuff t-crtstuff-pic t-libgcc-pic"
	;;
""",
    """i[34567]86-*-elf*)
	tmake_file="$tmake_file i386/t-crtstuff t-crtstuff-pic t-libgcc-pic"
	;;
i[34567]86-*-minix*)
	tmake_file="$tmake_file i386/t-crtstuff t-crtstuff-pic t-libgcc-pic"
	tmake_file="$tmake_file t-eh-dw2-dip"
	tmake_file="$tmake_file t-slibgcc t-slibgcc-gld t-slibgcc-elf-ver"
	tmake_file="$tmake_file t-slibgcc-libgcc"
	extra_parts="crtbegin.o crtend.o crtbeginS.o crtendS.o crtbeginT.o"
	;;
""")

# libstdc++-v3: MINIX's libc is NetBSD-derived; ride the netbsd cross-config
# answers instead of falling into the unknown-OS error.
sub("libstdc++-v3/crossconfig.m4",
    "  *-netbsd* | *-openbsd*)",
    "  *-netbsd* | *-openbsd* | *-minix*)")
sub("libstdc++-v3/configure",
    "  *-netbsd* | *-openbsd*)",
    "  *-netbsd* | *-openbsd* | *-minix*)")


# libgcc/gthr-posix.h (gthreads for libgcc's emutls/unwinder and libstdc++):
# MINIX's libmthread has no pthread_cancel, the default "are threads in
# use?" proxy symbol, so threads would never count as active.  Use
# pthread_create, as for bionic, and skip the weak pthread_cancel
# declaration (it needs a prototype).
sub("libgcc/gthr-posix.h",
    "#ifndef __BIONIC__\n__gthrw(pthread_cancel)",
    "#if !defined (__BIONIC__) && !defined (__minix)\n__gthrw(pthread_cancel)")
sub("libgcc/gthr-posix.h",
    "#elif defined (__BIONIC__)\n# define GTHR_ACTIVE_PROXY\t__gthrw_(pthread_create)",
    "#elif defined (__BIONIC__) || defined (__minix)\n# define GTHR_ACTIVE_PROXY\t__gthrw_(pthread_create)")

# libstdc++ --enable-libstdcxx-time=auto: MINIX has CLOCK_MONOTONIC/REALTIME,
# nanosleep and (with threads) sched_yield like NetBSD; without this,
# std::this_thread::yield() compiles to nothing, which starves MINIX's
# cooperative threads.
for f in ("libstdc++-v3/acinclude.m4", "libstdc++-v3/configure"):
    sub(f, "      freebsd*|netbsd*|dragonfly*|rtems*)",
        "      freebsd*|netbsd*|dragonfly*|rtems*|minix*)")

# libstdc++ OS configuration: os/minix = os/generic, except that gthreads
# use weak references (os/generic forces strong ones), so C++ programs
# link without -pthread and threads activate when libpthread (libmthread)
# is linked, as on NetBSD.
sub("libstdc++-v3/configure.host",
    "  netbsd*)\n    os_include_dir=\"os/bsd/netbsd\"\n    ;;\n",
    "  minix*)\n    os_include_dir=\"os/minix\"\n    ;;\n  netbsd*)\n    os_include_dir=\"os/bsd/netbsd\"\n    ;;\n")
copies = [("libstdc++-v3/config/os/generic/" + f, "libstdc++-v3/config/os/minix/" + f)
          for f in ("ctype_base.h", "ctype_configure_char.cc", "ctype_inline.h",
                    "error_constants.h")]

# gcc/ginclude/stddef.h: MINIX headers are NetBSD-derived and use the same
# _BSD_SIZE_T_ mechanism; gcc's stddef.h must play the same dance for us.
sub("gcc/ginclude/stddef.h",
    "#if defined(__NetBSD__)\n#if !defined(_SIZE_T_) && !defined(_BSD_SIZE_T_)",
    "#if defined(__NetBSD__) || defined(__minix)\n#if !defined(_SIZE_T_) && !defined(_BSD_SIZE_T_)")
# ...the lead-in include of machine/ansi.h, and the end-of-file cleanup
# block (three __NetBSD__ guards in all).
edits.append(("gcc/ginclude/stddef.h",
              "#if defined(__NetBSD__)\n#include <machine/ansi.h>",
              "#if defined(__NetBSD__) || defined(__minix)\n#include <machine/ansi.h>"))
edits.append(("gcc/ginclude/stddef.h",
              "#if defined(__NetBSD__)\n/*  The references",
              "#if defined(__NetBSD__) || defined(__minix)\n/*  The references"))

newfiles = {
    "libstdc++-v3/config/os/minix/os_defines.h": """\
// Specific definitions for MINIX  -*- C++ -*-

// Copyright (C) 2000-2023 Free Software Foundation, Inc.
//
// This file is part of the GNU ISO C++ Library.  This library is free
// software; you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the
// Free Software Foundation; either version 3, or (at your option)
// any later version.

// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// Under Section 7 of GPL version 3, you are granted additional
// permissions described in the GCC Runtime Library Exception, version
// 3.1, as published by the Free Software Foundation.

/** @file bits/os_defines.h
 *  This is an internal header file, included by other library headers.
 *  Do not attempt to use it directly. @headername{iosfwd}
 */

#ifndef _GLIBCXX_OS_DEFINES
#define _GLIBCXX_OS_DEFINES 1

// System-specific #define, typedefs, corrections, etc, go here.  This
// file will come before all others.

// Unlike os/generic, keep gthr.h's weak references (the default): MINIX
// threads are libmthread (libpthread); programs that do not link it run
// single-threaded, and those that do get working std::thread/mutex.

#endif
""",
    "gcc/config/minix.h": """\
/* Target definitions for MINIX.  */

#undef  TARGET_OS_CPP_BUILTINS
#define TARGET_OS_CPP_BUILTINS()		\\
  do {						\\
    builtin_define ("__minix=3");		\\
    builtin_define ("__minix__=3");		\\
    builtin_define ("__Minix__=3");		\\
    builtin_define_std ("unix");		\\
    builtin_assert ("system=minix");		\\
    builtin_assert ("system=unix");		\\
  } while (0)

/* Everyone links against libc.  -pthread: POSIX threads are libmthread,
   available as libpthread (see MINIX <pthread.h>).  It is linked even under
   --as-needed: libgcc's emutls refers to the pthread functions weakly, and
   weak references alone neither make the library needed nor may stay
   undefined under --no-undefined when a dependency provides them.  */
#undef  LIB_SPEC
#define LIB_SPEC \
  "%{pthread:--push-state --no-as-needed -lpthread --pop-state} -lc"

#undef  CPP_SPEC
#define CPP_SPEC "%{pthread:-D_REENTRANT}"
""",
    "gcc/config/minix.opt": """\
; MINIX options.

; See the GCC internals manual (options.texi) for a description of this
; file's format.

pthread
Driver
""",
    "gcc/config/i386/minix.h": """\
/* i386 MINIX target definitions: NetBSD-style crt startup files and the
   MINIX dynamic linker.  */

#undef  LINK_SPEC
#define LINK_SPEC "\
  -m elf_i386_minix \\
  %{!static:--eh-frame-hdr} \\
  %{shared:-Bshareable} \\
  %{!shared: \\
    %{!static:-dynamic-linker /usr/libexec/ld.elf_so} \\
    %{static:-Bstatic}}"

/* crt0.o/crti.o/crtn.o ship with MINIX (found in the sysroot); crtbegin/
   crtend come from this compiler.  */
#undef  STARTFILE_SPEC
#define STARTFILE_SPEC "\
  %{!shared:crt0%O%s} \\
  crti%O%s \\
  %{!shared:crtbegin%O%s} \\
  %{shared:crtbeginS%O%s}"

#undef  ENDFILE_SPEC
#define ENDFILE_SPEC "\
  %{!shared:crtend%O%s} \\
  %{shared:crtendS%O%s} \\
  crtn%O%s"
"""
}

newfiles["gcc/config/i386/minix.h"] += """\

/* Make gcc agree with <machine/ansi.h> (NetBSD-derived).  */

#undef  SIZE_TYPE
#define SIZE_TYPE "unsigned int"

#undef  PTRDIFF_TYPE
#define PTRDIFF_TYPE "int"
"""


def main():
    n = 0
    for path, old, new in edits:
        with open(path) as f:
            data = f.read()
        if data.count(old) != 1:
            print(f"FAIL: {path}: anchor found {data.count(old)}x")
            sys.exit(1)
        with open(path, "w") as f:
            f.write(data.replace(old, new))
        n += 1
    for src, dst in copies:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
        n += 1
    for path, content in newfiles.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
        n += 1
    print(f"applied {n} edits/new files")


if __name__ == "__main__":
    main()
