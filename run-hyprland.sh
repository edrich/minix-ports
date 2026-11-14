#!/bin/sh
# run-hyprland.sh - boot MINIX with the ports tree installed, for trying
# Hyprland by hand.
#
#  1. Prepare (automatic when stale): copy ../minix/minix_x86.img to
#     build/desktop/minix-desktop.img and install rootfs/usr/pkg (stripped,
#     via stage-payload.sh) plus the session files of desktop/ into it
#     (desktop/install.sh: start-hyprland, /etc/rc.d/hyprland, the desktop
#     user "desk"), using the headless harness with --persist.  Redone
#     whenever the base image, rootfs/usr/pkg or desktop/ is newer than the
#     desktop image.
#  2. Boot it: serial console (root login, no password) in this terminal,
#     screen on VNC 127.0.0.1:5901 (a viewer is started if one is found).
#     In the guest: `start-hyprland` (runs Hyprland as "desk"), then
#     SUPER+Return (or ALT+Return) in the VNC window opens foot.
#     `start-hyprland enable` (with PERSIST=1) starts it at every boot.
#     Leave with `poweroff`, or Ctrl-A x.
#
# Env: IMAGE=<base image>  MEM=<MB, default 256>  VNC=<display, default 1>
#      PERSIST=1 (keep guest changes; default snapshot - crashed
#      compositors' core dumps otherwise fill the root fs)
#      NOVIEWER=1 (do not start a VNC viewer)
# Args: prepare (only step 1, forced).  Gate: test-desktop.sh.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../minix" && pwd)
BASE=${IMAGE:-$REPO/minix_x86.img}
WORK=$HERE/build/desktop
IMG=$WORK/minix-desktop.img
BOOTDIR=$HERE/../obj.docker.i386/destdir.i386/boot/minix/.temp
[ -d "$BOOTDIR" ] || BOOTDIR=$HERE/../obj.i386/destdir.i386/boot/minix/.temp
MEM=${MEM:-256}
VNC=${VNC:-1}

stale() {
	[ ! -f "$IMG" ] && return 0
	[ "$BASE" -nt "$IMG" ] && return 0
	[ -n "$(find "$HERE/rootfs/usr/pkg" "$HERE/desktop" -newer "$IMG" 2>/dev/null | head -1)" ]
}

prepare() {
	echo "== preparing $IMG"
	mkdir -p "$WORK"
	rm -rf "$WORK/payload" "$IMG.tmp"
	mkdir -p "$WORK/payload"
	"$HERE/stage-payload.sh" "$WORK/payload"
	cp "$HERE"/desktop/* "$WORK/payload/scripts/"
	cp --sparse=always "$BASE" "$IMG.tmp"
	"$REPO/releasetools/x86_qemu.py" --image "$IMG.tmp" --bootdir "$BOOTDIR" \
		--persist --payload "$WORK/payload" --timeout 900 \
		--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
		--cmd 'sh /mnt/scripts/install.sh' \
		--cmd 'df' \
		--expect 'HARNESS:DONE:0' \
		--log "$WORK/prepare.log" > /dev/null ||
		{ echo "prepare failed, see $WORK/prepare.log"; exit 1; }
	mv "$IMG.tmp" "$IMG"
	rm -rf "$WORK/payload"
	echo "== prepared"
}

if [ "${1:-}" = prepare ]; then prepare; exit 0; fi
stale && prepare

if [ -z "${NOVIEWER:-}" ]; then
	for v in gvncviewer vncviewer remmina; do
		command -v $v > /dev/null || continue
		case $v in
		remmina) arg=vnc://127.0.0.1:$((5900 + VNC)) ;;
		*) arg=127.0.0.1:$VNC ;;
		esac
		(sleep 2; exec $v $arg > /dev/null 2>&1) &
		break
	done
fi

cat <<EOF
== MINIX on VNC 127.0.0.1:$((5900 + VNC)) (display :$VNC); console below.
   Log in as root, run: start-hyprland     Quit: poweroff, or Ctrl-A x
EOF
snap=,snapshot=on; [ -n "${PERSIST:-}" ] && snap=
mods=$(cd "$BOOTDIR" && ls mod* | sort | tr '\n' ',' | sed 's/,$//')
cd "$BOOTDIR"
accel=tcg; [ -r /dev/kvm ] && [ -w /dev/kvm ] && accel=kvm
exec qemu-system-i386 -machine pc -accel $accel -m "$MEM" -vga std \
	-display none -vnc 127.0.0.1:$VNC -no-reboot \
	-serial mon:stdio \
	-kernel kernel -initrd "$mods" \
	-append "rootdevname=c0d0p0 console=tty00" \
	-drive "file=$IMG,format=raw,if=ide,index=0,media=disk$snap"
