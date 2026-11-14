#!/bin/sh
# vim.sh - Phase 10 gate, run in the guest by test-vim.sh: vim from the
# ports (ports/vim.sh).
#   scripted  (no terminal: vim -es) features, substitute + write, Vim
#             script, normal-mode commands, runtime files (filetype
#             detection, syntax), xxd round trip, vim as git's editor
#   terminal  Hyprland; SUPER+Return opens "foot vim -u DEFAULTS vt.c"; the
#             harness types  G o // ok <Esc>  (HARNESS:INPUT:typetext),
#             takes a screendump (shot) and types  :wq <Return>  (typequit):
#             the file must have the new line and vim/foot must be gone.
# Prints VIM-OK.
unset LD_LIBRARY_PATH
ulimit -c 0
PATH=/usr/pkg/bin:$PATH; export PATH
W=/tmp/vimwork; rm -rf $W; mkdir -p $W; cd $W
fails=0
ok() { echo "VIM: ok   $1"; }
bad() { echo "VIM: FAIL $1"; fails=$((fails+1)); }
is() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: got '$2', want '$3'"; fi; }
V="vim -u NONE -i NONE -es"

echo "== scripted"
vim --version > ver.txt 2>&1 || bad "vim --version"
head -2 ver.txt
is "huge build" "$(grep -c '^Huge version' ver.txt)" 1
for f in +syntax +eval +multi_byte +terminfo +visual +folding; do
	grep -q -- "$f" ver.txt && ok "feature $f" || bad "feature $f"
done
printf 'one\ntwo\nthree\n' > a.txt
$V -c '%s/t\(\w\)/T\1/' -c 'wq' a.txt
is "substitute + write" "$(tr '\n' ' ' < a.txt)" "one Two Three "
$V -c 'call writefile([string(6*7), string(has("syntax")), toupper("minix"), join(sort(["c","a","b"]), "")], "s.out")' -c 'q'
is "vim script" "$(tr '\n' ' ' < s.out)" "42 1 MINIX abc "
$V -c 'normal ggddGp' -c 'normal ggA!' -c 'wq' a.txt
is "normal mode commands" "$(tr '\n' ' ' < a.txt)" "Two! Three one "
printf '#include <stdio.h>\nint main(void) { return 0; }\n' > x.c
$V -c 'filetype on' -c 'syntax on' -c 'e x.c' \
    -c 'call writefile([&filetype, exists("b:current_syntax") ? b:current_syntax : "none", synIDattr(synID(2, 1, 1), "name")], "ft.out")' -c 'q'
is "runtime: filetype, syntax" "$(tr '\n' ' ' < ft.out)" "c c cType "
$V -c 'set encoding=utf-8' -c 'e u.txt' -c 'call setline(1, "grüße €")' -c 'call writefile([string(strchars(getline(1))), string(strlen(getline(1)))], "u.out")' -c 'wq'
is "utf-8 text (chars bytes)" "$(tr '\n' ' ' < u.out)" "7 11 "
xxd a.txt > a.hex && xxd -r a.hex > a.back && cmp -s a.txt a.back &&
    ok "xxd round trip" || bad "xxd round trip"
if command -v git > /dev/null; then
	export HOME=$W/home; mkdir -p $HOME
	git config --global user.name T; git config --global user.email t@minix.invalid
	git init -q r && cd r && echo x > f && git add f &&
	    GIT_EDITOR="vim -u NONE -i NONE -es -c 'call append(0, \"from vim\")' -c wq" git commit -q 2> /dev/null
	is "vim as git's editor" "$(git log -1 --format=%s 2>/dev/null)" "from vim"
	cd $W
fi

echo "== terminal"
export XDG_RUNTIME_DIR=/tmp/xdg HOME=/tmp/hyprhome
rm -rf $XDG_RUNTIME_DIR $HOME /tmp/hypr; mkdir -m 700 $XDG_RUNTIME_DIR
mkdir -p $HOME/.config/hypr
export LANG=en_US.UTF-8
export WLR_RENDERER_ALLOW_SOFTWARE=1 WLR_DRM_NO_ATOMIC=1 \
	WLR_DRM_NO_MODIFIERS=1 WLR_DRM_DEVICES=/dev/drm0
