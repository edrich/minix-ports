# wlroots at the commit Hyprland v0.22.0beta pins as its submodule
# (0.17.0-dev, soversion 12; see PLAN.md Phase 8).  Built standalone for
# the tinywl smoke gate; Hyprland itself builds it as a subproject.
# Backends: DRM (/dev/drm0 via libdrm's DRM-lite emulation, legacy KMS)
# and libinput; renderer GLES2 (Mesa softpipe through EGL/GBM, dma-buf
# import = PRIME); allocator GBM.  No X11/XWayland, no Vulkan.
VERSION=677a3f2f8847ed2de49dd60868f9d9487a546f58
URL=https://gitlab.freedesktop.org/wlroots/wlroots/-/archive/$VERSION/wlroots-$VERSION.tar.gz
MESON_OPTS="-Dbackends=drm,libinput -Drenderers=gles2 -Dallocators=gbm -Dsession=enabled -Dxwayland=disabled -Dxcb-errors=disabled -Dexamples=true -Dwerror=false"
