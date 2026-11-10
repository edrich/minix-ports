#!/bin/sh
# test-drm.sh - Phase 3 gate for the libdrm port: build tests/drm-demo.c
# against the cross-built libdrm (rootfs/usr/pkg), run it inside MINIX on
# the bochs DRM-lite device, and verify the test card via a screendump.
#
# Requires: build-port.sh libdrm, and an image with the bochs driver.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
TC="$HERE/tc/bin/i586-elf32-minix"
SR="$HERE/sysroot"
WORK="$HERE/build/test-drm"

rm -rf "$WORK"
mkdir -p "$WORK/payload/bin" "$WORK/payload/lib"

"$TC-gcc" --sysroot="$SR" -std=gnu99 -O2 -Wall -Wl,-z,noexecstack \
	-I"$SR/usr/pkg/include" -I"$SR/usr/pkg/include/libdrm" \
	-o "$WORK/payload/bin/drm-demo" "$HERE/tests/drm-demo.c" \
	-L"$SR/usr/pkg/lib" -ldrm -Wl,-rpath,/usr/pkg/lib
cp -P "$HERE"/rootfs/usr/pkg/lib/libdrm.so* "$WORK/payload/lib/"

"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 400 \
	--cmd 'LD_LIBRARY_PATH=/mnt/lib /mnt/bin/drm-demo' \
	--cmd 'rm -rf /tmp/dd; mkdir /tmp/dd; cp -Rp /mnt/bin /mnt/lib /tmp/dd/; (LD_LIBRARY_PATH=/tmp/dd/lib /tmp/dd/bin/drm-demo 30 > /tmp/dd/log 2>&1 &); sleep 6; cat /tmp/dd/log' \
	--expect 'wlroots DRM prerequisites ok' \
	--expect 'DRMDEMO-OK' \
	--expect 'HARNESS:DONE:0' \
	--screendump "$WORK/card.ppm" \
	--log "$HERE/tests/last-drm-gate.log"

python3 "$HERE/tests/checkcard.py" "$WORK/card.ppm"
