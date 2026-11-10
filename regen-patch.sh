#!/bin/sh
# regen-patch.sh <name> <version> - rebuild patches/<name>-<version>-minix.patch
# from the edited tree src/<name>-<version> against a pristine extract of
# src/<name>-<version>.tar.* (paths a/ b/, as build-port.sh applies -p1).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
N=$1; V=$2
# The recipe may name the source dir and tarball differently (SRCNAME,
# TARBALL) and list trees to leave out (REGEN_EXCLUDE, diff -x patterns).
SRCNAME=; TARBALL=; REGEN_EXCLUDE=
[ -f "$HERE/ports/$N.sh" ] && . "$HERE/ports/$N.sh"
SRCNAME=${SRCNAME:-$N-$V}
TREE="$HERE/src/$SRCNAME"
if [ -n "$TARBALL" ]; then TARB="$HERE/src/$TARBALL"
else TARB=$(ls "$HERE/src/$N-$V".tar.* | head -1); fi
T=$(mktemp -d "$HERE/build/regen-XXXXXX")
trap 'rm -rf "$T"' EXIT
tar -C "$T" -xf "$TARB"
mv "$T/$SRCNAME" "$T/a"
ln -s "$TREE" "$T/b"
OUT="$HERE/patches/$N-$V-minix.patch"
X=
for x in $REGEN_EXCLUDE; do X="$X -x $x"; done
(cd "$T" && diff -ruN -x '*.orig' -x '*.rej' -x '__pycache__' -x '*.pyc' $X \
	a/ b/ > "$OUT.new") || [ $? -eq 1 ]
mv "$OUT.new" "$OUT"
grep '^+++' "$OUT" | awk '{print $2}'
