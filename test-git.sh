#!/bin/sh
# test-git.sh - Phase 10 gate: git from the ports in MINIX
# (tests/git/git.sh): local repository work, then curl and git over https
# against a public repository through QEMU user-mode networking (harness
# --net: e1000, DHCP in the guest).  NONET=1 skips the network part;
# REMOTE=<url> TAG=<tag> choose the repository (default zlib, v1.3.1).
# IMAGE=<path> overrides the image.  Needs network access on the host.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-git"
REMOTE=${REMOTE:-https://github.com/madler/zlib.git}
TAG=${TAG:-v1.3.1}
rm -rf "$WORK"
mkdir -p "$WORK/payload"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE/tests/git/"*.sh "$WORK/payload/scripts/"
net=--net
if [ "${NONET:-0}" = 1 ]; then
	net=
else
	# what the tag points at, as seen from the host
	git ls-remote "$REMOTE" "refs/tags/$TAG^{}" | awk '{print $1}' \
	    > "$WORK/payload/expect-tag"
	[ -s "$WORK/payload/expect-tag" ] ||
	    { echo "cannot reach $REMOTE from the host" >&2; exit 1; }
fi
"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} $net \
	--payload "$WORK/payload" --timeout 1800 \
	--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd "NONET=${NONET:-0} REMOTE=$REMOTE TAG=$TAG sh /mnt/scripts/git.sh" \
	--expect 'GIT-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-git-gate.log" > /dev/null || rc=$?
grep -a '^GIT' "$HERE/tests/last-git-gate.log" | tr -d '\r'
exit ${rc:-0}
