# wayland: libwayland-client/-server/-cursor/-egl + wayland-scanner.
# Cross builds need a native wayland-scanner of the same version: built
# first from the same source into ../host.  MINIX specifics (patch):
# peer credentials via LOCAL_PEEREID, no strict _POSIX_C_SOURCE.  epoll,
# signalfd and timerfd come from MINIX libc (<sys/epoll.h> etc.).
VERSION=1.23.1
URL=https://gitlab.freedesktop.org/wayland/wayland/-/releases/$VERSION/downloads/wayland-$VERSION.tar.xz
MESON_OPTS="-Ddocumentation=false -Dtests=false -Ddtd_validation=false -Dscanner=false"
port_configure() {
	host_meson -Dlibraries=false -Ddocumentation=false -Dtests=false \
		-Ddtd_validation=false
	if [ ! -f "$BUILD/obj/build.ninja" ]; then
		meson setup "$BUILD/obj" "$SRC" \
			--cross-file "$BUILD/meson-minix.txt" \
			--prefix="$PREFIX" --libdir=lib --buildtype=release \
			-Dbuild.pkg_config_path="$HOST/lib/pkgconfig" \
			-Ddefault_library=shared $MESON_OPTS
	fi
}
