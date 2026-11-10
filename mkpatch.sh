#!/bin/sh
# mkpatch.sh <name> <version> - regenerate patches/<name>-<version>-minix.patch
# from the edited tree src/<name>-<version> against a pristine extract of
# src/<tarball>, and verify that the patch reproduces the tree.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
N=$1 V=$2
TB=$(ls "$HERE"/src/$N-$V.tar.* | head -1)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
tar -C "$T" -xf "$TB"
mv "$T/$N-$V" "$T/a"
ln -s "$HERE/src/$N-$V" "$T/b"
(cd "$T" && diff -ruN -x '*.orig' -x '*.rej' a b/ || true) | sed 's|^+++ b//|+++ b/|' \
	> "$HERE/patches/$N-$V-minix.patch"
mkdir "$T/chk" && tar -C "$T/chk" -xf "$TB"
(cd "$T/chk/$N-$V" && patch -s -p1 < "$HERE/patches/$N-$V-minix.patch")
diff -r -x '*.orig' -x '*.rej' "$T/chk/$N-$V" "$HERE/src/$N-$V" >/dev/null
echo "patches/$N-$V-minix.patch: $(grep -c '^+++ ' "$HERE/patches/$N-$V-minix.patch") files, verified"
