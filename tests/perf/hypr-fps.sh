#!/bin/sh
# hypr-fps.sh <label> [config lines...] - run Hyprland (as the Phase 8 gate,
# no checks) with weston-simple-egl for ~30 s and print its steady fps:
# "PERF <label> fps <avg of the last reports>".  Extra arguments are
# appended to hyprland.conf (window rules, debug options); SEGL_ARGS go
# to weston-simple-egl (-o: opaque surface).
L=${1:?label}; shift
unset LD_LIBRARY_PATH
export XDG_RUNTIME_DIR=/tmp/xdg HOME=/tmp/hyprhome
rm -rf $XDG_RUNTIME_DIR $HOME /tmp/hypr; mkdir -m 700 $XDG_RUNTIME_DIR
mkdir -p $HOME/.config/hypr
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
CONF=$HOME/.config/hypr/hyprland.conf
CLOG=/tmp/simple-egl-$L.log
cat > $CONF <<CFG
monitor=,preferred,auto,1
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 3
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
exec-once = /usr/pkg/bin/weston-simple-egl ${SEGL_ARGS:-} > $CLOG 2>&1
CFG
for line in "$@"; do echo "$line" >> $CONF; done
# SPROF=1: sampling profiler (tests/sprof.c) in Hyprland and its children
# (they inherit LD_PRELOAD); profiles land in /tmp/sprof.<pid>.
rm -f /tmp/sprof.*
${SPROF:+env LD_PRELOAD=/mnt/bin/sprof.so} \
	/usr/pkg/bin/Hyprland --i-am-really-stupid -c $CONF > /tmp/hypr-$L.out 2>&1 &
H=$!
# PSDUMP=1: per-process CPU time (ps alx TIME, servers included) at 10 s
# and 30 s; tests/perf/psdiff.py turns the pair into CPU shares.
sleep 10
[ -n "$PSDUMP" ] && ps alx > /tmp/ps1
sleep 20
[ -n "$PSDUMP" ] && ps alx > /tmp/ps2
sleep 2
if [ -n "$PSDUMP" ]; then
	echo "PSDUMP1 $L"; cat /tmp/ps1; echo "PSDUMPEND"
	echo "PSDUMP2 $L"; cat /tmp/ps2; echo "PSDUMPEND"
fi
grep -a 'Config error\|error' /tmp/hypr-$L.out | head -3
# HYPRLAND_MINIX_FRAMESTATS=1: Hyprland's per-frame time breakdown
grep -a '^FRAMESTATS' /tmp/hypr-$L.out | sed "s/^/$L /"
C=$(ps ax | grep '[w]eston-simple-egl' | awk '{print $1}' | head -1)
[ -n "$C" ] && kill -INT $C
sleep 2
kill $H 2>/dev/null
n=0; while kill -0 $H 2>/dev/null && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
kill -9 $H 2>/dev/null
if [ -n "$SPROF" ]; then
	sleep 2
	for f in /tmp/sprof.*; do
		[ -f "$f" ] || continue
		echo "SPROFFILE $f"; cat "$f"; echo "SPROFEND"
	done
fi
# skip the first report (startup), average the rest
awk '/frames in/ {n++; if (n > 1) {s += $(NF-1); k++}}
     END {printf "PERF %s fps %.2f (%d reports)\n", L, k ? s / k : 0, k}' \
	L=$L $CLOG
