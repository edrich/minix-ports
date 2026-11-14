# openssl: TLS for curl/git (Phase 10).  The base system's OpenSSL is
# 1.0.1p (2015): too old for current curl and for today's servers.  3.5 is
# the LTS series.  Installed next to the base one: /usr/pkg/lib/libssl.so.3
# (base: /usr/lib/libssl.so.10), headers in /usr/pkg/include, which the
# ports' -I/-L order puts before the base ones.
# no-threads/no-async: libmthread is cooperative, no ucontext switching
# wanted; no-secure-memory: no mlock; no-dgram (so no DTLS/QUIC): MINIX has
# IP_PKTINFO without ipi_spec_dst.  Configuration dir /usr/pkg/etc/ssl
# (cert.pem there comes from the curl port).
VERSION=3.5.4
URL=https://github.com/openssl/openssl/releases/download/openssl-$VERSION/openssl-$VERSION.tar.gz

port_configure() {
	if [ ! -f "$BUILD/obj/Makefile" ]; then
		mkdir -p "$BUILD/obj"
		(cd "$BUILD/obj" && CC=gcc perl "$SRC/Configure" BSD-x86-elf \
			--cross-compile-prefix=i586-elf32-minix- \
			--prefix="$PREFIX" --libdir=lib \
			--openssldir="$PREFIX/etc/ssl" \
			shared no-threads no-async no-secure-memory no-tests \
			no-docs no-engine no-afalgeng no-dgram no-ui-console \
			--sysroot="$SYSROOT" \
			-Wl,-rpath,"$PREFIX/lib" -Wl,-z,noexecstack)
	fi
}
port_build() { make -C "$BUILD/obj" -j"$(nproc)"; }
port_install() {
	make -C "$BUILD/obj" install_sw install_ssldirs DESTDIR="$DESTDIR"
}
