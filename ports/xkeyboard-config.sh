# xkeyboard-config: the XKB keyboard database (data only).  Architecture
# independent, so it is built with the native meson setup and installed into
# the ports rootfs.
VERSION=2.43
URL=https://www.x.org/releases/individual/data/xkeyboard-config/xkeyboard-config-$VERSION.tar.xz
port_configure() {
	if [ ! -f "$BUILD/obj/build.ninja" ]; then
		meson setup "$BUILD/obj" "$SRC" --prefix="$PREFIX" \
			-Dnls=false -Dcompat-rules=true \
			-Dxorg-rules-symlinks=false
	fi
}
