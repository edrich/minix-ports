# cairo: 2D drawing for Weston's clients (terminal, desktop-shell).
# Image surfaces + freetype/fontconfig/png only (no X11, no GL).
VERSION=1.18.2
URL=https://cairographics.org/releases/cairo-$VERSION.tar.xz
MESON_OPTS="-Dxlib=disabled -Dxcb=disabled -Dxlib-xcb=disabled -Dquartz=disabled -Ddwrite=disabled -Dtests=disabled -Dgtk2-utils=disabled -Dglib=disabled -Dspectre=disabled -Dsymbol-lookup=disabled -Dgtk_doc=false -Dfreetype=enabled -Dfontconfig=enabled -Dpng=enabled -Dzlib=enabled"
