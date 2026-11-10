#!/bin/sh
# build-toolchain.sh - build the out-of-tree i586-elf32-minix cross toolchain
# (binutils + gcc 13) used for the wayland/wlroots/Hyprland ports.
#
# The in-tree toolchain (clang 3.6 / gcc 4.8) cannot build modern C++23 code,
# so the ports are compiled with this toolchain instead. It is a plain
# cross compiler against the MINIX sysroot produced by the normal OS build:
#
#   sysroot: ../obj.i386/destdir.i386        (must exist: build the OS first)
#   prefix:  <here>/tc
#
# Usage:
#   build-toolchain.sh            # build everything that isn't built yet
#   build-toolchain.sh binutils   # only binutils
#   build-toolchain.sh gcc        # only gcc (requires binutils installed)
#   build-toolchain.sh clean      # remove build dirs (keeps downloads & tc/)
#
# Re-running is cheap: extracted trees and build steps are skipped when their
# stamp/marker files exist. Patches are (re)applied only to a fresh extract.

set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/src"
BUILD="$HERE/build"
TC="$HERE/tc"
PATCHES="$HERE/patches"

TARGET=i586-elf32-minix
# Sysroot: the Docker-built destdir is canonical (the container cannot run
# host-built binaries, so the host objdir is being retired). Override with
# MINIX_SYSROOT if needed.
SYSDEF="$HERE/../obj.docker.i386/destdir.i386"
[ -d "$SYSDEF" ] || SYSDEF="$HERE/../obj.i386/destdir.i386"
SYSROOT=$(cd "${MINIX_SYSROOT:-$SYSDEF}" && pwd)
JOBS=$(nproc 2>/dev/null || echo 4)

BINUTILS_VER=2.43.1
GCC_VER=13.3.0

log() { echo "==> $*"; }
die() { echo "build-toolchain: ERROR: $*" >&2; exit 1; }

[ -d "$SYSROOT/usr/include" ] || die "sysroot $SYSROOT not found - build MINIX first"
[ -f "$SYSROOT/usr/lib/crt0.o" ] || die "sysroot lacks crt0.o - incomplete destdir?"

prep() {
    # prep <name-version> <tarball> <patch>
    name="$1"; tarb="$2"; patch="$3"
    if [ ! -d "$SRC/$name" ]; then
        log "extracting $name"
        tar -C "$SRC" -xf "$SRC/$tarb"
        if [ -n "$patch" ]; then
            log "applying $(basename "$patch")"
            (cd "$SRC/$name" && patch -s -p1 --no-backup-if-mismatch < "$patch") \
                || die "patch failed for $name"
        fi
    fi
}

build_binutils() {
    prep "binutils-$BINUTILS_VER" "binutils-$BINUTILS_VER.tar.xz" \
        "$PATCHES/binutils-$BINUTILS_VER-minix.patch"
    b="$BUILD/binutils"
    mkdir -p "$b"
    if [ ! -f "$b/.configured" ]; then
        log "configuring binutils"
        # --without-zstd: only used for debug-section compression, and its
        #   presence/absence differs between hosts/containers.
        # ac_cv_tls=_Thread_local: pin the TLS keyword probe (host compilers
        #   with a C23 default (gcc 15+) otherwise pick "thread_local", which
        #   older C compilers then choke on (and vice versa).
        (cd "$b" && ac_cv_tls=_Thread_local "$SRC/binutils-$BINUTILS_VER/configure" \
            --target="$TARGET" --prefix="$TC" \
            --with-sysroot="$SYSROOT" \
            --disable-nls --disable-gold --disable-werror \
            --without-zstd \
            --enable-deterministic-archives \
            > "$b/configure.log" 2>&1) || die "binutils configure failed (see $b/configure.log)"
        touch "$b/.configured"
    fi
    log "building binutils ($JOBS jobs, log: $b/build.log)"
    (cd "$b" && make -j"$JOBS" > build.log 2>&1) \
        || die "binutils build failed (see $b/build.log)"
    log "installing binutils"
    (cd "$b" && make install >> build.log 2>&1) || die "binutils install failed"
}

build_gcc() {
    prep "gcc-$GCC_VER" "gcc-$GCC_VER.tar.xz" \
        "$PATCHES/gcc-$GCC_VER-minix.patch"
    b="$BUILD/gcc"
    mkdir -p "$b"
    if [ ! -f "$b/.configured" ]; then
        log "configuring gcc"
        # --enable-__cxa_atexit (as for NetBSD): C++ static destructors
        # are registered per DSO and crtbeginS.o calls
        # __cxa_finalize(__dso_handle) when a shared object is unloaded;
        # without it, dlclose()d objects (Mesa DRI drivers) left exit
        # handlers pointing into unmapped memory.
        # --enable-shared: libgcc_s.so.1 (one emutls + unwinder per
        # process; installed into rootfs/usr/pkg/lib for the guest).
        # libstdc++ stays static in practice (ports link -static-libstdc++).
        # --enable-threads=posix: gthreads over MINIX <pthread.h>
        # (libmthread, cooperative user-level threads), so libstdc++ has
        # std::thread/mutex/condition_variable and emutls keeps one value
        # per thread.  Threads count as active when pthread_create is
        # linked (gthr-posix.h patch).  TLS stays emulated (--disable-tls).
        # Host gcc >= 15 defaults to a C++ std where u8"" is char8_t and
        # 'register' is an error; gcc-13-era host code (notably libcody)
        # needs the C++17 dialect.
        (cd "$b" && CXX="g++ -std=c++17" "$SRC/gcc-$GCC_VER/configure" \
            --target="$TARGET" --prefix="$TC" \
            --with-sysroot="$SYSROOT" \
            --with-native-system-header-dir=/usr/include \
            --enable-languages=c,c++ \
            --disable-multilib --disable-nls \
            --enable-threads=posix --disable-tls \
            --enable-shared \
            --disable-libssp --disable-libgomp --disable-libvtv \
            --disable-libquadmath --disable-libmpx --disable-lto \
            --disable-fixincludes \
            --enable-initfini-array \
            --enable-__cxa_atexit \
            --with-gnu-as --with-gnu-ld \
            --with-as="$TC/bin/$TARGET-as" --with-ld="$TC/bin/$TARGET-ld" \
            > "$b/configure.log" 2>&1) || die "gcc configure failed (see $b/configure.log)"
        touch "$b/.configured"
    fi
    log "building gcc (compiler + libgcc) ($JOBS jobs, log: $b/build.log)"
    (cd "$b" && make -j"$JOBS" all-gcc all-target-libgcc >> build.log 2>&1) \
        || die "gcc/libgcc build failed (see $b/build.log)"
    log "building gcc (libstdc++ and the rest)"
    (cd "$b" && make -j"$JOBS" all >> build.log 2>&1) \
        || die "gcc build failed (see $b/build.log)"
    log "installing gcc"
    (cd "$b" && make install >> build.log 2>&1) || die "gcc install failed"
    # The guest has no libgcc_s: ship it with the ports (/usr/pkg/lib).
    mkdir -p "$HERE/rootfs/usr/pkg/lib"
    cp -P "$TC/$TARGET"/lib/libgcc_s.so* "$HERE/rootfs/usr/pkg/lib/" \
        || die "libgcc_s.so not built"
}

case "${1:-all}" in
    all)       build_binutils; build_gcc ;;
    binutils)  build_binutils ;;
    gcc)       build_gcc ;;
    clean)     rm -rf "$BUILD"/binutils "$BUILD"/gcc ;;
    *)         die "unknown target: $1" ;;
esac
log "done"
