#!/bin/sh
# test-wayland.sh - Phase 4 gate: tests/wl-gate.c (wayland server + client,
# shm buffer painted with pixman, xkbcommon keymap) inside MINIX, against the
# ports in rootfs/usr/pkg (installed into the guest's /usr/pkg).
#
# Requires: build-port.sh libffi wayland wayland-protocols pixman
#           xkeyboard-config libxkbcommon
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
TC="$HERE/tc/bin/i586-elf32-minix"
SR="$HERE/sysroot"
WORK="$HERE/build/test-wayland"
PC="$HERE/tc/bin/i586-elf32-minix-pkg-config"

rm -rf "$WORK"
mkdir -p "$WORK/payload/bin" "$WORK/payload/pkg"

"$TC-gcc" --sysroot="$SR" -std=gnu99 -O2 -Wall -Wl,-z,noexecstack \
	$("$PC" --cflags wayland-server wayland-client pixman-1 xkbcommon) \
	-o "$WORK/payload/bin/wl-gate" "$HERE/tests/wl-gate.c" \
	$("$PC" --libs wayland-server wayland-client pixman-1 xkbcommon) \
	-Wl,-rpath,/usr/pkg/lib
# The runtime part of the ports tree (no headers/pkgconfig).
cp -Rp "$HERE/rootfs/usr/pkg/lib" "$WORK/payload/pkg/"
rm -rf "$WORK/payload/pkg/lib/pkgconfig"
mkdir -p "$WORK/payload/pkg/share/X11"
cp -Rp "$HERE/rootfs/usr/pkg/share/X11/xkb" "$WORK/payload/pkg/share/X11/"

"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 600 \
	--cmd 'cp -Rp /mnt/pkg/lib /mnt/pkg/share /usr/pkg/ && ls /usr/pkg/lib | wc -l' \
	--cmd 'rm -rf /tmp/xdg; mkdir -m 700 /tmp/xdg; XDG_RUNTIME_DIR=/tmp/xdg /mnt/bin/wl-gate' \
	--expect 'WLGATE-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-wayland-gate.log"
