# zlib: the base system's is 1.2.3 (2005); curl needs >= 1.2.5.2 and git
# wants a current one too (Phase 10).  /usr/pkg/lib/libz.so.1 shadows the
# base /usr/lib/libz.so.1 for the ports only (RPATH /usr/pkg/lib).
VERSION=1.3.1
URL=https://github.com/madler/zlib/releases/download/v$VERSION/zlib-$VERSION.tar.xz

port_configure() {
	if [ ! -f "$BUILD/obj/Makefile" ]; then
		mkdir -p "$BUILD/obj"
		(cd "$BUILD/obj" && CHOST=i586-elf32-minix \
			CC="i586-elf32-minix-gcc --sysroot=$SYSROOT" \
			LDSHARED="i586-elf32-minix-gcc --sysroot=$SYSROOT -shared -Wl,-soname,libz.so.1 -Wl,-z,noexecstack" \
			"$SRC/configure" --prefix="$PREFIX")
	fi
}
port_build() { make -C "$BUILD/obj" -j"$(nproc)"; }
port_install() { make -C "$BUILD/obj" install DESTDIR="$DESTDIR"; }
