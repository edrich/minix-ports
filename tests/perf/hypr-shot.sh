#!/bin/sh
# hypr-shot.sh <label> <shm-pattern mode> - Hyprland (gate config) with
# tests/shm-pattern.c as its only window; after it settles prints the
# window geometry ("SHOTWIN <label> x y w h", from hyprctl) and
# HARNESS:INPUT:<label> (the harness takes a screendump), then the
# FRAMESTATS lines (HYPRLAND_MINIX_FRAMESTATS=1 is set).  Environment
# (HYPRLAND_MINIX_NO*) passes through to Hyprland.  Labels: [A-Za-z0-9_]
# (the harness matches HARNESS:INPUT:\w+).
L=${1:?label}; MODE=${2:?mode}
unset LD_LIBRARY_PATH
export XDG_RUNTIME_DIR=/tmp/xdg HOME=/tmp/hyprhome HYPRLAND_MINIX_FRAMESTATS=1
rm -rf $XDG_RUNTIME_DIR $HOME /tmp/hypr; mkdir -m 700 $XDG_RUNTIME_DIR
mkdir -p $HOME/.config/hypr
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
CONF=$HOME/.config/hypr/hyprland.conf
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
exec-once = /mnt/bin/shm-pattern $MODE > /tmp/shm-pattern.log 2>&1
CFG
/usr/pkg/bin/Hyprland --i-am-really-stupid -c $CONF > /tmp/hypr-$L.out 2>&1 &
H=$!
sleep 25
SIG=$(ls /tmp/hypr | head -1)
HYPRLAND_INSTANCE_SIGNATURE=$SIG /usr/pkg/bin/hyprctl clients > /tmp/clients.out 2>&1
awk -v L=$L '/at: /{split($2, a, ",")} /size: /{split($2, s, ","); print "SHOTWIN", L, a[1], a[2], s[1], s[2]}' /tmp/clients.out
cat /tmp/shm-pattern.log
echo; echo HARNESS:INPUT:$L
sleep 4
C=$(ps ax | grep '[s]hm-pattern' | awk '{print $1}' | head -1)
[ -n "$C" ] && kill $C
sleep 1
kill $H 2>/dev/null
n=0; while kill -0 $H 2>/dev/null && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
kill -9 $H 2>/dev/null
grep -a '^FRAMESTATS' /tmp/hypr-$L.out | tail -2 | sed "s/^/$L /"
B=0; grep -aq 'MINIX: opaque textures are blitted' /tmp/hypr-$L.out && B=1
echo "BLITUSED $L $B"
