#!/bin/sh
# test-wlroots.sh - Phase 8 gate: wlroots (ports/wlroots.sh) - tinywl on
# /dev/drm0 with the GLES2 renderer (Mesa softpipe, GBM allocator, PRIME)
# and weston-simple-egl as client; the screendump is checked by
# tests/checkwlroots.py.  IMAGE=<path> overrides the harness default image.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-wlroots"
SHOT="$HERE/tests/last-wlroots.ppm"

rm -rf "$WORK"
mkdir -p "$WORK/payload/bin"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE/tests/wlroots/"*.sh "$WORK/payload/scripts/"
cp "$HERE/build/wlroots/obj/tinywl/tinywl" "$WORK/payload/bin/"
"$HERE/tc/bin/i586-elf32-minix-strip" "$WORK/payload/bin/tinywl"
rm -f "$SHOT"

"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 900 \
	--input "shot=screendump $SHOT" \
	--cmd 'unset LD_LIBRARY_PATH; cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd 'sh /mnt/scripts/tinywl.sh' \
	--expect 'WLROOTS-TINYWL-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-wlroots-gate.log"

python3 -I "$HERE/tests/checkwlroots.py" "$SHOT"
