#!/bin/sh
# install.sh - run in the guest by run-hyprland.sh (payload on /mnt, ports
# already copied to /usr/pkg): install the session files and make the
# desktop user.  Safe to run again.
set -e
D=$(dirname "$0")
cp "$D/start-hyprland.sh" /usr/pkg/bin/start-hyprland
chmod 755 /usr/pkg/bin/start-hyprland
cp "$D/rc.d-hyprland" /etc/rc.d/hyprland
chmod 555 /etc/rc.d/hyprland
grep -q '^hyprland=' /etc/rc.conf || echo 'hyprland=NO' >> /etc/rc.conf
# The desktop user: group operator (gid 0 on MINIX, like wheel) owns
# /dev/drm0 and /dev/input/event*.  No password: reached with su from root.
id desk > /dev/null 2>&1 || useradd -m -g users -G operator -c "Desktop user" desk
id desk
sync
echo DESKTOP-INSTALLED
