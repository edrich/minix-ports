#!/bin/sh
# stage-payload.sh <dir> - copy the runtime part of the ports tree (no
# headers, pkg-config files or static libraries; ELF files stripped) into
# <dir>/pkg, plus tests/weston/*.sh into <dir>/scripts, for the QEMU
# harness payload disk.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
D=$1
rm -rf "$D/pkg" "$D/scripts"
mkdir -p "$D/pkg" "$D/scripts"
for sub in bin libexec lib share etc; do
	# -a keeps hard links (Mesa's DRI drivers are one file, several names)
	[ -d "$HERE/rootfs/usr/pkg/$sub" ] && cp -a "$HERE/rootfs/usr/pkg/$sub" "$D/pkg/"
done
rm -rf "$D/pkg/lib/pkgconfig" "$D/pkg/share/pkgconfig" "$D/pkg/share/doc" \
	"$D/pkg/share/man" "$D/pkg/share/aclocal" "$D/pkg/share/gettext"
find "$D/pkg/lib" -name '*.a' -delete
# Strip the copies (rootfs keeps the symbols for addr2line).
find "$D/pkg" -type f \( -perm -u+x -o -name '*.so*' \) | while read -r f; do
	head -c 4 "$f" | grep -q 'ELF' && \
	    "$HERE/tc/bin/i586-elf32-minix-strip" --strip-unneeded "$f" 2>/dev/null || true
done
cp "$HERE"/tests/weston/*.sh "$D/scripts/"
