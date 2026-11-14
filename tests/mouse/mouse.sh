#!/bin/sh
# mouse.sh - Phase 8 gate: Hyprland driven by the mouse.  Two windows:
# tests/shm-pattern.c floating at 100,100 400x300 (window rules) above a
# tiled weston-simple-shm.  The harness moves the QEMU PS/2 mouse
# (HARNESS:INPUT:<step>); after each step the script reads hyprctl:
#   home     pointer into the top-left corner         -> cursorpos 0,0
#   tofloat  +350,+300: over the floating window      -> it has the focus
#   totile   +450,+300: over the tiled window         -> focus follows
#   back     -450,-300                                -> floating focused
#   drag     SUPER + left button, +200,+100           -> window moved
#   resize   SUPER + right button, +100,+50           -> window resized
#   shot     screendump
# Path: pckbd -> input server evdev -> libinput -> wlroots -> Hyprland
# (follow_mouse, bindm).  accel_profile flat: 1 count = 1 pixel.
# Prints MOUSE-OK.
unset LD_LIBRARY_PATH
ulimit -c 0
export XDG_RUNTIME_DIR=/tmp/xdg HOME=/tmp/hyprhome
rm -rf $XDG_RUNTIME_DIR $HOME /tmp/hypr; mkdir -m 700 $XDG_RUNTIME_DIR
mkdir -p $HOME/.config/hypr
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
CONF=$HOME/.config/hypr/hyprland.conf
LOG=/tmp/hyprland.out
TOL=${TOL:-12}		# pixels
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
windowrulev2 = float, class:^(shm-pattern)\$
windowrulev2 = size 400 300, class:^(shm-pattern)\$
windowrulev2 = move 100 100, class:^(shm-pattern)\$
bindm = SUPER, mouse:272, movewindow
bindm = SUPER, mouse:273, resizewindow
exec-once = /usr/pkg/bin/weston-simple-shm > /tmp/simple-shm.log 2>&1
exec-once = /mnt/bin/shm-pattern xrgb > /tmp/shm-pattern.log 2>&1
CFG
stop() {
	kill -$2 $1 2>/dev/null
	n=0
	while kill -0 $1 2>/dev/null && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
	kill -0 $1 2>/dev/null && { echo "MOUSE: pid $1 ignored SIG$2, killing"; kill -9 $1; }
}
/usr/pkg/bin/Hyprland --i-am-really-stupid -c $CONF > $LOG 2>&1 &
H=$!
sock() { ls $XDG_RUNTIME_DIR 2>/dev/null | grep '^wayland-[0-9]*$' | head -1; }
i=0
while [ -z "$(sock)" ] && [ $i -lt 90 ] && kill -0 $H 2>/dev/null; do
	sleep 1; i=$((i+1))
done
[ -n "$(sock)" ] || { echo "MOUSE: no Hyprland socket"; tail -40 $LOG; exit 1; }
echo "MOUSE: Hyprland up after ${i}s"
SIG=$(ls /tmp/hypr | head -1)
hc() { HYPRLAND_INSTANCE_SIGNATURE=$SIG /usr/pkg/bin/hyprctl "$@"; }
i=0
while [ "$(hc clients 2>/dev/null | grep -c 'class: ')" -lt 2 ] && [ $i -lt 60 ]; do
	sleep 1; i=$((i+1))
done
sleep 3
echo "== hyprctl clients"; hc clients | grep -E 'Window|at:|size:|floating:|class:'

# "x y" of the pointer; "class x y w h" of the focused / the floating window
cursor() { hc cursorpos | tr -d ',' ; }
active() { hc activewindow | awk '/at: /{split($2,a,",")} /size: /{split($2,s,",")}
	/class: /{c=$2} END{print c, a[1], a[2], s[1], s[2]}'; }
floatwin() { hc clients | awk '/at: /{split($2,a,",")} /size: /{split($2,s,",")}
	/class: shm-pattern/{print a[1], a[2], s[1], s[2]}'; }
# near <name> <got...> -- <want...>: all within TOL
fails=0
near() {
	name=$1; shift
	if echo "$*" | awk -v t=$TOL '{ n = (NF - 1) / 2
	    for (i = 1; i <= n; i++) { d = $i - $(i + n + 1); if (d < 0) d = -d
		if (d > t) exit 1 } }'; then
		echo "MOUSE: ok   $name: $*"
	else
		echo "MOUSE: FAIL $name: $* (tolerance $TOL)"; fails=$((fails+1))
	fi
}
is() {
	if [ "$2" = "$3" ]; then echo "MOUSE: ok   $1: $2"
	else echo "MOUSE: FAIL $1: got '$2', want '$3'"; fails=$((fails+1)); fi
}
step() { echo; echo HARNESS:INPUT:$1; sleep ${2:-6}; }

F0=$(floatwin)
near "floating window placed" $F0 -- 100 100 400 300

step home 10
near "pointer in the corner" $(cursor) -- 0 0

step tofloat
near "pointer over the floating window" $(cursor) -- 350 300
set -- $(active); is "focus (floating)" "$1" shm-pattern

step totile
near "pointer over the tiled window" $(cursor) -- 800 600
set -- $(active); is "focus follows to the tiled window" "$1" org.freedesktop.weston.simple-shm

step back
near "pointer back" $(cursor) -- 350 300
set -- $(active); is "focus back on the floating window" "$1" shm-pattern

step drag 14
near "pointer after the drag" $(cursor) -- 550 400
near "window moved by 200,100" $(floatwin) -- 300 200 400 300

step resize 14
near "pointer after the resize" $(cursor) -- 650 450
near "window resized by 100,50" $(floatwin) -- 300 200 500 350
set -- $(active); is "focus after the drags" "$1" shm-pattern

step shot 4
echo "== hyprctl clients"; hc clients | grep -E 'Window|at:|size:|floating:|class:'
alive=0; kill -0 $H 2>/dev/null && alive=1
for p in $(ps ax | grep -E '[s]hm-pattern|[w]eston-simple-shm' | awk '{print $1}'); do
	kill $p
done
sleep 1
stop $H TERM
echo "== shm-pattern log"; cat /tmp/shm-pattern.log
echo "== Hyprland log (binds)"; grep -aE "Keybind triggered" $LOG | tail
echo "== Hyprland log (errors)"; grep -aE 'ERR|CRIT' $LOG | head -20
echo "MOUSE: alive=$alive fails=$fails"
[ $alive = 1 ] && [ $fails = 0 ] && echo MOUSE-OK
