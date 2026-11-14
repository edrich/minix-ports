#!/bin/sh
# start-hyprland - the MINIX Hyprland session (installed into the desktop
# image by run-hyprland.sh as /usr/pkg/bin/start-hyprland).
#
#   start-hyprland            start Hyprland on /dev/drm0 in the background
#   start-hyprland stop       stop it
#   start-hyprland status     is it running?
#   start-hyprland ctl ARGS   hyprctl ARGS for the running instance
#   start-hyprland enable | disable    (root) start at boot: hyprland=YES/NO
#                             in /etc/rc.conf, see /etc/rc.d/hyprland
#
# Root hands over to the desktop user ($HYPRLAND_USER, default "desk", made
# by run-hyprland.sh; member of group operator for /dev/drm0 and
# /dev/input/event*) when that user exists; HYPRLAND_USER=root keeps root.
# Log: /tmp/hyprland-<user>.out.  Config: ~/.config/hypr/hyprland.conf,
# written on first start.
#
# Keys (MOD = SUPER or ALT; ALT for when the host eats SUPER):
#   MOD+Return  foot terminal        MOD+Q        close window
#   MOD+B       NetSurf browser
#   MOD+F       fullscreen           MOD+V        toggle floating
#   MOD+arrows  move focus           MOD+1..4     workspace 1..4
#   MOD+SHIFT+1..4  move window to workspace     MOD+SHIFT+E  exit
#   MOD+left/right mouse drag: move/resize window
SELF=/usr/pkg/bin/start-hyprland
DUSER=${HYPRLAND_USER:-desk}

case "${1:-start}" in
enable|disable)
	[ "$(id -u)" = 0 ] || { echo "start-hyprland $1: must be root"; exit 1; }
	v=NO; [ "$1" = enable ] && v=YES
	grep -v '^hyprland=' /etc/rc.conf > /etc/rc.conf.new
	echo "hyprland=$v" >> /etc/rc.conf.new
	mv /etc/rc.conf.new /etc/rc.conf
	echo "hyprland=$v in /etc/rc.conf"
	exit 0 ;;
start|stop|status|ctl) ;;
*)	sed -n '2,24p' $0; exit 1 ;;
esac

if [ "$(id -u)" = 0 ] && [ "$DUSER" != root ] && id "$DUSER" > /dev/null 2>&1
then
	cmd=$SELF
	for a in "$@"; do cmd="$cmd '$a'"; done
	exec su -l "$DUSER" -c "$cmd"
fi

unset LD_LIBRARY_PATH	# would beat the ports' RPATH (base libgcc_s stub)
ulimit -c 0		# no core files of a crashed compositor
ME=$(id -un)
export XDG_RUNTIME_DIR=/tmp/xdg-$ME HOME=${HOME:-/root}
export LANG=en_US.UTF-8	# foot and friends need a UTF-8 LC_CTYPE
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
LOG=/tmp/hyprland-$ME.out
CONF=$HOME/.config/hypr/hyprland.conf

running() { ps ax | grep '[/]usr/pkg/bin/Hyprland' | awk '{print $1}'; }

case "${1:-start}" in
stop)
	for p in $(running); do kill $p 2>/dev/null; done
	n=0
	while [ -n "$(running)" ] && [ $n -lt 15 ]; do sleep 1; n=$((n+1)); done
	[ -z "$(running)" ] || { echo "Hyprland still running"; exit 1; }
	exit 0 ;;
status)
	p=$(running)
	[ -n "$p" ] && { echo "Hyprland running (pid $p)"; exit 0; }
	echo "Hyprland not running"; exit 1 ;;
ctl)
	shift
	sig=$(ls -t /tmp/hypr 2>/dev/null | head -1)
	[ -n "$sig" ] || { echo "no Hyprland instance"; exit 1; }
	HYPRLAND_INSTANCE_SIGNATURE=$sig exec /usr/pkg/bin/hyprctl "$@" ;;
esac

[ -n "$(running)" ] && { echo "Hyprland already running (pid $(running))"; exit 1; }
for d in /dev/drm0 /dev/input/event0 /dev/input/event1; do
	[ -r $d ] && [ -w $d ] ||
	    { echo "$ME cannot open $d (not in group operator?)"; exit 1; }
done

rm -rf $XDG_RUNTIME_DIR; mkdir -m 700 $XDG_RUNTIME_DIR || exit 1
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
bind = $m, Return, exec, /usr/pkg/bin/foot > /tmp/foot-$ME.log 2>&1
bind = $m, B, exec, /usr/pkg/bin/netsurf-fb -f wl > /tmp/netsurf-$ME.log 2>&1
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

flags=; [ "$(id -u)" = 0 ] && flags=--i-am-really-stupid
cd $HOME
/usr/pkg/bin/Hyprland $flags -c $CONF > $LOG 2>&1 < /dev/null &
H=$!
i=0
while ! ls $XDG_RUNTIME_DIR 2>/dev/null | grep -q '^wayland-[0-9]*$' &&
    [ $i -lt 60 ] && kill -0 $H 2>/dev/null; do
	sleep 1; i=$((i+1))
done
if kill -0 $H 2>/dev/null; then
	echo "Hyprland running as $ME (pid $H, log $LOG). SUPER/ALT+Return opens foot."
	echo "hyprctl: start-hyprland ctl clients"
else
	echo "Hyprland exited; last log lines:"; tail -30 $LOG; exit 1
fi
