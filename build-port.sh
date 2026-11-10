#!/bin/sh
# build-port.sh - cross-build one port into rootfs/usr/pkg (guest /usr/pkg).
#
#   ./build-port.sh <name> [clean]
#
# Recipe: ports/<name>.sh sets
#   VERSION, URL (tarball), optional SRCNAME (dir inside the tarball,
#   default <name>-<VERSION>), TARBALL (local file name, default the URL's
#   basename), MESON_OPTS (meson -D... options), EXTRA_CFLAGS (extra
#   compiler flags, e.g. -march=pentium4 -mfpmath=sse),
#   and may override port_configure / port_build / port_install.
#   A recipe with LOCAL=yes and no URL builds MINIX-specific code kept in
#   local/<name>/ (no download, no patch).
# Patch: patches/<name>-<VERSION>-minix.patch (patch -p1), applied once
# when the source is first extracted into src/.
#
# Run inside the minix-dev container (docker/dev.sh); requires the
# toolchain (build-toolchain.sh) and the sysroot (mksysroot.sh, done
# automatically when missing).

set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
NAME=${1:?usage: build-port.sh <name> [clean]}
RECIPE="$HERE/ports/$NAME.sh"
[ -f "$RECIPE" ] || { echo "no recipe $RECIPE" >&2; exit 1; }

TC="$HERE/tc/bin"
HOST="$HERE/host"		# native build tools (e.g. wayland-scanner)
SYSROOT="$HERE/sysroot"
DESTDIR="$HERE/rootfs"
PREFIX=/usr/pkg
export PATH="$HOST/bin:$TC:$PATH"

[ -d "$SYSROOT/usr" ] || "$HERE/mksysroot.sh"

SRCNAME=
TARBALL=
LOCAL=
URL=
MESON_OPTS=
EXTRA_CFLAGS=
. "$RECIPE"
SRCNAME=${SRCNAME:-$NAME-$VERSION}
SRC="$HERE/src/$SRCNAME"
[ "$LOCAL" = yes ] && SRC="$HERE/local/$NAME"
BUILD="$HERE/build/$NAME"

if [ "${2:-}" = clean ]; then
	rm -rf "$BUILD"
fi

# Fetch + extract + patch.
if [ "$LOCAL" != yes ]; then
TARBALL="$HERE/src/${TARBALL:-$(basename "$URL")}"
[ -f "$TARBALL" ] || curl -sSfL -o "$TARBALL" "$URL"
fi
if [ ! -d "$SRC" ]; then
	tar -C "$HERE/src" -xf "$TARBALL"
	P="$HERE/patches/$NAME-$VERSION-minix.patch"
	if [ -f "$P" ]; then
		(cd "$SRC" && patch -p1 < "$P")
	fi
fi

mkdir -p "$BUILD"
sed -e "s|@SYSROOT@|$SYSROOT|g" -e "s|@TC@|$TC|g" \
	"$HERE/cross/meson-minix.txt.in" > "$BUILD/meson-minix.txt"
# EXTRA_CFLAGS (recipe): extra C/C++ compiler flags, e.g. code generation
# options, appended to c_args/cpp_args of the cross file.  Changing them
# needs "build-port.sh <name> clean" (meson keeps the configured values).
if [ -n "${EXTRA_CFLAGS:-}" ]; then
	_x=
	for _f in $EXTRA_CFLAGS; do _x="$_x, '$_f'"; done
	sed -i -e "s|^c_args = \['--sysroot=$SYSROOT'|c_args = ['--sysroot=$SYSROOT'$_x|" \
	    -e "s|^cpp_args = \['--sysroot=$SYSROOT'|cpp_args = ['--sysroot=$SYSROOT'$_x|" \
	    "$BUILD/meson-minix.txt"
fi

# Native (build machine) meson build+install into $HOST, for tools that
# cross builds need to run, e.g. host_meson <dir> [-Doption...].
host_meson() {
	_b="$BUILD/native"
	if [ ! -f "$_b/build.ninja" ]; then
		meson setup "$_b" "$SRC" --prefix="$HOST" --libdir=lib \
			--buildtype=release "$@"
	fi
	ninja -C "$_b" install
}

# GNU autotools (configure script in the tarball).
autotools_configure() {
	if [ ! -f "$BUILD/obj/Makefile" ]; then
		mkdir -p "$BUILD/obj"
		(cd "$BUILD/obj" && "$SRC/configure" \
			--host=i586-elf32-minix --build="$(cc -dumpmachine)" \
			--prefix="$PREFIX" --libdir="$PREFIX/lib" \
			CC="i586-elf32-minix-gcc --sysroot=$SYSROOT" \
			CXX="i586-elf32-minix-g++ --sysroot=$SYSROOT" \
			CPPFLAGS="-I$SYSROOT$PREFIX/include" \
			LDFLAGS="-L$SYSROOT$PREFIX/lib -Wl,-rpath,$PREFIX/lib -Wl,-z,noexecstack" \
			PKG_CONFIG=i586-elf32-minix-pkg-config \
			"$@")
		fix_libtool "$BUILD/obj/libtool"
	fi
}

# libtool does not know that MINIX has ELF shared libraries (host_os
# "minix" -> build_libtool_libs=no, i.e. static only).  Its link commands
# are already the GNU ld ones; fill in the platform section of the
# generated script with the usual ELF values (as for Linux/NetBSD).
fix_libtool() {
	[ -f "$1" ] || return 0
	sed -i \
		-e 's/^build_libtool_libs=no$/build_libtool_libs=yes/' \
		-e 's/^deplibs_check_method=.*/deplibs_check_method="pass_all"/' \
		-e 's/^version_type=.*/version_type=linux/' \
		-e 's/^need_lib_prefix=.*/need_lib_prefix=no/' \
		-e 's/^need_version=.*/need_version=no/' \
		-e 's/^library_names_spec=.*/library_names_spec="\\$libname\\$release\\$shared_ext\\$versuffix \\$libname\\$release\\$shared_ext\\$major \\$libname\\$shared_ext"/' \
		-e 's/^soname_spec=.*/soname_spec="\\$libname\\$release\\$shared_ext\\$major"/' \
		-e 's/^shlibpath_var=.*/shlibpath_var=LD_LIBRARY_PATH/' \
		-e 's/^dynamic_linker=.*/dynamic_linker="MINIX ld.elf_so"/' \
		-e 's/^link_all_deplibs=unknown$/link_all_deplibs=no/' \
		"$1"
}
autotools_build() {
	make -C "$BUILD/obj" -j"$(nproc)"
}
autotools_install() {
	make -C "$BUILD/obj" install DESTDIR="$DESTDIR"
	# libtool archives carry absolute paths into the guest prefix; they
	# only confuse later cross links.
	find "$DESTDIR$PREFIX/lib" -name '*.la' -delete
}

port_configure() {
	if [ ! -f "$BUILD/obj/build.ninja" ]; then
		meson setup "$BUILD/obj" "$SRC" \
			--cross-file "$BUILD/meson-minix.txt" \
			--prefix="$PREFIX" --libdir=lib --buildtype=release \
			-Dbuild.pkg_config_path="$HOST/lib/pkgconfig" \
			-Ddefault_library=shared $MESON_OPTS
	fi
}
port_build() {
	ninja -C "$BUILD/obj"
}
port_install() {
	DESTDIR="$DESTDIR" ninja -C "$BUILD/obj" install
}

# Recipes may redefine the functions above; re-source to apply overrides.
. "$RECIPE"

port_configure
port_build
port_install
echo "build-port: $NAME $VERSION installed into $DESTDIR$PREFIX"
