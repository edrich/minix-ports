# libdrm: core library only (no GPU vendor libs).  On MINIX, drmIoctl() is
# routed to minix_drm.c (added by the patch), which emulates the Linux KMS
# ioctls on top of the DRM-lite device /dev/drm0 (<sys/ioc_mdrm.h>).
VERSION=2.4.123
URL=https://dri.freedesktop.org/libdrm/libdrm-$VERSION.tar.xz
MESON_OPTS="-Dintel=disabled -Dradeon=disabled -Damdgpu=disabled
 -Dnouveau=disabled -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled
 -Dfreedreno=disabled -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled
 -Dcairo-tests=disabled -Dman-pages=disabled -Dvalgrind=disabled
 -Dtests=false -Dudev=false -Dinstall-test-programs=false"
