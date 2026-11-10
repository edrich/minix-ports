# libpng: PNG images (cairo, Weston clients, desktop-shell backgrounds).
VERSION=1.6.44
URL=https://download.sourceforge.net/libpng/libpng-$VERSION.tar.xz

port_configure() {
	autotools_configure --disable-static --disable-tests --disable-tools \
		--enable-hardware-optimizations=no
}
port_build() { autotools_build; }
port_install() { autotools_install; }
