#!/bin/sh
# test-blit.sh - Phase 8 render-path check for the MINIX Hyprland
# optimizations: tests/shm-pattern.c windows (XRGB, ARGB + opaque region,
# translucent ARGB) under Hyprland, each screendumped with the blit fast
# path on and off (HYPRLAND_MINIX_NOBLIT=1); tests/checkblit.py verifies
# the pattern pixel-exact and that both paths agree.  IMAGE= overrides.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
SR="$HERE/sysroot"
TC="$HERE/tc/bin/i586-elf32-minix"
WORK="$HERE/build/test-blit"
SHOTS="$WORK/shots"
XML="$HERE/rootfs/usr/pkg/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
rm -rf "$WORK"; mkdir -p "$WORK/payload/bin" "$WORK/gen" "$SHOTS"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE"/tests/perf/*.sh "$WORK/payload/scripts/"
"$HERE/host/bin/wayland-scanner" client-header "$XML" "$WORK/gen/xdg-shell-client-protocol.h"
"$HERE/host/bin/wayland-scanner" private-code "$XML" "$WORK/gen/xdg-shell-protocol.c"
"$TC-gcc" --sysroot="$SR" -std=gnu99 -O2 -Wall -Wl,-z,noexecstack \
	-I"$WORK/gen" -I"$SR/usr/pkg/include" -o "$WORK/payload/bin/shm-pattern" \
	"$HERE/tests/shm-pattern.c" "$WORK/gen/xdg-shell-protocol.c" \
	-L"$SR/usr/pkg/lib" -lwayland-client -Wl,-rpath,/usr/pkg/lib
LABELS="xrgb xrgb_nb argbo argbo_nb argb"
set --
for L in $LABELS; do set -- "$@" --input "$L=screendump $SHOTS/$L.ppm"; done
"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 900 "$@" \
	--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd 'sh /mnt/scripts/hypr-shot.sh xrgb xrgb' \
	--cmd 'HYPRLAND_MINIX_NOBLIT=1 sh /mnt/scripts/hypr-shot.sh xrgb_nb xrgb' \
	--cmd 'sh /mnt/scripts/hypr-shot.sh argbo argb-opaque' \
	--cmd 'HYPRLAND_MINIX_NOBLIT=1 sh /mnt/scripts/hypr-shot.sh argbo_nb argb-opaque' \
	--cmd 'sh /mnt/scripts/hypr-shot.sh argb argb' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-blit-gate.log" > /dev/null
grep -aE '^(SHOTWIN|SHMPATTERN|BLITUSED)' "$HERE/tests/last-blit-gate.log" | tr -d '\r'
python3 -I "$HERE/tests/checkblit.py" "$HERE/tests/last-blit-gate.log" "$SHOTS" $LABELS
