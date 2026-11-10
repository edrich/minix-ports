# Hyprland v0.22.0beta (PLAN.md Phase 8: the newest wlroots-era release that
# needs no pango/udis86/hyprlang).  Built with its wlroots submodule as a
# static meson subproject - the same commit as ports/wlroots.sh, with that
# port's MINIX patch - and hyprland-protocols 301733ae.  No XWayland, no
# systemd.  Runtime: see tests/hyprland/hyprland.sh for the environment.
VERSION=0.22.0beta
URL=https://github.com/hyprwm/Hyprland/archive/refs/tags/v$VERSION.tar.gz
TARBALL=Hyprland-$VERSION.tar.gz
SRCNAME=Hyprland-$VERSION
# The submodules live in their own tarballs (regen-patch.sh skips them).
REGEN_EXCLUDE="wlroots hyprland-protocols"
WLR_VER=677a3f2f8847ed2de49dd60868f9d9487a546f58
HPROTO_VER=301733ae466b229066ba15a53e6d8b91c5dcef5b
HPROTO_URL=https://github.com/hyprwm/hyprland-protocols/archive/$HPROTO_VER.tar.gz
MESON_OPTS="-Dxwayland=disabled -Dsystemd=disabled -Dwlroots:backends=drm,libinput -Dwlroots:renderers=gles2 -Dwlroots:allocators=gbm -Dwlroots:session=enabled -Dwlroots:xwayland=disabled -Dwlroots:xcb-errors=disabled -Dwlroots:werror=false"

# Fill subprojects/ (empty in GitHub's tag tarball).
populate_subprojects() {
	sp="$SRC/subprojects"
	if [ ! -f "$sp/wlroots/meson.build" ]; then
		wt="$HERE/src/wlroots-$WLR_VER.tar.gz"
		[ -f "$wt" ] || curl -sSfL -o "$wt" \
		    "https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/$WLR_VER/wlroots-$WLR_VER.tar.gz"
		rm -rf "$sp/wlroots"
		tar -C "$sp" -xf "$wt"
		mv "$sp/wlroots-$WLR_VER" "$sp/wlroots"
		(cd "$sp/wlroots" && patch -s -p1 < "$HERE/patches/wlroots-$WLR_VER-minix.patch")
	fi
	if [ ! -f "$sp/hyprland-protocols/meson.build" ]; then
		ht="$HERE/src/hyprland-protocols-$HPROTO_VER.tar.gz"
		[ -f "$ht" ] || curl -sSfL -o "$ht" "$HPROTO_URL"
		rm -rf "$sp/hyprland-protocols"
		tar -C "$sp" -xf "$ht"
		mv "$sp/hyprland-protocols-$HPROTO_VER" "$sp/hyprland-protocols"
	fi
}

# Hyprland links wlroots statically (its default_library): no shared default.
port_configure() {
	populate_subprojects
	if [ ! -f "$BUILD/obj/build.ninja" ]; then
		meson setup "$BUILD/obj" "$SRC" \
			--cross-file "$BUILD/meson-minix.txt" \
			--prefix="$PREFIX" --libdir=lib --buildtype=release \
			-Dbuild.pkg_config_path="$HOST/lib/pkgconfig" \
			-Ddefault_library=static \
			--force-fallback-for=hyprland-protocols $MESON_OPTS
	fi
}

# Only Hyprland itself: the static wlroots and the protocol XML/.pc of the
# subprojects are build-time only (an installed hyprland-protocols.pc
# without its XML broke the next configure).
port_install() {
	DESTDIR="$DESTDIR" meson install -C "$BUILD/obj" --skip-subprojects
}
