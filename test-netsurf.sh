#!/bin/sh
# test-netsurf.sh - Phase 10 gate: the NetSurf browser under Hyprland
# (tests/netsurf/netsurf.sh): local pages with a JPEG link, navigation by
# mouse click and by a URL typed into the URL bar, a compositor-driven
# resize, an https page (QEMU user-mode networking), close.  The guest
# checks NetSurf's log and hyprctl; this script checks the screendumps
# (tests/last-netsurf-{a,b,c,r,n}.ppm) for the pages' background colours.
# NONET=1 skips the https part.  IMAGE=<path> overrides the image.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-netsurf"
SHOT="$HERE/tests/last-netsurf"
NETURL=${NETURL:-https://example.com/}
rm -rf "$WORK"
mkdir -p "$WORK/payload/nsw"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE/tests/netsurf/"*.sh "$WORK/payload/scripts/"
rm -f "$SHOT"-*.ppm

# test pages: one background colour each; a.html links to b.html through
# a JPEG (libjpeg-turbo's test image, 227x149)
N="$WORK/payload/nsw"
cp "$HERE"/src/libjpeg-turbo-*/testimages/testorig.jpg "$N/red.jpg"
cat > "$N/a.html" <<'HTML'
<html><head><title>Page A</title></head><body bgcolor="#00c000">
<a href="b.html"><img src="red.jpg" width="454" height="298" border="0"></a>
<h1>Page A</h1><p>NetSurf on MINIX: click the picture.</p>
</body></html>
HTML
cat > "$N/b.html" <<'HTML'
<html><head><title>Page B</title></head><body bgcolor="#0000c0" text="#ffffff">
<h1>Page B</h1><p>Reached by a mouse click.</p></body></html>
HTML
cat > "$N/c.html" <<'HTML'
<html><head><title>Page C</title></head><body bgcolor="#e0e000">
<h1>Page C</h1><p>Reached by typing its URL.</p></body></html>
HTML

# monitor commands: pointer moves in steps of at most 50 counts
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
# type <text>: sendkey commands for a URL (lower case, digits, : / . -)
type_keys() {
	printf '%s' "$1" | awk 'BEGIN { m[":"] = "shift-semicolon"; m["/"] = "slash"
		m["."] = "dot"; m["-"] = "minus" }
	{ n = length($0); for (i = 1; i <= n; i++) { c = substr($0, i, 1)
		printf "sendkey %s; ", (c in m) ? m[c] : c } }'
}
net=--net; [ "${NONET:-0}" = 1 ] && net=
# The picture: window at 11,11 (gap 8 + border 3), toolbar 30 high, body
# margin 8 -> the image covers about 19..473 x 49..347.  URL bar: right of
# the five toolbar buttons.
"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} $net \
	--payload "$WORK/payload" --timeout 1500 \
	--input "home=$(move -1400 -1400)" \
	--input "tolink=$(move 240 200)" \
	--input "click=mouse_button 1; sleep 0.2; mouse_button 0" \
	--input "tourl=$(move -1400 -1400) $(move 500 26)" \
	--input "typeurl=sendkey ctrl-u; $(type_keys file:///tmp/nsw/c.html) sendkey ret" \
	--input "typenet=sendkey ctrl-u; $(type_keys "$NETURL") sendkey ret" \
	--input "shota=screendump $SHOT-a.ppm" \
	--input "shotb=screendump $SHOT-b.ppm" \
	--input "shotc=screendump $SHOT-c.ppm" \
	--input "shotr=screendump $SHOT-r.ppm" \
	--input "shotn=screendump $SHOT-n.ppm" \
	--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd "NONET=${NONET:-0} NETURL=$NETURL sh /mnt/scripts/netsurf.sh" \
	--expect 'NETSURF-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-netsurf-gate.log" > /dev/null || rc=$?
grep -a '^NETSURF' "$HERE/tests/last-netsurf-gate.log" | tr -d '\r'

# Screendumps: share of pixels close to a colour (PPM P6, 8 bit).
share() {	# <file> <r> <g> <b>
	python3 - "$@" <<'PY'
import sys
f, r, g, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
d = open(f, 'rb').read()
p = d.split(None, 4)            # P6 w h max data
w, h, px = int(p[1]), int(p[2]), p[4]
n = sum(1 for i in range(0, w * h * 3, 3 * 7)   # every 7th pixel
        if abs(px[i] - r) < 24 and abs(px[i+1] - g) < 24 and abs(px[i+2] - b) < 24)
print(int(100 * n * 7 / (w * h)))
PY
}
pix() {		# <name> <file> <r> <g> <b> <min %> [<max %>]
	if [ ! -f "$2" ]; then echo "NETSURF: FAIL $1: no screendump"; rc=1; return; fi
	s=$(share "$2" "$3" "$4" "$5")
	if [ "$s" -ge "$6" ] && [ "$s" -le "${7:-100}" ]; then
		echo "NETSURF: ok   $1: $s%"
	else
		echo "NETSURF: FAIL $1: $s% (want $6..${7:-100}%)"; rc=1
	fi
}
pix "page A is green" "$SHOT-a.ppm" 0 192 0 40
pix "page B is blue" "$SHOT-b.ppm" 0 0 192 70
pix "page C is yellow" "$SHOT-c.ppm" 224 224 0 70
pix "resized: C in half the screen" "$SHOT-r.ppm" 224 224 0 25 55
exit ${rc:-0}
