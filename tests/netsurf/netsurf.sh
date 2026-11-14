#!/bin/sh
# netsurf.sh - Phase 10 gate, run in the guest by test-netsurf.sh: the
# NetSurf browser (framebuffer frontend on the libnsfb Wayland surface of
# the ports patch) under Hyprland.  Pages a/b/c.html and red.jpg come from
# the payload (/mnt/nsw); each has its own background colour, which the
# host checks in the screendumps.  Steps (HARNESS:INPUT:<name>):
#   shota            a.html: green page, a JPEG (red) that is a link
#   home tolink click   pointer onto the JPEG, left click -> b.html (blue)
#   tourl click typeurl  click the URL bar, Ctrl+U, type the URL of c.html
#                    + Return -> c.html (yellow): keyboard incl. shift
#   (second client)  the tile shrinks: NetSurf follows the new size
#   typenet          (unless NONET=1) type an https URL -> fetched with 200
#   (close)          hyprctl dispatch closewindow: NetSurf exits
# Prints NETSURF-OK.
unset LD_LIBRARY_PATH
ulimit -c 0
PATH=/usr/pkg/bin:$PATH; export PATH
NETURL=${NETURL:-https://example.com/}
rm -rf /tmp/nsw; cp -R /mnt/nsw /tmp/nsw
export XDG_RUNTIME_DIR=/tmp/xdg HOME=/tmp/hyprhome
rm -rf $XDG_RUNTIME_DIR $HOME /tmp/hypr; mkdir -m 700 $XDG_RUNTIME_DIR
mkdir -p $HOME/.config/hypr
export LANG=en_US.UTF-8
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
CONF=$HOME/.config/hypr/hyprland.conf
LOG=/tmp/hyprland.out
NLOG=/tmp/netsurf.log
fails=0
ok() { echo "NETSURF: ok   $1"; }
bad() { echo "NETSURF: FAIL $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
waitfor() {	# <seconds> <condition>
	i=0
	while ! eval "$2" && [ $i -lt $1 ]; do sleep 1; i=$((i+1)); done
	eval "$2"
}
[ "${NONET:-0}" = 1 ] || dhcpcd -qM -4 -w em0 || bad "dhcp"
cat > $CONF <<CFG
monitor=,preferred,auto,1
input {
    follow_mouse = 1
    accel_profile = flat
    sensitivity = 0
}
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 3
    col.active_border = rgba(ffcc00ff)
    col.inactive_border = rgba(404040ff)
}
decoration {
    rounding = 0
    blur = false
    drop_shadow = false
}
animations {
    enabled = false
}
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}
exec-once = /usr/pkg/bin/netsurf-fb -v -f wl file:///tmp/nsw/a.html > $NLOG 2>&1
CFG
stop() {
	kill -$2 $1 2>/dev/null
	n=0
	while kill -0 $1 2>/dev/null && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
	kill -0 $1 2>/dev/null && { echo "NETSURF: pid $1 ignored SIG$2, killing"; kill -9 $1; }
}
/usr/pkg/bin/Hyprland --i-am-really-stupid -c $CONF > $LOG 2>&1 &
H=$!
sock() { ls $XDG_RUNTIME_DIR 2>/dev/null | grep '^wayland-[0-9]*$' | head -1; }
i=0
while [ -z "$(sock)" ] && [ $i -lt 90 ] && kill -0 $H 2>/dev/null; do
	sleep 1; i=$((i+1))
done
[ -n "$(sock)" ] || { echo "NETSURF: no Hyprland socket"; tail -40 $LOG; exit 1; }
SIG=$(ls /tmp/hypr | head -1)
hc() { HYPRLAND_INSTANCE_SIGNATURE=$SIG /usr/pkg/bin/hyprctl "$@"; }
nspid() { ps ax | grep '[/]usr/pkg/bin/netsurf-fb' | grep -v 'sh -c' | awk '{print $1}' | head -1; }
nssize() { hc clients | awk '/size: /{s=$2} /class: netsurf/{print s}'; }
opened() { grep -q "content_open: content .* $1\$" $NLOG; }
step() { echo; echo HARNESS:INPUT:$1; sleep ${2:-3}; }

check "window (class netsurf)" "waitfor 60 'hc clients 2>/dev/null | grep -q \"class: netsurf\"'"
check "a.html opened" "waitfor 30 'opened file:///tmp/nsw/a.html'"
S0=$(nssize); echo "NETSURF: window size $S0 at $(hc clients | awk '/at: /{print $2}')"
check "window is tiled (not 800x600)" '[ -n "$S0" ] && [ "$S0" != 800,600 ]'
check "JPEG decoded" 'grep -q "red.jpg" $NLOG && ! grep -qi "red.jpg.*\(fail\|error\)" $NLOG'
sleep 3
step shota 4

step home 8
step tolink 4
step click 2
check "click on the image link opened b.html" "waitfor 30 'opened file:///tmp/nsw/b.html'"
sleep 3
step shotb 4

step tourl 4
step click 2
step typeurl 10
check "typed URL opened c.html" "waitfor 30 'opened file:///tmp/nsw/c.html'"
sleep 3
step shotc 4

# a second client: the tile shrinks, NetSurf has to follow
WAYLAND_DISPLAY=$(sock) /usr/pkg/bin/weston-simple-shm > /tmp/simple-shm.log 2>&1 &
check "window resized by the compositor" "waitfor 30 '[ \"\$(nssize)\" != \"$S0\" ]'"
S1=$(nssize); echo "NETSURF: window size now $S1"
sleep 5
check "NetSurf alive after the resize" '[ -n "$(nspid)" ]'
step shotr 4
for p in $(ps ax | grep '[w]eston-simple-shm' | awk '{print $1}'); do kill $p; done
check "window back to the full tile" "waitfor 30 '[ \"\$(nssize)\" = \"$S0\" ]'"
sleep 4

if [ "${NONET:-0}" != 1 ]; then
	step tourl 4
	step click 2
	step typenet 10
	check "https page fetched" "waitfor 40 'grep -q \"fetch_curl_done: done $NETURL\" $NLOG'"
	check "https page opened" "waitfor 20 'opened $NETURL'"
	check "HTTP status 200" 'grep -q "HTTP status code 200" $NLOG'
	sleep 3
	step shotn 4
fi

check "Hyprland alive" 'kill -0 $H 2>/dev/null'
hc dispatch closewindow netsurf > /dev/null	# regex on the class
check "close request ends NetSurf" "waitfor 20 '[ -z \"\$(nspid)\" ]'"
stop $H TERM
echo "== netsurf log (warnings, errors)"
grep -E 'WARNING|ERROR|CRITICAL' $NLOG | cut -c1-200 | head -20
echo "== netsurf log (pages)"; grep 'content_open' $NLOG | cut -c1-160
echo "NETSURF: fails=$fails"
[ $fails = 0 ] && echo NETSURF-OK
