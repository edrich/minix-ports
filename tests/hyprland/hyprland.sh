#!/bin/sh
# hyprland.sh - Phase 8 gate: Hyprland on the DRM backend (/dev/drm0,
# legacy KMS), GLES2 on Mesa softpipe (GBM + PRIME), libinput via libseat.
# A minimal config (no animations/blur/shadows/wallpaper: software
# rendering) starts weston-simple-egl, which Hyprland tiles; hyprctl talks
# to the IPC socket; the harness takes a screendump (HARNESS:INPUT:shot).
# Prints HYPRLAND-OK.
unset LD_LIBRARY_PATH
ulimit -c 0	# a crashed compositor's core fills the root fs
export XDG_RUNTIME_DIR=/tmp/xdg HOME=/tmp/hyprhome
rm -rf $XDG_RUNTIME_DIR $HOME /tmp/hypr; mkdir -m 700 $XDG_RUNTIME_DIR
mkdir -p $HOME/.config/hypr
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
CONF=$HOME/.config/hypr/hyprland.conf
LOG=/tmp/hyprland.out
CLOG=/tmp/simple-egl.log
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
exec-once = /usr/pkg/bin/weston-simple-egl > $CLOG 2>&1
CFG
stop() {
	kill -$2 $1 2>/dev/null
	n=0
	while kill -0 $1 2>/dev/null && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
	if kill -0 $1 2>/dev/null; then
		echo "HYPRLAND: pid $1 ignored SIG$2, killing"; kill -9 $1
	fi
}
${PRELOAD:+env LD_PRELOAD=$PRELOAD} /usr/pkg/bin/Hyprland --i-am-really-stupid \
	-c $CONF > $LOG 2>&1 &
H=$!
# Crash reports (Hyprland's SIGSEGV/SIGABRT handler, with a backtrace).
crashreports() {
	for f in $HOME/.hyprland/.hyprlandCrashReport*; do
		[ -f "$f" ] && { echo "== $f"; cat "$f"; }
	done
}
sock() { ls $XDG_RUNTIME_DIR 2>/dev/null | grep '^wayland-[0-9]*$' | head -1; }
i=0
while [ -z "$(sock)" ] && [ $i -lt 90 ] && kill -0 $H 2>/dev/null; do
	sleep 1; i=$((i+1))
done
if [ -z "$(sock)" ]; then
	echo "HYPRLAND: no socket after ${i}s"
	grep -v '^$' $LOG | tail -60; crashreports; stop $H TERM; exit 1
fi
echo "HYPRLAND: socket $(sock) up after ${i}s"
sleep 20
SIG=$(ls /tmp/hypr | head -1)
echo "== hyprctl monitors"
HYPRLAND_INSTANCE_SIGNATURE=$SIG /usr/pkg/bin/hyprctl monitors > /tmp/hyprctl.out 2>&1
cat /tmp/hyprctl.out
echo "== hyprctl clients"
HYPRLAND_INSTANCE_SIGNATURE=$SIG /usr/pkg/bin/hyprctl clients 2>&1 | head -20
echo; echo HARNESS:INPUT:shot
sleep 3
alive=0; kill -0 $H 2>/dev/null && alive=1
C=$(ps ax | grep '[w]eston-simple-egl' | awk '{print $1}' | head -1)
run=0; [ -n "$C" ] && run=1 && stop $C INT
stop $H TERM
echo "== Hyprland log (selected)"
grep -aE 'ERR|rror|CRIT|fail|Fail|renderer|Monitor|monitor|EGL|GL_|wlr|socket|exec' $LOG | head -80
echo "== simple-egl log"; cat $CLOG
crashreports
mon=0; grep -q 'Virtual-1' /tmp/hyprctl.out && mon=1
frames=0; grep -q 'frames in' $CLOG && frames=1
echo "HYPRLAND: alive=$alive hyprctl-monitor=$mon client-running=$run fps-report=$frames"
[ $alive = 1 ] && [ $mon = 1 ] && [ $run = 1 ] && [ $frames = 1 ] && echo HYPRLAND-OK
