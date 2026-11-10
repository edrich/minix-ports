#!/bin/sh
# Weston on the DRM backend (/dev/drm0, pixman renderer) with the desktop
# shell and weston-terminal.  The harness types "touch /tmp/typed" + Enter
# into the terminal (HARNESS:INPUT:type) and takes a screendump
# (HARNESS:INPUT:shot).  Prints WESTON-DRM-OK if the typed command ran.
# MINIX /etc/profile puts /usr/lib before /usr/pkg/lib in LD_LIBRARY_PATH,
# which beats RPATH: the base libgcc_s.so.1 stub would shadow the ports' one.
unset LD_LIBRARY_PATH
export XDG_RUNTIME_DIR=/tmp/xdg
rm -rf $XDG_RUNTIME_DIR /tmp/typed; mkdir -m 700 $XDG_RUNTIME_DIR
LOG=/tmp/weston-drm.log
cat > /tmp/weston.ini <<'INI'
[core]
idle-time=0

[shell]
background-color=0xff1f4f6f
panel-position=top
locking=false

[terminal]
font=monospace
font-size=16
INI
${PRELOAD:+env LD_PRELOAD=$PRELOAD} /usr/pkg/bin/weston --backend=drm \
	--renderer=pixman --socket=wayland-1 --config=/tmp/weston.ini \
	--log=$LOG &
W=$!
i=0
while [ ! -S $XDG_RUNTIME_DIR/wayland-1 ] && [ $i -lt 60 ]; do
	sleep 1; i=$((i+1))
done
if [ ! -S $XDG_RUNTIME_DIR/wayland-1 ]; then
	echo "WESTON-DRM: no socket after ${i}s"; cat $LOG; kill $W; exit 1
fi
echo "WESTON-DRM: socket up after ${i}s"
sleep 3
SHELL=/bin/sh WAYLAND_DISPLAY=wayland-1 ${TERM_DEBUG:+env WAYLAND_DEBUG=1} /usr/pkg/bin/weston-terminal 2>/tmp/term.log &
T=$!
sleep 8
echo; echo HARNESS:INPUT:type
i=0
while [ ! -f /tmp/typed ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
[ -f /tmp/typed ] && ok=1 || ok=0
echo "WESTON-DRM: typed command ran: $ok (after ${i}s)"
sleep 2
echo; echo HARNESS:INPUT:shot
sleep 3
kill $T 2>/dev/null
kill $W; wait $W
cat $LOG
if [ -n "$TERM_DEBUG" ]; then
	echo "== terminal input events"
	grep -E "wl_keyboard|wl_pointer@[0-9]+\.(enter|button)" /tmp/term.log | head -40
fi
[ $ok = 1 ] && echo WESTON-DRM-OK
