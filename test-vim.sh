#!/bin/sh
# test-vim.sh - Phase 10 gate: vim from the ports (tests/vim/vim.sh):
# scripted edits without a terminal, then vim in foot under Hyprland typed
# into through QEMU's keyboard.  Screendump (vim with syntax colours) in
# tests/last-vim.ppm.  IMAGE=<path> overrides the image.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
WORK="$HERE/build/test-vim"
SHOT="$HERE/tests/last-vim.ppm"
rm -rf "$WORK"
mkdir -p "$WORK/payload"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE/tests/vim/"*.sh "$WORK/payload/scripts/"
rm -f "$SHOT"
# G o "// ok" Esc
TEXT="sendkey shift-g; sendkey o; sendkey slash; sendkey slash; sendkey spc"
TEXT="$TEXT; sendkey o; sendkey k; sendkey esc"
QUIT="sendkey shift-semicolon; sendkey w; sendkey q; sendkey ret"
"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 1200 \
	--input "openterm=sendkey meta_l-ret" \
	--input "typetext=$TEXT" \
	--input "shot=screendump $SHOT" \
	--input "typequit=$QUIT" \
	--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd 'sh /mnt/scripts/vim.sh' \
	--expect 'VIM-OK' \
	--expect 'HARNESS:DONE:0' \
	--log "$HERE/tests/last-vim-gate.log" > /dev/null || rc=$?
grep -a '^VIM' "$HERE/tests/last-vim-gate.log" | tr -d '\r'
exit ${rc:-0}
