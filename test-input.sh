#!/bin/sh
# test-input.sh - Phase 5 gate: tests/input-gate.c (libseat + libinput over
# libudev-minix and the input server's evdev devices, xkbcommon) inside
# MINIX, with keyboard and mouse input injected through QEMU's monitor.
#
# Requires: the OS image with evdev support (MAKEDEV input), and
#   build-port.sh libevdev mtdev libudev-minix libinput libseat
#   (+ xkeyboard-config libxkbcommon from Phase 4)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
TC="$HERE/tc/bin/i586-elf32-minix"
SR="$HERE/sysroot"
WORK="$HERE/build/test-input"
PC="$HERE/tc/bin/i586-elf32-minix-pkg-config"
PKGS="libinput libseat libudev xkbcommon"

rm -rf "$WORK"
mkdir -p "$WORK/payload/bin" "$WORK/payload/pkg"

"$TC-gcc" --sysroot="$SR" -std=gnu99 -O2 -Wall -Wl,-z,noexecstack \
	$("$PC" --cflags $PKGS) \
	-o "$WORK/payload/bin/input-gate" "$HERE/tests/input-gate.c" \
	$("$PC" --libs $PKGS) -Wl,-rpath,/usr/pkg/lib
# The runtime part of the ports tree (no headers/pkgconfig).
cp -Rp "$HERE/rootfs/usr/pkg/lib" "$WORK/payload/pkg/"
rm -rf "$WORK/payload/pkg/lib/pkgconfig"
mkdir -p "$WORK/payload/pkg/share/X11"
cp -Rp "$HERE/rootfs/usr/pkg/share/X11/xkb" "$WORK/payload/pkg/share/X11/"
cp -Rp "$HERE/rootfs/usr/pkg/share/libinput" "$WORK/payload/pkg/share/"

"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 600 \
	--input 'keys=sendkey a;sleep 0.3;sendkey shift-b' \
	--input 'mouse=mouse_move 20 10;sleep 0.3;mouse_button 1;sleep 0.3;mouse_button 0' \
	--cmd 'cp -Rp /mnt/pkg/lib /mnt/pkg/share /usr/pkg/ && ls /usr/pkg/lib | wc -l' \
	--cmd 'ls -l /dev/input' \
	--cmd '/mnt/bin/input-gate' \
	--expect 'INPUTGATE-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-input-gate.log"
