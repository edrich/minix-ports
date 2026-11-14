#!/bin/sh
# test-desktop.sh - Phase 9 gate: the desktop image (run-hyprland.sh
# prepare: base image + /usr/pkg + desktop/ session files) boots and
#  1. `start-hyprland` runs Hyprland as the unprivileged user "desk",
#     SUPER+Return opens foot (UTF-8 locale), typed text runs in its shell,
#     a crashing client leaves no core file (needs RLIMIT_CORE in PM, OS
#     change 44), status/ctl/stop work (tests/desktop/desktop.sh session);
#  2. after `start-hyprland enable` the next boot comes up with Hyprland
#     running (rc.d/hyprland), checked on a scratch copy of the image.
# Screendumps: tests/last-desktop.ppm, tests/last-desktop-boot.ppm.
# IMAGE=<path> overrides the BASE image.  NOPREPARE=1 reuses
# build/desktop/minix-desktop.img.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-desktop"
IMG="$HERE/build/desktop/minix-desktop.img"
BOOTDIR=$HERE/../obj.docker.i386/destdir.i386/boot/minix/.temp
LOG="$HERE/tests/last-desktop-gate.log"
SHOT="$HERE/tests/last-desktop.ppm"
SHOT2="$HERE/tests/last-desktop-boot.ppm"

[ -n "${NOPREPARE:-}" ] && [ -f "$IMG" ] || "$HERE/run-hyprland.sh" prepare
rm -rf "$WORK"; mkdir -p "$WORK/payload/scripts"
cp "$HERE/tests/desktop/"*.sh "$WORK/payload/scripts/"
rm -f "$SHOT" "$SHOT2" "$LOG"
TYPE="sendkey t; sendkey o; sendkey u; sendkey c; sendkey h; sendkey spc"
TYPE="$TYPE; sendkey slash; sendkey t; sendkey m; sendkey p; sendkey slash"
TYPE="$TYPE; sendkey d; sendkey e; sendkey s; sendkey k; sendkey o; sendkey k"
TYPE="$TYPE; sendkey ret"
rc=0
boot() {	# <log suffix> <image> <harness args...>
	l=$1 i=$2; shift 2
	"$REPO/releasetools/x86_qemu.py" --image "$i" --bootdir "$BOOTDIR" \
		--payload "$WORK/payload" --timeout 900 "$@" \
		--expect 'HARNESS:DONE:0' --log "$WORK/$l.log" > /dev/null || rc=1
	cat "$WORK/$l.log" >> "$LOG"
}
boot session "$IMG" \
	--input "openterm=sendkey meta_l-ret" --input "typecmd=$TYPE" \
	--input "shot=screendump $SHOT" \
	--cmd 'sh /mnt/scripts/desktop.sh session' --expect DESKTOP-SESSION-OK

cp --sparse=always "$IMG" "$WORK/autostart.img"
boot enable "$WORK/autostart.img" --persist \
	--cmd 'sh /mnt/scripts/desktop.sh enable' --expect DESKTOP-ENABLE-OK
boot autostart "$WORK/autostart.img" \
	--input "shot2=screendump $SHOT2" \
	--cmd 'sh /mnt/scripts/desktop.sh autostart' --expect DESKTOP-AUTOSTART-OK
rm -f "$WORK/autostart.img"
grep -a '^DESKTOP' "$LOG" | tr -d '\r'
exit $rc
