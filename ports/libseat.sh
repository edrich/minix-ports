# libseat (from seatd): seat management API used by Weston and wlroots.
# Only the "noop" backend is built: it opens devices directly (needs
# access to /dev/drm0 and /dev/input/event*, i.e. root or the operator
# group) and does no VT switching.  Select it with LIBSEAT_BACKEND=noop.
VERSION=0.9.1
URL=https://git.sr.ht/~kennylevinsen/seatd/archive/$VERSION.tar.gz
TARBALL=seatd-$VERSION.tar.gz
SRCNAME=seatd-$VERSION
MESON_OPTS="-Dlibseat-logind=disabled -Dlibseat-seatd=disabled -Dlibseat-builtin=disabled -Dserver=disabled -Dexamples=disabled -Dman-pages=disabled"
