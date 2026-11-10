# pixman: software rendering (Weston/wlroots pixman renderers).  The x86 SIMD
# paths (MMX/SSE2/SSSE3) are picked at run time; MINIX saves SSE state.
VERSION=0.43.4
URL=https://cairographics.org/releases/pixman-$VERSION.tar.gz
MESON_OPTS="-Dgtk=disabled -Dlibpng=disabled -Dtests=disabled
 -Ddemos=disabled -Dopenmp=disabled -Dtimers=false"
