# Weston: the reference Wayland compositor (Phase 6 gate), with the DRM
# backend (/dev/drm0 via libdrm's DRM-lite emulation, legacy KMS) and the
# pixman renderer, plus (Phase 7) the GL renderer over Mesa's GBM/EGL
# (softpipe via kms_swrast); headless backend for tests.  No X11,
# XWayland, RDP/VNC/PipeWire, systemd, lcms.  Clients: weston-terminal and
# the desktop-shell helpers (cairo); simple-shm and simple-egl as smoke
# tests.
VERSION=14.0.1
URL=https://gitlab.freedesktop.org/wayland/weston/-/releases/$VERSION/downloads/weston-$VERSION.tar.xz
MESON_OPTS="-Dbackend-drm=true -Dbackend-drm-screencast-vaapi=false -Dbackend-headless=true -Dbackend-pipewire=false -Dbackend-rdp=false -Dscreenshare=false -Dbackend-vnc=false -Dbackend-wayland=false -Dbackend-x11=false -Dbackend-default=drm -Drenderer-gl=true -Dxwayland=false -Dsystemd=false -Dremoting=false -Dpipewire=false -Dshell-desktop=true -Dshell-fullscreen=false -Dshell-ivi=false -Dshell-kiosk=true -Dcolor-management-lcms=false -Dimage-jpeg=false -Dimage-webp=false -Dtools=terminal,info -Ddemo-clients=false -Dsimple-clients=shm,egl -Dresize-pool=false -Dwcap-decode=false -Dtests=false -Ddoc=false"
