#!/bin/sh
# test-mouse.sh - Phase 8 gate: Hyprland driven by the QEMU mouse
# (tests/mouse/mouse.sh): pointer motion, focus-follows-mouse between a
# floating and a tiled window, SUPER+left drag moves and SUPER+right drag
# resizes the floating window; all checked through hyprctl.  Screendump in
# tests/last-mouse.ppm.  IMAGE=<path> overrides the image.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
SR="$HERE/sysroot"
TC="$HERE/tc/bin/i586-elf32-minix"
WORK="$HERE/build/test-mouse"
SHOT="$HERE/tests/last-mouse.ppm"
XML="$HERE/rootfs/usr/pkg/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
rm -rf "$WORK"
mkdir -p "$WORK/payload/bin" "$WORK/gen"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE/tests/mouse/"*.sh "$WORK/payload/scripts/"
"$HERE/host/bin/wayland-scanner" client-header "$XML" "$WORK/gen/xdg-shell-client-protocol.h"
"$HERE/host/bin/wayland-scanner" private-code "$XML" "$WORK/gen/xdg-shell-protocol.c"
"$TC-gcc" --sysroot="$SR" -std=gnu99 -O2 -Wall -Wl,-z,noexecstack \
	-I"$WORK/gen" -I"$SR/usr/pkg/include" -o "$WORK/payload/bin/shm-pattern" \
	"$HERE/tests/shm-pattern.c" "$WORK/gen/xdg-shell-protocol.c" \
	-L"$SR/usr/pkg/lib" -lwayland-client -Wl,-rpath,/usr/pkg/lib
rm -f "$SHOT"

# move <dx> <dy>: monitor commands in steps of at most 50 counts (a PS/2
# packet carries -256..255; small steps also look like a real mouse)
move() {
	awk -v dx="$1" -v dy="$2" 'BEGIN {
		ax = dx < 0 ? -dx : dx; ay = dy < 0 ? -dy : dy
		n = int(((ax > ay ? ax : ay) + 49) / 50); if (n < 1) n = 1
		px = 0; py = 0
		for (i = 1; i <= n; i++) {
			x = int(dx * i / n); y = int(dy * i / n)
			printf "mouse_move %d %d; sleep 0.05; ", x - px, y - py
			px = x; py = y
		}
	}'
}
# SUPER stays down for 6 s (sendkey hold time) around the button drag.
# QEMU queues another delay of the hold time after the release: a sendkey
# within 12 s of this one is held back (the guest waits 14 s per drag).
drag() {	# <button mask (1 left, 2 right)> <dx> <dy>
	echo "sendkey meta_l 6000; sleep 1; mouse_button $1; sleep 0.5;" \
	    "$(move "$2" "$3") sleep 1; mouse_button 0; sleep 0.5"
}
"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 1200 \
	--input "home=$(move -1400 -1400)" \
	--input "tofloat=$(move 350 300)" \
	--input "totile=$(move 450 300)" \
	--input "back=$(move -450 -300)" \
	--input "drag=$(drag 1 200 100)" \
	--input "resize=$(drag 2 100 50)" \
	--input "shot=screendump $SHOT" \
	--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd 'sh /mnt/scripts/mouse.sh' \
	--expect 'MOUSE-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-mouse-gate.log" > /dev/null || rc=$?
grep -a '^MOUSE' "$HERE/tests/last-mouse-gate.log" | tr -d '\r'
exit ${rc:-0}
