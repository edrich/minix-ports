# libffi: needed by libwayland-client/-server (marshalling of requests).
VERSION=3.4.6
URL=https://github.com/libffi/libffi/releases/download/v$VERSION/libffi-$VERSION.tar.gz
port_configure() {
	autotools_configure --disable-docs --disable-multi-os-directory \
		--enable-shared --disable-static --disable-exec-static-tramp
}
port_build() { autotools_build; }
port_install() { autotools_install; }
