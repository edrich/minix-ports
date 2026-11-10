# libinput: input device handling for Wayland compositors, over the input
# server's evdev devices (/dev/input/event*) and libudev-minix.
# Patch: kernel headers -> FreeBSD variant (as libevdev), no DMI on MINIX.
VERSION=1.26.2
URL=https://gitlab.freedesktop.org/libinput/libinput/-/archive/$VERSION/libinput-$VERSION.tar.gz
MESON_OPTS="-Dlibwacom=false -Ddebug-gui=false -Dtests=false -Ddocumentation=false -Dzshcompletiondir=no"
