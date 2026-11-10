# mtdev: multitouch protocol translation (libinput dependency; a no-op for
# MINIX' keyboard and mouse).  Needs <linux/input.h> from the libevdev port.
VERSION=1.1.7
URL=https://bitmath.org/code/mtdev/mtdev-$VERSION.tar.bz2

port_configure() {
	autotools_configure --disable-static
}
port_build() {
	make -C "$BUILD/obj/src" -j"$(nproc)"
}
port_install() {
	make -C "$BUILD/obj/src" install DESTDIR="$DESTDIR"
	make -C "$BUILD/obj" install-pkgconfigDATA DESTDIR="$DESTDIR"
	find "$DESTDIR$PREFIX/lib" -name '*.la' -delete
}
