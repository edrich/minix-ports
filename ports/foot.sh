# foot: Wayland terminal emulator (Phase 9).  1.20.2: the newest release
# that builds against wayland-protocols 1.38 and xkbcommon 1.7 (1.21+
# needs wayland-protocols >= 1.41 and fcft >= 3.3.1).  MINIX's terminfo is
# NetBSD's database without a "foot" entry: no terminfo build (it needs
# ncurses tic), TERM defaults to xterm-256color.  No utmp, themes, tests.
VERSION=1.20.2
URL=https://codeberg.org/dnkl/foot/archive/$VERSION.tar.gz
TARBALL=foot-$VERSION.tar.gz
SRCNAME=foot
# NetBSD-style <ctype.h> macros index a table: char arguments warn
# (char-subscripts), which foot builds with -Werror.
EXTRA_CFLAGS="-Wno-error=char-subscripts"
MESON_OPTS="-Ddocs=disabled -Dthemes=false -Dtests=false -Dterminfo=disabled -Ddefault-terminfo=xterm-256color -Dutmp-backend=none -Dgrapheme-clustering=disabled"
