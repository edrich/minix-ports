# libevdev: evdev device wrapper library (libinput dependency).
# The MINIX patch maps the bundled kernel headers to FreeBSD's variant (BSD
# ioctl encoding, as on MINIX) and passes EVIOCGRAB's argument by pointer
# (see <minix/evdev.h>).  Also installs <linux/input.h> & co. into the
# prefix for other evdev users (mtdev), like FreeBSD's evdev-proto.
VERSION=1.13.3
URL=https://www.freedesktop.org/software/libevdev/libevdev-$VERSION.tar.xz
MESON_OPTS="-Dtests=disabled -Dtools=disabled -Ddocumentation=disabled"

port_install() {
	DESTDIR="$DESTDIR" ninja -C "$BUILD/obj" install
	_inc="$DESTDIR$PREFIX/include/linux"
	mkdir -p "$_inc"
	cp "$SRC/include/linux/freebsd/input-event-codes.h" "$_inc/"
	for _h in input.h uinput.h; do
		{
			echo "/* MINIX: Linux evdev ABI (<minix/evdev.h>), from libevdev's FreeBSD copy. */"
			echo "#include <sys/ioccom.h>"
			echo "#ifndef _IOWINT	/* MINIX: int arguments by pointer */"
			echo "#define _IOWINT(g, n)	_IOW(g, n, int)"
			echo "#endif"
			cat "$SRC/include/linux/freebsd/$_h"
		} > "$_inc/$_h"
	done
}
