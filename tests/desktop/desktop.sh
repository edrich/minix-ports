#!/bin/sh
# desktop.sh - Phase 9 gate, run as root in the booted desktop image
# (run-hyprland.sh prepare).  Modes:
#   session    start-hyprland (must run Hyprland as the user "desk"), the
#              harness presses SUPER+Return (HARNESS:INPUT:openterm) and
#              types "touch /tmp/deskok" into foot (HARNESS:INPUT:typecmd);
#              checks the file's owner, foot's UTF-8 locale, start-hyprland
#              ctl/status/stop, and that a crashing client of the session
#              leaves no core file.  Prints DESKTOP-SESSION-OK.
#   enable     start-hyprland enable (the gate boots this image again)
#   autostart  after such a boot: Hyprland must already run, as desk
#              (HARNESS:INPUT:shot2).  Prints DESKTOP-AUTOSTART-OK.
S=/usr/pkg/bin/start-hyprland
fails=0
ok() { echo "DESKTOP: ok   $1"; }
bad() { echo "DESKTOP: FAIL $1"; fails=$((fails+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
owner() { ps -axo user,command | grep "$1" | grep -v grep | awk '{print $1}' | head -1; }
waitfor() {	# <seconds> <condition>
	i=0
	while ! eval "$2" && [ $i -lt $1 ]; do sleep 1; i=$((i+1)); done
	eval "$2"
}

case "$1" in
enable)
	$S enable && grep '^hyprland=YES' /etc/rc.conf && sync &&
	    echo DESKTOP-ENABLE-OK
	exit ;;
autostart)
	check "Hyprland started by rc" "waitfor 60 '$S status'"
	check "it runs as desk" '[ "$(owner /usr/pkg/bin/Hyprland)" = desk ]'
	check "wayland socket" "waitfor 30 'ls /tmp/xdg-desk/wayland-1 > /dev/null 2>&1'"
	sleep 5
	check "monitor Virtual-1" "$S ctl monitors | grep -q Virtual-1"
	echo; echo HARNESS:INPUT:shot2; sleep 4
	check "rc.d stop" "/etc/rc.d/hyprland stop && ! $S status > /dev/null"
	echo "DESKTOP: fails=$fails"
	[ $fails = 0 ] && echo DESKTOP-AUTOSTART-OK
	exit ;;
session) ;;
*)	echo "usage: desktop.sh session|enable|autostart"; exit 1 ;;
esac

check "desktop user in group operator" 'id desk | grep -q "groups=.*0("'
check "rc.d script installed, off by default" \
	'[ -x /etc/rc.d/hyprland ] && grep -q "^hyprland=NO" /etc/rc.conf'
check "not running after boot" "! $S status > /dev/null"
$S; check "start-hyprland" "[ $? = 0 ]"
check "status" "$S status"
check "Hyprland runs as desk" '[ "$(owner /usr/pkg/bin/Hyprland)" = desk ]'
check "second start refused" "! $S > /dev/null"
sleep 5
check "ctl monitors" "$S ctl monitors | grep -q Virtual-1"

echo; echo HARNESS:INPUT:openterm
check "SUPER+Return opens foot" "waitfor 60 '$S ctl clients | grep -q \"class: foot\"'"
check "foot runs as desk" '[ "$(owner /usr/pkg/bin/foot)" = desk ]'
sleep 5	# shell prompt
echo; echo HARNESS:INPUT:typecmd
check "typed command ran" "waitfor 30 '[ -f /tmp/deskok ]'"
check "as desk" '[ "$(ls -l /tmp/deskok | awk "{print \$3}")" = desk ]'
check "foot found a UTF-8 locale" '! grep -q "not a UTF-8 locale" /tmp/foot-desk.log'
sleep 2
echo; echo HARNESS:INPUT:shot; sleep 4

# A client that dies of SIGSEGV inside the session (ulimit -c 0 is
# inherited from start-hyprland): no core file anywhere it could land.
F=$(ps ax | grep '[/]usr/pkg/bin/foot' | awk '{print $1}' | head -1)
[ -n "$F" ] && kill -SEGV $F
sleep 3
check "crashed client left no core file" \
	'[ -z "$(ls /home/desk/core.* /tmp/core.* /core.* 2>/dev/null)" ]'
check "Hyprland survived it" "$S status > /dev/null"
check "stop" "$S stop && ! $S status > /dev/null"
check "no core files after stop" '[ -z "$(ls /home/desk/core.* 2>/dev/null)" ]'
echo "== foot log"; grep -v '^$' /tmp/foot-desk.log | head -20
echo "== Hyprland log (errors)"; grep -aE 'ERR|CRIT' /tmp/hyprland-desk.out | head -20
echo "DESKTOP: fails=$fails"
[ $fails = 0 ] && echo DESKTOP-SESSION-OK
