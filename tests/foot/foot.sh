#!/bin/sh
# foot.sh - Phase 9 gate: foot under Hyprland, driven by the keyboard.
# Hyprland binds SUPER+Return to foot; the harness presses it
# (HARNESS:INPUT:openterm), then types "touch /tmp/footok" + Return into
# the terminal (HARNESS:INPUT:typecmd): keyboard -> libinput -> Hyprland
# keybind -> foot -> pty -> shell.  Screendump: HARNESS:INPUT:shot.
# Prints FOOT-OK.
unset LD_LIBRARY_PATH
ulimit -c 0
export XDG_RUNTIME_DIR=/tmp/xdg HOME=/tmp/hyprhome
rm -rf $XDG_RUNTIME_DIR $HOME /tmp/hypr /tmp/footok; mkdir -m 700 $XDG_RUNTIME_DIR
mkdir -p $HOME/.config/hypr
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
CONF=$HOME/.config/hypr/hyprland.conf
LOG=/tmp/hyprland.out
FLOG=/tmp/foot.log
cat > $CONF <<CFG
monitor=,preferred,auto,1
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
bind = SUPER, Return, exec, /usr/pkg/bin/foot > $FLOG 2>&1
CFG
stop() {
	kill -$2 $1 2>/dev/null
	n=0
	while kill -0 $1 2>/dev/null && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
	kill -0 $1 2>/dev/null && { echo "FOOT: pid $1 ignored SIG$2, killing"; kill -9 $1; }
}
/usr/pkg/bin/Hyprland --i-am-really-stupid -c $CONF > $LOG 2>&1 &
H=$!
sock() { ls $XDG_RUNTIME_DIR 2>/dev/null | grep '^wayland-[0-9]*$' | head -1; }
i=0
while [ -z "$(sock)" ] && [ $i -lt 90 ] && kill -0 $H 2>/dev/null; do
	sleep 1; i=$((i+1))
done
[ -n "$(sock)" ] || { echo "FOOT: no Hyprland socket"; tail -40 $LOG; exit 1; }
echo "FOOT: Hyprland up after ${i}s"
sleep 5
SIG=$(ls /tmp/hypr | head -1)
hc() { HYPRLAND_INSTANCE_SIGNATURE=$SIG /usr/pkg/bin/hyprctl "$@"; }
echo; echo HARNESS:INPUT:openterm
i=0
while ! hc clients 2>/dev/null | grep -q 'class: foot' && [ $i -lt 60 ]; do
	sleep 1; i=$((i+1))
done
term=0; hc clients | grep -q 'class: foot' && term=1
echo "FOOT: terminal window=$term after ${i}s"
sleep 5	# shell prompt
echo; echo HARNESS:INPUT:typecmd
i=0
while [ ! -f /tmp/footok ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
typed=0; [ -f /tmp/footok ] && typed=1
echo "FOOT: typed command ran=$typed after ${i}s"
sleep 2
echo; echo HARNESS:INPUT:shot
sleep 3
echo "== hyprctl clients"; hc clients | grep -E 'Window|class|title|at:|size:'
F=$(ps ax | grep '[/]usr/pkg/bin/foot' | awk '{print $1}' | head -1)
[ -n "$F" ] && stop $F TERM
stop $H TERM
echo "== foot log"; grep -v '^$' $FLOG | head -40
echo "== Hyprland log (errors)"; grep -aE 'ERR|CRIT' $LOG | head -20
echo "FOOT: window=$term typed=$typed"
[ $term = 1 ] && [ $typed = 1 ] && echo FOOT-OK
