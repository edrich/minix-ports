# fcft: font loading and glyph rasterization (freetype + fontconfig +
# pixman) for foot.  3.1.10: the fcft of foot 1.20.x (PLAN.md Phase 9).
# No text shaping (no harfbuzz/utf8proc), no SVG glyphs.  Uses C11
# <threads.h> (MINIX: libmthread, OS change 40).
VERSION=3.1.10
URL=https://codeberg.org/dnkl/fcft/archive/$VERSION.tar.gz
TARBALL=fcft-$VERSION.tar.gz
SRCNAME=fcft
MESON_OPTS="-Dsvg-backend=none -Ddocs=disabled -Dgrapheme-shaping=disabled -Drun-shaping=disabled -Dexamples=false"
