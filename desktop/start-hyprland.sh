#!/bin/sh
# start-hyprland - start Hyprland on /dev/drm0 for interactive use
# (installed into the desktop image by run-hyprland.sh).  Run as root from
# the serial console; Hyprland runs in the background, the shell stays
# usable.  Log: /tmp/hyprland.out.  Stop: start-hyprland stop (or MOD+SHIFT+E).
#
# Keys (MOD = SUPER or ALT; ALT for when the host eats SUPER):
#   MOD+Return  foot terminal        MOD+Q        close window
#   MOD+F       fullscreen           MOD+V        toggle floating
#   MOD+arrows  move focus           MOD+1..4     workspace 1..4
#   MOD+SHIFT+1..4  move window to workspace     MOD+SHIFT+E  exit
#   MOD+left/right mouse drag: move/resize window
unset LD_LIBRARY_PATH	# /etc/profile's /usr/lib would shadow our libgcc_s
ulimit -c 0		# a crashed compositor's core fills the root fs
export XDG_RUNTIME_DIR=/tmp/xdg HOME=${HOME:-/root}
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
LOG=/tmp/hyprland.out
CONF=$HOME/.config/hypr/hyprland.conf

running() { ps ax | grep '[/]usr/pkg/bin/Hyprland' | awk '{print $1}'; }

if [ "${1:-}" = stop ]; then
	for p in $(running); do kill $p; done
	exit 0
fi
[ -n "$(running)" ] && { echo "Hyprland already running (pid $(running))"; exit 1; }

rm -rf $XDG_RUNTIME_DIR /tmp/hypr; mkdir -m 700 $XDG_RUNTIME_DIR
if [ ! -f $CONF ]; then
	mkdir -p $(dirname $CONF)
	{
	cat <<'CFG'
# Software rendering (Mesa softpipe): keep animations/blur/shadows/rounding
# off - each costs a shaded full-window pass per frame.
monitor=,preferred,auto,1
input {
    kb_layout = us
    follow_mouse = 1
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
CFG
	for m in SUPER ALT; do
		cat <<CFG
bind = $m, Return, exec, /usr/pkg/bin/foot > /tmp/foot.log 2>&1
bind = $m, Q, killactive,
bind = $m SHIFT, E, exit,
bind = $m, F, fullscreen, 0
bind = $m, V, togglefloating,
bind = $m, left, movefocus, l
bind = $m, right, movefocus, r
bind = $m, up, movefocus, u
bind = $m, down, movefocus, d
bindm = $m, mouse:272, movewindow
bindm = $m, mouse:273, resizewindow
CFG
		for n in 1 2 3 4; do
			echo "bind = $m, $n, workspace, $n"
			echo "bind = $m SHIFT, $n, movetoworkspace, $n"
		done
	done
	} > $CONF
	echo "wrote default config $CONF"
fi

/usr/pkg/bin/Hyprland --i-am-really-stupid -c $CONF > $LOG 2>&1 &
H=$!
i=0
while ! ls $XDG_RUNTIME_DIR 2>/dev/null | grep -q '^wayland-[0-9]*$' &&
    [ $i -lt 60 ] && kill -0 $H 2>/dev/null; do
	sleep 1; i=$((i+1))
done
if kill -0 $H 2>/dev/null; then
	echo "Hyprland running (pid $H, log $LOG). SUPER/ALT+Return opens foot."
	echo "hyprctl: HYPRLAND_INSTANCE_SIGNATURE=\$(ls /tmp/hypr) /usr/pkg/bin/hyprctl clients"
else
	echo "Hyprland exited; last log lines:"; tail -30 $LOG; exit 1
fi
