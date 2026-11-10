# os-pc: pkg-config files for the OS's own expat and zlib (local/os-pc).
LOCAL=yes
VERSION=1

port_configure() { :; }
port_build() { :; }
port_install() {
	_pc="$DESTDIR$PREFIX/lib/pkgconfig"
	mkdir -p "$_pc"
	cat > "$_pc/expat.pc" <<'PC'
prefix=/usr
libdir=${prefix}/lib
includedir=${prefix}/include

Name: expat
Description: expat XML parser (MINIX base system)
Version: 2.1.0
Libs: -L${libdir} -lexpat
Cflags: -I${includedir}
PC
	cat > "$_pc/zlib.pc" <<'PC'
prefix=/usr
libdir=${prefix}/lib
includedir=${prefix}/include

Name: zlib
Description: zlib compression library (MINIX base system)
Version: 1.2.3
Libs: -L${libdir} -lz
Cflags: -I${includedir}
PC
}
