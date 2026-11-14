# netsurf: small graphical web browser (Phase 10), framebuffer frontend on
# a Wayland window.
VERSION=3.11
URL=https://download.netsurf-browser.org/netsurf/releases/source-full/netsurf-all-$VERSION.tar.gz
SRCNAME=netsurf-all-$VERSION
TARBALL=netsurf-all-$VERSION.tar.gz
# dangling "Messages" symlinks in the tarball (generated at build time)
REGEN_EXCLUDE="Messages"
NSLIBS="buildsystem libnslog libwapcaplet libparserutils libcss libhubbub
	libdom libnsbmp libnsgif librosprite libnsutils libutf8proc libnspsl
	libsvgtiny libnsfb"

ns_make() {	# <dir> <target...>
	_d=$1; shift
	# LDFLAGS from the environment (the makefiles append to it):
	# rpath-link for the libraries that shared ones need (libffi under
	# libwayland-client, libgcc_s under libssl)
	LDFLAGS="-L$SYSROOT$PREFIX/lib -Wl,-rpath,$PREFIX/lib -Wl,-rpath-link,$SYSROOT$PREFIX/lib -Wl,-z,noexecstack" \
	make -C "$BUILD/obj/$_d" -j"$(nproc)" HOST=i586-elf32-minix \
		BUILD="$(cc -dumpmachine)" PREFIX="$PREFIX" DESTDIR="$DESTDIR" \
		PKGCONFIG=i586-elf32-minix-pkg-config \
		PKG_CONFIG=i586-elf32-minix-pkg-config \
		NSSHARED="$BUILD/obj/buildsystem" Q= \
		BUILD_LIBPNG_CFLAGS="-I$HOST/include" \
		BUILD_LIBPNG_LDFLAGS="-L$HOST/lib -lpng16 -lz -lm" \
		WARNFLAGS='-Wall -W -Wno-error' "$@"
}
port_configure() {
	# in-tree build on a copy; -u: edits in src/ reach the copy
	mkdir -p "$BUILD/obj"
	cp -au "$SRC/." "$BUILD/obj/"
	_x="$HERE/rootfs/usr/pkg/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
	_d="$BUILD/obj/libnsfb/src/surface"
	[ -f "$_d/xdg-shell-protocol.c" ] || {
		wayland-scanner client-header "$_x" "$_d/xdg-shell-client-protocol.h"
		wayland-scanner private-code "$_x" "$_d/xdg-shell-protocol.c"
	}
}
port_build() {
	# host tool: the JavaScript binding generator
	[ -x "$HOST/bin/nsgenbind" ] ||
	    make -C "$BUILD/obj/nsgenbind" install HOST="$(cc -dumpmachine)" \
		PREFIX="$HOST" DESTDIR= NSSHARED="$BUILD/obj/buildsystem" Q=
	# host libpng (static) for netsurf's convert_image tool: the container
	# has no libpng headers; same tarball as the libpng port
	if [ ! -f "$HOST/lib/libpng16.a" ]; then
		_p=$(ls -d "$HERE"/src/libpng-*/ | head -1)
		[ -n "$_p" ] || { echo "build the libpng port first" >&2; exit 1; }
		mkdir -p "$BUILD/host-libpng"
		(cd "$BUILD/host-libpng" && "$_p/configure" --prefix="$HOST" \
			--disable-shared --disable-tests --disable-tools &&
		 make -j"$(nproc)" install)
	fi
	for l in $NSLIBS; do
		ns_make $l install COMPONENT_TYPE=lib-static
	done
	cat > "$BUILD/obj/netsurf/Makefile.config" <<CFG
override NETSURF_FB_FRONTEND := wl
override NETSURF_FB_FONTLIB := freetype
override NETSURF_FB_FONTPATH := $PREFIX/share/fonts/dejavu
override NETSURF_FB_FONT_SANS_SERIF_ITALIC := DejaVuSans.ttf
override NETSURF_FB_FONT_SANS_SERIF_ITALIC_BOLD := DejaVuSans-Bold.ttf
override NETSURF_FB_FONT_SERIF := DejaVuSans.ttf
override NETSURF_FB_FONT_SERIF_BOLD := DejaVuSans-Bold.ttf
override NETSURF_FB_FONT_CURSIVE := DejaVuSans.ttf
override NETSURF_FB_FONT_FANTASY := DejaVuSans-Bold.ttf
override NETSURF_USE_JPEG := YES
override NETSURF_USE_JPEGXL := NO
override NETSURF_USE_WEBP := NO
override NETSURF_USE_RSVG := NO
override NETSURF_USE_VIDEO := NO
override NETSURF_USE_LIBICONV_PLUG := YES
override NETSURF_USE_PNG := YES
override NETSURF_USE_CURL := YES
override NETSURF_USE_OPENSSL := YES
override NETSURF_USE_DUKTAPE := YES
CFG
	ns_make netsurf TARGET=framebuffer CC=i586-elf32-minix-gcc
}
port_install() {
	ns_make netsurf TARGET=framebuffer CC=i586-elf32-minix-gcc install
}
