# links: text-mode web browser for the terminal (Phase 10).  https through
# the openssl port (CA file /usr/pkg/etc/ssl/cert.pem from the curl port),
# gzip through zlib.  No graphics mode (its drivers are X, framebuffer,
# SVGAlib, DirectFB - none on MINIX; the graphical browser is a separate
# port), no gpm, no libevent (select loop), no brotli/zstd/lzma.
VERSION=2.30
URL=http://links.twibright.com/download/links-$VERSION.tar.bz2

# Its configure is autoconf 2.13: no VAR=value arguments (the compiler goes
# into the environment), and tests that run programs need answers when
# cross compiling.
port_configure() {
	if [ ! -f "$BUILD/obj/Makefile" ]; then
		mkdir -p "$BUILD/obj"
		(cd "$BUILD/obj" && \
		CC="i586-elf32-minix-gcc --sysroot=$SYSROOT" \
		CPPFLAGS="-I$SYSROOT$PREFIX/include" \
		LDFLAGS="-L$SYSROOT$PREFIX/lib -Wl,-rpath,$PREFIX/lib -Wl,-z,noexecstack" \
		ac_cv_sizeof_unsigned_long=4 ac_cv_sizeof_unsigned_long_long=8 \
		ac_cv_c_bigendian=no \
		"$SRC/configure" --host=i586-elf32-minix \
			--prefix="$PREFIX" --with-ssl --with-zlib \
			--disable-graphics --without-x --without-fb \
			--without-directfb --without-svgalib --without-gpm \
			--without-libevent --without-brotli --without-zstd \
			--without-lzma --without-bzip2 --without-lzip \
			--without-openmp)
	fi
}
port_build() { autotools_build; }
port_install() { autotools_install; }
