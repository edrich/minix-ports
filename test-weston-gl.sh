#!/bin/sh
# test-weston-gl.sh - Phase 7 gate: Weston's GL renderer (Mesa softpipe)
# with the weston-simple-egl client (EGL wayland platform).
#  1. headless backend, gl-renderer on EGL surfaceless
#  2. DRM backend on /dev/drm0, gl-renderer on GBM/kms_swrast, desktop
#     shell; the screendump is checked by tests/checkweston-gl.py.
# Requires the Phase 4-7 ports with Weston built -Drenderer-gl=true
# (ports/weston.sh) and a current OS image (IMAGE=<path> overrides the
# harness default minix_x86.img).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-weston-gl"
SHOT="$HERE/tests/last-weston-gl.ppm"

rm -rf "$WORK"
mkdir -p "$WORK/payload"
"$HERE/stage-payload.sh" "$WORK/payload"
rm -f "$SHOT"

"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 900 \
	--input "shot=screendump $SHOT" \
	--cmd 'unset LD_LIBRARY_PATH; cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd 'sh /mnt/scripts/gl.sh headless' \
	--cmd 'sh /mnt/scripts/gl.sh drm' \
	--expect 'WESTON-GL-HEADLESS-OK' \
	--expect 'WESTON-GL-DRM-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-weston-gl-gate.log"

python3 -I "$HERE/tests/checkweston-gl.py" "$SHOT"
