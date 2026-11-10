# Mesa (Phase 7): software OpenGL / OpenGL ES 2 with the softpipe gallium
# driver (no LLVM, so no llvmpipe/JIT), EGL (wayland, surfaceless and drm
# = GBM platforms) and GBM with the DRI backend.  On /dev/drm0 GBM and EGL
# use kms_swrast (softpipe rendering into DRM-lite dumb buffers); on
# Wayland without a usable DRM device EGL falls back to swrast over wl_shm.
# No GLX/X11, Vulkan, video, OpenCL, shader cache (no background cache
# thread: MINIX threads are cooperative), no glvnd.
VERSION=24.0.9
URL=https://archive.mesa3d.org/mesa-$VERSION.tar.xz
MESON_OPTS="-Dplatforms=wayland -Degl-native-platform=wayland -Dgallium-drivers=swrast -Dvulkan-drivers= -Dllvm=disabled -Dshared-llvm=disabled -Ddraw-use-llvm=false -Dglx=disabled -Degl=enabled -Dgbm=enabled -Dgles1=disabled -Dgles2=enabled -Dopengl=true -Dshared-glapi=enabled -Dglvnd=false -Ddri3=disabled -Dgallium-vdpau=disabled -Dgallium-va=disabled -Dgallium-xa=disabled -Dgallium-nine=false -Dgallium-opencl=disabled -Dgallium-rusticl=false -Dgallium-omx=disabled -Dvideo-codecs= -Dshader-cache=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dzstd=disabled -Dexpat=disabled -Dxmlconfig=disabled -Dbuild-tests=false -Dosmesa=false -Dtools= -Dperfetto=false -Dselinux=false -Dandroid-libbacktrace=disabled -Dmicrosoft-clc=disabled -Dintel-clc=disabled -Dspirv-to-dxil=false"

# Mesa's code generators need python3 with mako: use the container's venv.
export PATH="/opt/py/bin:$PATH"
# softpipe interprets shaders in floating point: SSE2 code generation
# instead of the toolchain's i586/x87 default (QEMU's qemu32 CPU and any
# i686+ CPU since the Pentium 4 have SSE2; MINIX saves the SSE state).
EXTRA_CFLAGS="-march=pentium4 -mtune=generic -mfpmath=sse"
