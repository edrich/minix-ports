#!/bin/sh
# tinywl.sh - wlroots smoke test: tinywl (wlroots' minimal compositor) on
# the DRM backend (/dev/drm0, legacy KMS), GLES2 renderer on Mesa softpipe
# (EGL/GBM, buffers shared by PRIME), libinput through libseat; the
# weston-simple-egl client draws into a toplevel.  The harness takes a
# screendump (HARNESS:INPUT:shot).  Prints WLROOTS-TINYWL-OK.
unset LD_LIBRARY_PATH
export XDG_RUNTIME_DIR=/tmp/xdg
rm -rf $XDG_RUNTIME_DIR; mkdir -m 700 $XDG_RUNTIME_DIR
# Software rendering is refused unless allowed; DRM-lite has no atomic KMS
# and no format modifiers; skip the udev scan for the DRM device.
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
LOG=/tmp/tinywl.log
CLOG=/tmp/simple-egl.log
# stop PID: SIGINT/SIGTERM, then SIGKILL after 5 s; never blocks forever.
stop() {
	kill -$2 $1 2>/dev/null
	n=0
	while kill -0 $1 2>/dev/null && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
	if kill -0 $1 2>/dev/null; then
		echo "WLROOTS-TINYWL: pid $1 ignored SIG$2, killing"; kill -9 $1
	fi
}
${PRELOAD:+env LD_PRELOAD=$PRELOAD} /mnt/bin/tinywl > $LOG 2>&1 &
W=$!
i=0
while [ ! -S $XDG_RUNTIME_DIR/wayland-0 ] && [ $i -lt 60 ] && kill -0 $W 2>/dev/null
do
	sleep 1; i=$((i+1))
done
if [ ! -S $XDG_RUNTIME_DIR/wayland-0 ]; then
	echo "WLROOTS-TINYWL: no socket after ${i}s"
	grep -v '^$' $LOG | tail -60; kill $W 2>/dev/null; exit 1
fi
echo "WLROOTS-TINYWL: socket up after ${i}s"
sleep 3
echo "== tinywl log so far (tail)"; grep -v '^$' $LOG | tail -25
WAYLAND_DISPLAY=wayland-0 ${CPRELOAD:+env LD_PRELOAD=$CPRELOAD} \
	/usr/pkg/bin/weston-simple-egl > $CLOG 2>&1 &
C=$!
sleep 14
echo; echo HARNESS:INPUT:shot
sleep 3
if kill -0 $C 2>/dev/null; then
	run=1; stop $C INT
else
	run=0; echo "WLROOTS-TINYWL: simple-egl exited early"
fi
alive=0; kill -0 $W 2>/dev/null && alive=1
if [ -n "$HANGDIAG" ] && [ $alive = 1 ]; then
	# Where is the compositor?  Run with PRELOAD=crashmap.so: SIGABRT
	# prints its registers, stack and load bases.
	ps alx | grep -E 'UID|tinywl|simple' ; kill -ABRT $W; sleep 3
	grep -a CRASHMAP $LOG
fi
stop $W TERM
echo "== tinywl log (selected)"
grep -E 'ERROR|rror|fail|Running Wayland|renderer|allocator|EGL|GBM|DRM|drm|libinput|seat|output|mode|Using' $LOG | head -100
echo "== simple-egl log"; cat $CLOG
up=0; grep -q 'Running Wayland compositor' $LOG && up=1
frames=0; grep -q 'frames in' $CLOG && frames=1
echo "WLROOTS-TINYWL: compositor-up=$up still-alive=$alive client-running=$run fps-report=$frames"
[ $up = 1 ] && [ $alive = 1 ] && [ $run = 1 ] && [ $frames = 1 ] && echo WLROOTS-TINYWL-OK
