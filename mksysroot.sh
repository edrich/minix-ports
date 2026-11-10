#!/bin/sh
# mksysroot.sh - (re)create the merged cross sysroot for ports.
#
#   sysroot/            symlinks into the MINIX OS destdir (headers, libc...)
#   sysroot/usr/pkg  -> rootfs/usr/pkg   (ports install here, guest prefix
#                                         /usr/pkg as with pkgsrc)
#
# Ports are compiled with --sysroot=sysroot so that both the OS and already
# built ports are visible under their guest paths.  They cannot be installed
# into the OS destdir itself: build.sh's release flist check rejects files
# that are not in distrib/sets/lists.
#
# Env: MINIX_SYSROOT (default ../obj.docker.i386/destdir.i386)

set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OS=${MINIX_SYSROOT:-$HERE/../obj.docker.i386/destdir.i386}
OS=$(cd "$OS" && pwd)
SR="$HERE/sysroot"
RFS="$HERE/rootfs"

mkdir -p "$RFS/usr/pkg"
rm -rf "$SR"
mkdir -p "$SR/usr"

for e in "$OS"/*; do
	n=$(basename "$e")
	case "$n" in usr|METALOG*|SETS.*) continue ;; esac
	ln -s "$e" "$SR/$n"
done
for e in "$OS"/usr/*; do
	n=$(basename "$e")
	[ "$n" = pkg ] && continue
	ln -s "$e" "$SR/usr/$n"
done
ln -s "$RFS/usr/pkg" "$SR/usr/pkg"
echo "sysroot: $SR (OS: $OS, ports: $RFS/usr/pkg)"
