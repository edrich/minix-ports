#!/bin/sh
# test-weston.sh - Phase 6 gate: Weston inside MINIX.
#  1. headless backend (pixman): desktop shell + weston-simple-shm client
#  2. DRM backend on /dev/drm0 (pixman renderer): desktop shell, panel,
#     weston-terminal; QEMU types "touch /tmp/typed" + Enter into the
#     terminal (keyboard -> input server evdev -> libinput -> Weston ->
#     terminal -> shell) and takes a screendump, checked by
#     tests/checkweston.py.
# Requires the Phase 6 ports (see README) and an OS image with evdev,
# DRM-lite and the libc/libmthread changes of 2026-11-07.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-weston"
SHOT="$HERE/tests/last-weston.ppm"

rm -rf "$WORK"
mkdir -p "$WORK/payload"
"$HERE/stage-payload.sh" "$WORK/payload"
rm -f "$SHOT"

"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 900 \
	--input 'type=mouse_button 1;sleep 0.2;mouse_button 0;sleep 0.5;sendkey t;sendkey o;sendkey u;sendkey c;sendkey h;sendkey spc;sendkey slash;sendkey t;sendkey m;sendkey p;sendkey slash;sendkey t;sendkey y;sendkey p;sendkey e;sendkey d;sendkey ret' \
	--input "shot=screendump $SHOT" \
	--cmd 'unset LD_LIBRARY_PATH; cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd 'sh /mnt/scripts/headless.sh' \
	--cmd 'sh /mnt/scripts/drm.sh' \
	--expect 'WESTON-HEADLESS-OK' \
	--expect 'WESTON-DRM-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-weston-gate.log"

python3 -I "$HERE/tests/checkweston.py" "$SHOT"
