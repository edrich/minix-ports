# libxkbcommon: keymaps (xkeyboard-config data from the xkeyboard-config
# port, installed under /usr/pkg/share/X11/xkb).
VERSION=1.7.0
URL=https://xkbcommon.org/download/libxkbcommon-$VERSION.tar.xz
MESON_OPTS="-Denable-x11=false -Denable-wayland=false -Denable-docs=false
 -Denable-tools=false -Denable-xkbregistry=false
 -Denable-bash-completion=false
 -Dxkb-config-root=/usr/pkg/share/X11/xkb
 -Dx-locale-root=/usr/pkg/share/X11/locale"
