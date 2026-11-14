#!/bin/sh
# links.sh - Phase 10 gate, run in the guest by test-links.sh: the links
# text browser from the ports (ports/links.sh).
#   dump      a local HTML file (headings, list, table, entities) rendered
#             to text; over the network (DHCP on em0): http and https
#             pages, an expired certificate refused
#   terminal  Hyprland; SUPER+Return opens "foot links <https url>"; the
#             harness presses Return (HARNESS:INPUT:welcome: the first-run
#             "Welcome to links" box), takes a screendump (shot) and types
#             q <Return> (typequit: quit + confirm): links and the foot
#             window must be gone.
# Prints LINKS-OK.
unset LD_LIBRARY_PATH
ulimit -c 0
PATH=/usr/pkg/bin:$PATH; export PATH
URL=${URL:-https://example.com/}
WANT=${WANT:-documentation examples}
W=/tmp/linkswork; rm -rf $W; mkdir -p $W; cd $W
export HOME=$W
fails=0
ok() { echo "LINKS: ok   $1"; }
bad() { echo "LINKS: FAIL $1"; fails=$((fails+1)); }
has() { if grep -q -- "$2" "$3"; then ok "$1"; else bad "$1"; sed 's/^/    /' "$3" | head -12; fi; }

echo "== dump"
links -version || bad "links -version"
cat > t.html <<'HTML'
<html><head><title>MINIX test page</title></head><body>
<h1>Heading One</h1>
<p>Caf&eacute; &amp; cr&egrave;me &lt;tag&gt; &copy; 2026</p>
<ul><li>first item</li><li>second item</li></ul>
<table border=1><tr><th>Name</th><th>Value</th></tr>
<tr><td>alpha</td><td>1</td></tr><tr><td>beta</td><td>22</td></tr></table>
<a href="http://example.com/x">a link</a>
</body></html>
HTML
links -dump -codepage utf-8 t.html > t.txt 2> t.err || bad "dump of a local file"
has "heading" 'Heading One' t.txt
has "entities (UTF-8)" 'Café & crème <tag> © 2026' t.txt
has "list" '[*] *second item' t.txt
has "table row" 'beta *| *22' t.txt
has "table border" '+--' t.txt

echo "== network"
dhcpcd -qM -4 -w em0 || bad "dhcp"
links -dump http://example.com/ > h.txt 2> h.err; has "http page" "$WANT" h.txt
links -dump "$URL" > s.txt 2> s.err; has "https page" "$WANT" s.txt
links -dump -ssl.certificates 2 "$URL" > s2.txt 2> s2.err
has "https page, certificates enforced" "$WANT" s2.txt
links -dump -ssl.certificates 2 https://expired.badssl.com/ > x.txt 2> x.err
if [ -s x.txt ]; then bad "expired certificate refused"; head -5 x.txt
else ok "expired certificate refused: $(head -1 x.err)"; fi

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
bind = SUPER, Return, exec, /usr/pkg/bin/foot /usr/pkg/bin/links $URL > $FLOG 2>&1
CFG
stop() {
	kill -$2 $1 2>/dev/null
	n=0
	while kill -0 $1 2>/dev/null && [ $n -lt 10 ]; do sleep 1; n=$((n+1)); done
	kill -0 $1 2>/dev/null && { echo "LINKS: pid $1 ignored SIG$2, killing"; kill -9 $1; }
}
/usr/pkg/bin/Hyprland --i-am-really-stupid -c $CONF > $LOG 2>&1 &
H=$!
sock() { ls $XDG_RUNTIME_DIR 2>/dev/null | grep '^wayland-[0-9]*$' | head -1; }
i=0
while [ -z "$(sock)" ] && [ $i -lt 90 ] && kill -0 $H 2>/dev/null; do
	sleep 1; i=$((i+1))
done
[ -n "$(sock)" ] || { echo "LINKS: no Hyprland socket"; tail -40 $LOG; exit 1; }
sleep 5
SIG=$(ls /tmp/hypr | head -1)
hc() { HYPRLAND_INSTANCE_SIGNATURE=$SIG /usr/pkg/bin/hyprctl "$@"; }
lpid() { ps ax | grep '[/]usr/pkg/bin/links' | grep -v foot | awk '{print $1}' | head -1; }
echo; echo HARNESS:INPUT:openterm
i=0
while { ! hc clients 2>/dev/null | grep -q 'class: foot' || [ -z "$(lpid)" ]; } &&
    [ $i -lt 60 ]; do sleep 1; i=$((i+1)); done
hc clients | grep -q 'class: foot' && ok "foot window" || bad "foot window"
[ -n "$(lpid)" ] && ok "links runs in foot" || bad "links runs in foot"
sleep 10	# page load + render
echo; echo HARNESS:INPUT:welcome; sleep 3
echo; echo HARNESS:INPUT:shot; sleep 4
[ -n "$(lpid)" ] && ok "links still running" || bad "links died"
echo; echo HARNESS:INPUT:typequit
i=0
while [ -n "$(lpid)" ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
[ -z "$(lpid)" ] && ok "q + Return ended links" || bad "q + Return ended links"
i=0
while hc clients | grep -q 'class: foot' && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
hc clients | grep -q 'class: foot' && bad "foot closed with links" || ok "foot closed with links"
alive=0; kill -0 $H 2>/dev/null && alive=1
[ $alive = 1 ] && ok "Hyprland alive" || bad "Hyprland alive"
F=$(ps ax | grep '[/]usr/pkg/bin/foot' | awk '{print $1}' | head -1)
[ -n "$F" ] && stop $F TERM
stop $H TERM
echo "== foot log"; grep -v '^$' $FLOG | head -20
echo "LINKS: fails=$fails"
[ $fails = 0 ] && echo LINKS-OK
