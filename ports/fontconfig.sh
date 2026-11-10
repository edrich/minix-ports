# fontconfig: font discovery (cairo, Weston clients).  Fonts are looked up
# in /usr/pkg/share/fonts; configuration in /usr/pkg/etc/fonts.
VERSION=2.15.0
URL=https://www.freedesktop.org/software/fontconfig/release/fontconfig-$VERSION.tar.xz
MESON_OPTS="-Ddoc=disabled -Dnls=disabled -Dtests=disabled -Dtools=enabled -Dcache-build=disabled -Diconv=disabled -Ddefault-fonts-dirs=/usr/pkg/share/fonts"
