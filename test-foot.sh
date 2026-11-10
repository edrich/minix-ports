#!/bin/sh
# test-foot.sh - Phase 9 gate: foot (+ fcft, tllist) under Hyprland, opened
# with the SUPER+Return keybind and typed into through QEMU's keyboard
# (tests/foot/foot.sh); screendump in tests/last-foot.ppm.  IMAGE=<path>
# overrides the image.  Needs OS change 40 (C11 threads, semaphores,
# <uchar.h>, UTF-8 locales) in the image.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-foot"
SHOT="$HERE/tests/last-foot.ppm"
rm -rf "$WORK"
mkdir -p "$WORK/payload/bin"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE/tests/foot/"*.sh "$WORK/payload/scripts/"
rm -f "$SHOT"
TYPE="sendkey t; sendkey o; sendkey u; sendkey c; sendkey h; sendkey spc"
TYPE="$TYPE; sendkey slash; sendkey t; sendkey m; sendkey p; sendkey slash"
TYPE="$TYPE; sendkey f; sendkey o; sendkey o; sendkey t; sendkey o; sendkey k"
TYPE="$TYPE; sendkey ret"
"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 1200 \
	--input "openterm=sendkey meta_l-ret" \
	--input "typecmd=$TYPE" \
	--input "shot=screendump $SHOT" \
	--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd 'sh /mnt/scripts/foot.sh' \
	--expect 'FOOT-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-foot-gate.log"
