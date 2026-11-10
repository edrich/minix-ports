#!/bin/sh
# Weston smoke test on the headless backend (pixman renderer): start the
# compositor, connect weston-simple-shm for a few seconds, stop it.
# MINIX /etc/profile puts /usr/lib before /usr/pkg/lib in LD_LIBRARY_PATH,
# which beats RPATH: the base libgcc_s.so.1 stub would shadow the ports' one.
unset LD_LIBRARY_PATH
export XDG_RUNTIME_DIR=/tmp/xdg
rm -rf $XDG_RUNTIME_DIR; mkdir -m 700 $XDG_RUNTIME_DIR
LOG=/tmp/weston-headless.log
${PRELOAD:+env LD_PRELOAD=$PRELOAD} /usr/pkg/bin/weston --backend=headless --renderer=pixman --socket=wayland-1 \
	--log=$LOG &
W=$!
i=0
while [ ! -S $XDG_RUNTIME_DIR/wayland-1 ] && [ $i -lt 60 ]; do
	sleep 1; i=$((i+1))
done
if [ ! -S $XDG_RUNTIME_DIR/wayland-1 ]; then
	echo "WESTON-HEADLESS: no socket after ${i}s"; cat $LOG; kill $W; exit 1
fi
echo "WESTON-HEADLESS: socket up after ${i}s"
WAYLAND_DISPLAY=wayland-1 /usr/pkg/bin/weston-simple-shm &
C=$!
sleep 5
if kill -0 $C 2>/dev/null; then
	echo "WESTON-HEADLESS: simple-shm still running after 5s"; ok=1
	kill $C
else
	wait $C; echo "WESTON-HEADLESS: simple-shm exited early ($?)"; ok=0
fi
kill $W; wait $W
cat $LOG
[ $ok = 1 ] && echo WESTON-HEADLESS-OK
