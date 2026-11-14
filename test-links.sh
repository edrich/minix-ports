#!/bin/sh
# test-links.sh - Phase 10 gate: the links text browser (tests/links/
# links.sh): -dump of a local page and of http/https pages through QEMU
# user-mode networking, then links in foot under Hyprland showing an https
# page (screendump tests/last-links.ppm) and quit from the keyboard.
# URL=<https url> WANT=<text on that page> choose the page (default
# example.com).  IMAGE=<path> overrides the image.  Needs network access.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-links"
SHOT="$HERE/tests/last-links.ppm"
rm -rf "$WORK"
mkdir -p "$WORK/payload"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE/tests/links/"*.sh "$WORK/payload/scripts/"
rm -f "$SHOT"
"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} --net \
	--payload "$WORK/payload" --timeout 1200 \
	--input "openterm=sendkey meta_l-ret" \
	--input "welcome=sendkey ret" \
	--input "shot=screendump $SHOT" \
	--input "typequit=sendkey q; sendkey ret" \
	--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd "${URL:+URL='$URL' }${WANT:+WANT='$WANT' }sh /mnt/scripts/links.sh" \
	--expect 'LINKS-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-links-gate.log" > /dev/null || rc=$?
grep -a '^LINKS' "$HERE/tests/last-links-gate.log" | tr -d '\r'
exit ${rc:-0}
