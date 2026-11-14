# libjpeg-turbo: JPEG decoding for the netsurf port (Phase 10).  First
# cmake port: cross/cmake-minix.cmake.  Static library only (cmake has no
# shared-library rules for the "Minix" system name), no SIMD (needs nasm),
# no turbojpeg API, no tools.
VERSION=3.0.4
URL=https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$VERSION/libjpeg-turbo-$VERSION.tar.gz

port_configure() {
	if [ ! -f "$BUILD/obj/build.ninja" ]; then
		cmake -G Ninja -S "$SRC" -B "$BUILD/obj" \
			-DCMAKE_TOOLCHAIN_FILE="$HERE/cross/cmake-minix.cmake" \
			-DCMAKE_INSTALL_PREFIX="$PREFIX" \
			-DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_BUILD_TYPE=Release \
			-DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_SIMD=OFF \
			-DWITH_TURBOJPEG=OFF -DWITH_JAVA=OFF
	fi
}
port_build() { ninja -C "$BUILD/obj" jpeg-static; }
port_install() {
	# only the library and its headers (the install target wants the
	# tools as well)
	mkdir -p "$DESTDIR$PREFIX/lib" "$DESTDIR$PREFIX/include"
	cp "$BUILD/obj/libjpeg.a" "$DESTDIR$PREFIX/lib/"
	cp "$SRC/jpeglib.h" "$SRC/jmorecfg.h" "$SRC/jerror.h" \
	    "$BUILD/obj/jconfig.h" "$DESTDIR$PREFIX/include/"
}