CONF=$HOME/.config/hypr/hyprland.conf
LOG=/tmp/hyprland.out
FLOG=/tmp/foot.log
cat > $W/vt.c <<'SRC'
#include <stdio.h>

/* edited by vim in foot under Hyprland on MINIX */
int
main(int argc, char **argv)
{
	const char *who = argc > 1 ? argv[1] : "world";

	printf("hello, %s: %d\n", who, 42);
	return 0;
}
SRC
cat > $CONF <<CFG
monitor=,preferred,auto,1
general {
    gaps_in = 4
    gaps_out = 8
    border_size = 3
    col.active_border = rgba(ffcc00ff)
}
decoration {
    rounding = 0
    blur = false
    drop_shadow = false
}
animations {
    enabled = false
}
misc {
    disable_hyprland_logo = true
    disable_splash_rendering = true
}
bind = SUPER, Return, exec, /usr/pkg/bin/foot /usr/pkg/bin/vim -u DEFAULTS -i NONE $W/vt.c > $FLOG 2>&1
CFG
stop() {
	kill -$2 $1 2>/dev/null
	n=0
	while kill -0 $1 2>/dev/null && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
	kill -0 $1 2>/dev/null && { echo "VIM: pid $1 ignored SIG$2, killing"; kill -9 $1; }
}
/usr/pkg/bin/Hyprland --i-am-really-stupid -c $CONF > $LOG 2>&1 &
H=$!
sock() { ls $XDG_RUNTIME_DIR 2>/dev/null | grep '^wayland-[0-9]*$' | head -1; }
i=0
while [ -z "$(sock)" ] && [ $i -lt 90 ] && kill -0 $H 2>/dev/null; do
	sleep 1; i=$((i+1))
done
[ -n "$(sock)" ] || { echo "VIM: no Hyprland socket"; tail -40 $LOG; exit 1; }
sleep 5
SIG=$(ls /tmp/hypr | head -1)
hc() { HYPRLAND_INSTANCE_SIGNATURE=$SIG /usr/pkg/bin/hyprctl "$@"; }
vimpid() { ps ax | grep '[/]usr/pkg/bin/vim -u DEFAULTS' | grep -v foot | awk '{print $1}' | head -1; }
echo; echo HARNESS:INPUT:openterm
i=0
while { ! hc clients 2>/dev/null | grep -q 'class: foot' || [ -z "$(vimpid)" ]; } &&
    [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done
hc clients | grep -q 'class: foot' && ok "foot window" || bad "foot window"
[ -n "$(vimpid)" ] && ok "vim runs in foot" || bad "vim runs in foot"
sleep 6
echo; echo HARNESS:INPUT:typetext; sleep 8
echo; echo HARNESS:INPUT:shot; sleep 4
[ -n "$(vimpid)" ] && ok "vim still running after typing" || bad "vim died while typing"
echo; echo HARNESS:INPUT:typequit
i=0
while [ -n "$(vimpid)" ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
[ -z "$(vimpid)" ] && ok ":wq ended vim" || bad ":wq ended vim"
is "typed line saved" "$(grep -c '^// ok$' $W/vt.c)" 1
is "line count" "$(wc -l < $W/vt.c | tr -d ' ')" 12
# foot leaves when its client has exited: SIGCHLD seen by its event loop
# (epoll_pwait with the signal pending, minix test98 subtest 8)
i=0
while hc clients | grep -q 'class: foot' && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
hc clients | grep -q 'class: foot' && bad "foot closed with vim" || ok "foot closed with vim"
alive=0; kill -0 $H 2>/dev/null && alive=1
is "Hyprland alive" $alive 1
F=$(ps ax | grep '[/]usr/pkg/bin/foot' | awk '{print $1}' | head -1)
[ -n "$F" ] && stop $F TERM
stop $H TERM
echo "== foot log"; grep -v '^$' $FLOG | head -20
echo "== Hyprland log (errors)"; grep -aE 'ERR|CRIT' $LOG | head -10
echo "VIM: fails=$fails"
[ $fails = 0 ] && echo VIM-OK
