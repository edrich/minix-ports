#!/bin/sh
# test-toolchain.sh - Phase 1 gate: cross-compile C and C++ probes with the
# minix-ports toolchain and run them inside MINIX via the QEMU harness.
#
# Covers: dynamic linking (ld.elf_so), static linking, static constructors
# (.init_array), exceptions (EH frame registration), iostream, STL, and
# C++ threads (gthreads over libmthread: tests/threads.cpp).
#
# Usage: test-toolchain.sh
# Requires: build-toolchain.sh already run, and the MINIX image built with
# the i386 HAVE_INITFINI_ARRAY csu/rtld (repo branch hyprland-support).

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
TC="$HERE/tc/bin/i586-elf32-minix"
WORK=$(mktemp -d /tmp/tc-gate-XXXXXX)
trap 'rm -rf "$WORK"' EXIT

CC="$TC-gcc"
CXX="$TC-g++"
CFLAGS="-O2 -Wl,-z,noexecstack"
# -z noexecstack: MINIX crt0.o lacks a .note.GNU-stack section (harmless
# warning otherwise).

mkdir -p "$WORK/payload/bin"

$CC $CFLAGS        -o "$WORK/payload/bin/hello-c"        "$HERE/tests/hello.c"
$CC $CFLAGS -static -o "$WORK/payload/bin/hello-c-static" "$HERE/tests/hello.c"
# libstdc++/libgcc are static on purpose: they are not installed in the
# guest image. libc stays dynamic so the ld.elf_so path is also exercised.
$CXX $CFLAGS -std=c++17 -o "$WORK/payload/bin/hello-cpp" "$HERE/tests/hello.cpp" \
    -static-libstdc++ -static-libgcc

# C++20 threads: -pthread links libpthread (= libmthread).
$CXX $CFLAGS -std=c++20 -pthread -o "$WORK/payload/bin/threads-cpp" \
    "$HERE/tests/threads.cpp" -static-libstdc++ -static-libgcc

"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
    --payload "$WORK/payload" \
    --cmd '/mnt/bin/hello-c' \
    --cmd '/mnt/bin/hello-c-static' \
    --cmd '/mnt/bin/hello-cpp' \
    --cmd '/mnt/bin/threads-cpp' \
    --expect 'TC-C-OK 42' \
    --expect 'TC-CPP-OK 12345 eh-works' \
    --expect 'TC-CPP17-OK' \
    --expect 'TC-THREADS-OK 200 55' \
    --expect 'HARNESS:DONE:0' \
    --log "$HERE/tests/last-gate.log"
