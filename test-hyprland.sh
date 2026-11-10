#!/bin/sh
# test-hyprland.sh - Phase 8 gate: Hyprland v0.22.0beta (ports/hyprland.sh)
# on /dev/drm0 with weston-simple-egl tiled, hyprctl over IPC, screendump
# checked by tests/checkhyprland.py.  IMAGE=<path> overrides the image.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-hyprland"
SHOT="$HERE/tests/last-hyprland.ppm"

rm -rf "$WORK"
mkdir -p "$WORK/payload/bin"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE/tests/hyprland/"*.sh "$WORK/payload/scripts/"
rm -f "$SHOT"

"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 1200 \
	--input "shot=screendump $SHOT" \
	--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd 'sh /mnt/scripts/hyprland.sh' \
	--expect 'HYPRLAND-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-hyprland-gate.log"

python3 -I "$HERE/tests/checkhyprland.py" "$SHOT"
