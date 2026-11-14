# curl: HTTP(S) client and libcurl, for git's https transport (Phase 10).
# TLS: the openssl port.  CA bundle: Mozilla's, as published by the curl
# project, installed as /usr/pkg/etc/ssl/cert.pem (OpenSSL's default file
# too).  No threaded resolver (cooperative threads); no optional
# compression/HTTP2/IDN libraries.  Static libcurl: curl's configure decides
# for itself that MINIX has no shared libraries (Makefile conditionals, not
# just the libtool script that build-port.sh fixes up).
VERSION=8.17.0
URL=https://curl.se/download/curl-$VERSION.tar.xz
CA_URL=https://curl.se/ca/cacert.pem

port_configure() {
	autotools_configure --disable-shared --with-openssl --with-zlib \
		--with-ca-bundle="$PREFIX/etc/ssl/cert.pem" \
		--without-ca-path --disable-threaded-resolver \
		--disable-docs --disable-manual --disable-ldap --disable-ldaps \
		--without-libpsl --without-brotli --without-zstd \
		--without-nghttp2 --without-libidn2 --without-librtmp \
		--without-libssh2 --disable-ntlm
	# static only: undo fix_libtool's "MINIX has shared libraries"
	sed -i 's/^build_libtool_libs=yes$/build_libtool_libs=no/' \
	    "$BUILD/obj/libtool"
}
port_build() { autotools_build; }
port_install() {
	autotools_install
	[ -f "$HERE/src/cacert.pem" ] ||
	    curl -sSfL -o "$HERE/src/cacert.pem" "$CA_URL"
	mkdir -p "$DESTDIR$PREFIX/etc/ssl"
	cp "$HERE/src/cacert.pem" "$DESTDIR$PREFIX/etc/ssl/cert.pem"
}
