# freetype: font rasterizer (fontconfig, cairo).
VERSION=2.13.3
URL=https://download.savannah.gnu.org/releases/freetype/freetype-$VERSION.tar.xz
MESON_OPTS="-Dzlib=system -Dpng=enabled -Dbzip2=disabled -Dbrotli=disabled -Dharfbuzz=disabled -Dtests=disabled"
