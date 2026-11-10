#!/bin/sh
# test-perf.sh - Phase 8 performance probes (no pass/fail): softpipe cost of
# compositor operations (tests/glbench.c) and weston-simple-egl's fps in
# Hyprland, tiled (full-screen client) and as a 250x250 floating window.
# Prints the PERF/GLBENCH lines; log in tests/last-perf.log.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/../minix"
SR="$HERE/sysroot"
TC="$HERE/tc/bin/i586-elf32-minix"
WORK="$HERE/build/test-perf"
rm -rf "$WORK"; mkdir -p "$WORK/payload/bin"
"$HERE/stage-payload.sh" "$WORK/payload"
cp "$HERE"/tests/perf/*.sh "$WORK/payload/scripts/"
"$TC-gcc" --sysroot="$SR" -std=gnu99 -O2 -Wall -Wl,-z,noexecstack \
	${GLBENCH_CFLAGS:-} -I"$SR/usr/pkg/include" \
	-o "$WORK/payload/bin/glbench" "$HERE/tests/glbench.c" \
	-L"$SR/usr/pkg/lib" -lEGL -lGLESv2 -Wl,-rpath,/usr/pkg/lib
# SPROF=1: profile Hyprland and its clients (tests/sprof.c), results
# resolved by tests/sprof-report.py into tests/last-sprof.txt.
"$TC-gcc" --sysroot="$SR" -shared -fPIC -O1 -static-libgcc \
	-o "$WORK/payload/bin/sprof.so" "$HERE/tests/sprof.c"
"$REPO/releasetools/x86_qemu.py" ${IMAGE:+--image "$IMAGE"} \
	--payload "$WORK/payload" --timeout 1500 \
	--cmd 'cp -Rp /mnt/pkg/* /usr/pkg/ && echo installed' \
	--cmd 'unset LD_LIBRARY_PATH; /mnt/bin/glbench 1024 768 20' \
	--cmd 'unset LD_LIBRARY_PATH; /mnt/bin/glbench 250 250 100' \
	--cmd "${SPROF:+SPROF=1 }sh /mnt/scripts/hypr-fps.sh tiled" \
	--cmd 'sh /mnt/scripts/hypr-fps.sh float250 "windowrule = float,title:^(simple-egl)$" "windowrule = size 250 250,title:^(simple-egl)$"' \
	--log "$HERE/tests/last-perf.log" > /dev/null || true
grep -aE '^(GLBENCH|PERF)' "$HERE/tests/last-perf.log" | grep -v 'cmd\|HARNESS'
if [ -n "${SPROF:-}" ]; then
	rm -rf "$WORK/sprof"; mkdir -p "$WORK/sprof"
	awk -v d="$WORK/sprof" '{sub(/\r$/, "")} /^SPROFFILE /{f=d "/" substr($2, 6); next}
	    /^SPROFEND/{f=""; next} f && /^SPROF /{print > f}' \
	    "$HERE/tests/last-perf.log"
	python3 -I "$HERE/tests/sprof-report.py" --top=25 "$WORK"/sprof/sprof.* \
	    > "$HERE/tests/last-sprof.txt"
	echo "profile: tests/last-sprof.txt"
fi
