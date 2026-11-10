#!/bin/sh
# gl.sh headless|drm - Weston with the GL renderer (Mesa softpipe through
# EGL: surfaceless for headless, GBM/kms_swrast on /dev/drm0 for drm) and
# the weston-simple-egl client (EGL wayland platform).  The drm variant
# asks the harness for a screendump (HARNESS:INPUT:shot) while the client
# runs.  Prints WESTON-GL-<BACKEND>-OK when Weston came up with the GL
# renderer and simple-egl kept drawing frames.
# MINIX /etc/profile puts /usr/lib before /usr/pkg/lib in LD_LIBRARY_PATH,
# which beats RPATH: the base libgcc_s.so.1 stub would shadow the ports' one.
unset LD_LIBRARY_PATH
B=${1:?usage: gl.sh headless|drm}
TAG=$(echo $B | tr a-z A-Z)
export XDG_RUNTIME_DIR=/tmp/xdg
rm -rf $XDG_RUNTIME_DIR; mkdir -m 700 $XDG_RUNTIME_DIR
LOG=/tmp/weston-gl-$B.log
CLOG=/tmp/simple-egl-$B.log
cat > /tmp/weston-gl.ini <<'INI'
[core]
idle-time=0

[shell]
background-color=0xff1f4f6f
panel-position=top
locking=false
INI
${PRELOAD:+env LD_PRELOAD=$PRELOAD} /usr/pkg/bin/weston --backend=$B \
	--renderer=gl --socket=wayland-1 \
	--config=/tmp/weston-gl.ini --log=$LOG &
W=$!
i=0
while [ ! -S $XDG_RUNTIME_DIR/wayland-1 ] && [ $i -lt 90 ]; do
	sleep 1; i=$((i+1))
done
if [ ! -S $XDG_RUNTIME_DIR/wayland-1 ]; then
	echo "WESTON-GL-$TAG: no socket after ${i}s"; cat $LOG; kill $W; exit 1
fi
echo "WESTON-GL-$TAG: socket up after ${i}s"
sleep 3
WAYLAND_DISPLAY=wayland-1 ${CPRELOAD:+env LD_PRELOAD=$CPRELOAD} \
	/usr/pkg/bin/weston-simple-egl > $CLOG 2>&1 &
C=$!
sleep 14
if [ $B = drm ]; then
	echo; echo HARNESS:INPUT:shot
	sleep 3
fi
if kill -0 $C 2>/dev/null; then
	# SIGINT: simple-egl exits cleanly and flushes its fps lines.
	run=1; kill -INT $C; wait $C
else
	run=0; wait $C; echo "WESTON-GL-$TAG: simple-egl exited early ($?)"
fi
kill $W; wait $W
echo "== weston log"; cat $LOG
echo "== simple-egl log"; cat $CLOG
gl=0; grep -q "GL version" $LOG && gl=1
frames=0; grep -q "frames in" $CLOG && frames=1
echo "WESTON-GL-$TAG: gl-renderer=$gl client-running=$run fps-report=$frames"
[ $gl = 1 ] && [ $run = 1 ] && [ $frames = 1 ] && echo WESTON-GL-$TAG-OK
