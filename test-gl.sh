#!/bin/sh
# test-gl.sh - Phase 7 gate: Mesa (softpipe) OpenGL ES 2 inside MINIX.
#  1. tests/egl-gate.c surfaceless: EGL surfaceless platform + pbuffer,
#     GLSL program, glReadPixels check.
#  1b. tests/egl-gate.c dmabuf: PRIME export + EGL dma-buf import (wlroots)
#  2. tests/egl-gate.c gbm: GBM + EGL on /dev/drm0 (kms_swrast), animated
#     frames scanned out with page flips; the last frame is checked from a
#     screendump (tests/checkgl.py).
# Requires the Phase 4-7 ports (see README) and a current OS image.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
TC="$HERE/tc/bin/i586-elf32-minix"
SR="$HERE/sysroot"
WORK="$HERE/build/test-gl"
SHOT="$WORK/gl.ppm"

rm -rf "$WORK"
mkdir -p "$WORK/payload/bin"
"$HERE/stage-payload.sh" "$WORK/payload"
"$TC-gcc" --sysroot="$SR" -std=gnu99 -O2 -Wall -Wl,-z,noexecstack \
	-I"$SR/usr/pkg/include" -I"$SR/usr/pkg/include/libdrm" \
	-o "$WORK/payload/bin/egl-gate" "$HERE/tests/egl-gate.c" \
	-L"$SR/usr/pkg/lib" -lEGL -lGLESv2 -lgbm -ldrm -lm \
	-Wl,-rpath,/usr/pkg/lib

"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 900 \
	--cmd 'unset LD_LIBRARY_PATH; cp -Rp /mnt/pkg/* /usr/pkg/ && cp /mnt/bin/egl-gate /tmp/ && echo installed' \
	--cmd 'unset LD_LIBRARY_PATH; /tmp/egl-gate surfaceless' \
	--cmd 'unset LD_LIBRARY_PATH; /tmp/egl-gate dmabuf' \
	--cmd 'unset LD_LIBRARY_PATH; (/tmp/egl-gate gbm 120 > /tmp/gbm.log 2>&1 &); i=0; while [ $i -lt 300 ] && ! grep -E -q "EGL-GBM-OK|EGL-FAIL" /tmp/gbm.log; do sleep 1; i=$((i+1)); done; sleep 2; cat /tmp/gbm.log; grep -q EGL-GBM-OK /tmp/gbm.log' \
	--expect 'EGL-SURFACELESS-OK' \
	--expect 'EGL-GBM-OK' \
	--expect 'EGL-DMABUF-OK' \
	--expect 'HARNESS:DONE:0' \
	--screendump "$SHOT" \
	--log "$HERE/tests/last-gl-gate.log"

python3 -I "$HERE/tests/checkgl.py" "$SHOT"
