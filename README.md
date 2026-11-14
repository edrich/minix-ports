# minix-ports — out-of-tree ports overlay for MINIX 3 (Hyprland project)

This repository is the companion of the main MINIX source repo,
[edrich/minix](https://github.com/edrich/minix). It lives **outside** the
MINIX source tree (checked out as a sibling of `../obj.i386` and of the
`minix` checkout) and holds everything that should not be part of the OS
build itself: a modern cross toolchain and the third-party ports (wayland,
wlroots, Hyprland ...) built with it.

```
git clone https://github.com/edrich/minix.git
git clone https://github.com/edrich/minix-ports.git
```

## Layout

- `build-toolchain.sh` — builds the `i586-elf32-minix` cross toolchain
  (binutils 2.43.1 + gcc 13.3.0) into `tc/`. Sources are vanilla GNU
  tarballs in `src/` with MINIX target patches in `patches/` applied on
  first extraction. Iterating: `rm -rf build/gcc` then re-run.
- `test-toolchain.sh` — Phase-1 gate: cross-compiles `tests/hello.c` /
  `tests/hello.cpp` (C, C++17: iostream/STL/exceptions/static ctors),
  injects them into MINIX via the QEMU harness (`minix/releasetools/
  x86_qemu.py`) and verifies their output. Static and dynamic linking both
  covered.
- `cross/` — cross-build integration: `meson-minix.txt.in` (meson
  `--cross-file` template, filled in by build-port.sh), `cmake-minix.cmake`
  (`-DCMAKE_TOOLCHAIN_FILE=...`), `i586-elf32-minix-pkg-config` (also
  installed into `tc/bin/`; resolves .pc files inside `sysroot/`).
- `mksysroot.sh` — creates `sysroot/`: symlinks into the MINIX OS destdir
  plus `usr/pkg -> rootfs/usr/pkg`.  Ports compile with
  `--sysroot=sysroot` and install into `rootfs/usr/pkg` (guest prefix
  `/usr/pkg`, rpath `/usr/pkg/lib`).  They cannot go into the OS destdir:
  the release build's flist check rejects files missing from the set lists.
- `build-port.sh <name> [clean]` — builds one port from `ports/<name>.sh`
  (VERSION, URL, MESON_OPTS; meson by default, recipes may override
  `port_configure/port_build/port_install`; helpers: `autotools_*` for
  configure-based ports, which also fixes the generated libtool script
  (libtool thinks MINIX has no shared libraries); `host_meson` for native
  tools a cross build must run, installed into `host/`, e.g.
  wayland-scanner).  The tarball goes to `src/`,
  `patches/<name>-<VERSION>-minix.patch` is applied on first extraction,
  the build tree is `build/<name>/`.  To change a patch: edit the tree in
  `src/`, regenerate with `diff -ruN` against a pristine extract, and check
  that a clean rebuild reproduces it.
- `mkpatch.sh <name> <version>` — regenerates
  `patches/<name>-<version>-minix.patch` from the edited `src/` tree and
  verifies it against a pristine extract.
- Ports so far: `libdrm` (2.4.123; `minix_drm.c` emulates the Linux KMS
  ioctls on the MINIX DRM-lite device /dev/drm0, see the patch header),
  `libffi` 3.4.6, `wayland` 1.23.1, `wayland-protocols` 1.38, `pixman`
  0.43.4, `xkeyboard-config` 2.43 (data), `libxkbcommon` 1.7.0.  Build
  order: libdrm; libffi, wayland, wayland-protocols, pixman,
  xkeyboard-config, libxkbcommon.
- `local/<name>/` — MINIX-specific code built like a port (recipe sets
  `LOCAL=yes`, no download/patch): `libudev-minix`, the libudev API over
  a static view of MINIX devices (`/dev/input/event*` from the input
  server, `/dev/drm0` as drm `card0` with a PCI parent), no hotplug.
- Ports so far (`ports/*.sh`, in build order): libdrm; libffi, wayland,
  wayland-protocols, pixman, xkeyboard-config, libxkbcommon (Phase 4);
  libevdev (also installs `<linux/input.h>` & co. into /usr/pkg/include),
  mtdev, libudev-minix, libinput, libseat (noop backend only) (Phase 5);
  os-pc (pkg-config files for the OS's expat and zlib), libpng, freetype,
  fontconfig, cairo, dejavu-fonts, libdisplay-info, weston (Phase 6);
  mesa 24.0.9 (Phase 7: softpipe, EGL wayland/surfaceless/GBM, GLES2,
  GBM with the DRI backend, kms_swrast over /dev/drm0 dumb buffers; the
  recipe puts /opt/py, the container's python with mako, first in PATH).
- `stage-payload.sh <dir>` — copies the runtime part of `rootfs/usr/pkg`
  (no headers, .pc files or static libraries; ELF files stripped, hard
  links kept - Mesa's DRI drivers are one file under several names) plus
  `tests/weston/*.sh` into a harness payload directory.  Use the
  unstripped files in `rootfs/` for addr2line.
- `tests/crashmap.c` — debugging aid: build as a shared object and
  `LD_PRELOAD` it; on a crash it prints every loaded object's base address
  (MINIX has no ASLR and its ld.so ignores LD_TRACE_LOADED_OBJECTS), so
  the kernel's stack trace can be resolved with addr2line.
- `test-gl.sh` — Phase-7 gate (passing since 2026-11-10):
  `tests/egl-gate.c surfaceless` (EGL surfaceless + pbuffer, GLSL,
  glReadPixels check) and `egl-gate gbm` (GBM + EGL on /dev/drm0,
  animated frames with page flips; last frame checked from a screendump
  by `tests/checkgl.py`).
- `test-weston.sh` — Phase-6 gate: Weston headless (desktop shell +
  weston-simple-shm), then Weston on /dev/drm0 with the desktop shell and
  weston-terminal; QEMU types a shell command into the terminal and takes
  a screendump, checked by `tests/checkweston.py`.
- `test-input.sh` — Phase-5 gate: `tests/input-gate.c` opens a seat with
  libseat, lets libinput's udev backend find and open the evdev devices,
  and checks keyboard text (via xkbcommon) and pointer motion/clicks
  injected through QEMU's monitor (`x86_qemu.py --input`).
- `test-wayland.sh` — Phase-4 gate: `tests/wl-gate.c`, a forked minimal
  compositor + client (shm buffer via fd passing, pixman, frame
  callback, signalfd/timerfd event sources) and an xkbcommon keymap,
  run inside MINIX with the ports installed into the guest's /usr/pkg.
- `test-drm.sh` — Phase-3 gate: `tests/drm-demo.c` drives /dev/drm0 via
  the libdrm API only (modeset, 30 event-paced page flips) inside MINIX
  and checks the screendump (`tests/checkcard.py`).
- `binutils` toolchain: `i586-elf32-minix` target; ld emulation
  `elf_i386_minix`; ELF, dynamic linker `/usr/libexec/ld.elf_so`.
- gcc: C and C++, static libgcc/libstdc++, `--disable-threads` (MINIX has
  libmthread, not preemptive pthreads — revisit if ports need std::thread),
  `-pthread` accepted (-> `-D_REENTRANT`, `-lpthread` = libmthread alias,
  `<pthread.h>` from the OS),
  `--disable-tls`, single (posix-less) gthreads, `os/generic` libstdc++
  with the NetBSD cross-config answer set.  Consequences: `__thread`/
  `thread_local` are emutls with ONE value shared by all threads, and
  libstdc++ has no `std::mutex`/`std::thread` (Hyprland will need a
  `--enable-threads=posix` rebuild).  Predefines `unix`, `__unix`,
  `__unix__` and `__minix`/`__minix__`/`__Minix__` (=3).

## Prereqs

- A checkout of [edrich/minix](https://github.com/edrich/minix) (`master`)
  next to this one (`../minix`); paths like `minix/docker/` and
  `minix/releasetools/` below refer to it.
- The MINIX OS must be built once (sysroot is `../obj.docker.i386/destdir.i386`
  by default — from the docker/ workflow; override with `MINIX_SYSROOT`) and
  the boot image produced (`minix/minix_x86.img`). `master` includes the
  dual-stack i386 csu/rtld change the toolchain relies on (merged from the
  former `hyprland-support` branch).
- Host: docker (see `minix/docker/README.md`) or: gcc/g++, flex, bison,
  texinfo, gmp/mpfr/mpc dev libs, qemu-system-i386, mke2fs, python3.
- `src/` (tarballs + patched source trees, ~1.8G) and `build/` are
  regenerable via `./build-toolchain.sh`; only `tc/` (~740M) is the product.
  `build/` can be deleted any time.

## Notable toolchain decisions / gotchas

- gcc is configured `--disable-fixincludes`: fixincludes mangles MINIX's
  NetBSD-style `_BSD_*` headers.
- `gcc/ginclude/stddef.h` gets a small patch: its three `#if
  defined(__NetBSD__)` blocks also match `__minix`, keeping the
  `_BSD_SIZE_T_`/etc. typedef dance coherent between gcc and MINIX libc
  headers (otherwise `typedef _BSD_SIZE_T_ size_t;` breaks in C++11 mode).
- `libstdc++-v3` uses the NetBSD cross-config answers (MINIX's libc is
  NetBSD-8 derived).
- gcc patches add the `i586-elf32-minix` target: `gcc/config/minix.h` +
  `i386/minix.h` (link recipe: `-m elf_i386_minix`, crt0/crti/crtn from the
  sysroot, crtbegin/crtend from gcc, dynamic linker
  `/usr/libexec/ld.elf_so`), plus `netbsd-stdint.h` in `tm_file` and
  `extra_parts` in `libgcc/config.host` so crtbegin/crtend are built.

## Test

```
./build-toolchain.sh        # once / after patch changes
./test-toolchain.sh         # in-guest integration gate
./build-port.sh libdrm      # ports (inside docker/dev.sh)
./test-drm.sh               # libdrm + DRM-lite gate
for p in libffi wayland wayland-protocols pixman xkeyboard-config \
    libxkbcommon; do ./build-port.sh $p; done
./test-wayland.sh           # wayland stack gate
./test-input.sh             # input stack gate (libinput/libseat/udev)
./test-weston.sh            # Weston desktop gate (Phase 6)
```

## Command line applications (git, curl, vim)

```
./build-port.sh zlib; ./build-port.sh openssl; ./build-port.sh curl
./build-port.sh git; ./build-port.sh vim
./test-git.sh               # gate: local git work + https clone (needs network)
NONET=1 ./test-git.sh       # local part only
./test-vim.sh               # gate: scripted edits + vim typed into in foot
```

- `vim` 9.1.2148: huge feature set, terminal only (base libterminfo; foot
  runs it with `TERM=xterm-256color`), Wayland clipboard support, no
  scripting-language interfaces.  The base system's `vi` (nvi) stays
  `/usr/bin/vi`; this one is `/usr/pkg/bin/vim` (`view`, `vimdiff`, `xxd`).
  The gate needs a MINIX libc with the eventfd/epoll_pwait fixes of
  2026-11-14 (minix repo, docs/UPDATING): without them foot does not
  close when the program in it exits.
- `zlib` 1.3.1 and `openssl` 3.5.4 are installed in `/usr/pkg` next to the
  base system's much older ones (zlib 1.2.3, OpenSSL 1.0.1p); ports find
  them first through the `-I`/`-L` order and the `/usr/pkg/lib` RPATH.
- `curl` 8.17.0: static libcurl, OpenSSL TLS, Mozilla's CA bundle in
  `/usr/pkg/etc/ssl/cert.pem` (fetched from curl.se at build time, kept in
  `src/cacert.pem`; delete that file to refresh it).
- `git` 2.52.0: https remotes through libcurl; no ssh in the MINIX base
  system, so no `ssh://` remotes yet.  Built without threads, mmap, iconv,
  perl, python, Tcl/Tk and gettext (see `ports/git.sh`).  Needs a MINIX
  libc with `getpgid()` (minix repo, docs/UPDATING 20261114).
- Network in QEMU: the harness option `--net` (and `run-hyprland.sh` by
  default) attaches an e1000 NIC on user-mode networking; in the guest
  `dhcpcd -qM -4 -w em0` configures it (the desktop image does so at boot
  through `/etc/ifconfig.em0`).

## Desktop image (Hyprland session)

`run-hyprland.sh` makes `build/desktop/minix-desktop.img` (the OS image +
the ports in `/usr/pkg` + the session files of `desktop/`) and boots it
with the screen on VNC and the serial console in the terminal:

```
./run-hyprland.sh           # prepare when stale, then boot (VNC :1)
  minix# start-hyprland     # Hyprland as user "desk"; SUPER/ALT+Return = foot
  minix# start-hyprland ctl clients | status | stop
  minix# start-hyprland enable      # start at boot (use PERSIST=1)
./test-desktop.sh           # gate: session as desk, foot, autostart at boot
./test-hyprland.sh ./test-foot.sh ./test-mouse.sh ./test-blit.sh
```

- `desktop/start-hyprland.sh` -> `/usr/pkg/bin/start-hyprland`: session
  environment (wlroots software-rendering variables, `LANG=en_US.UTF-8`,
  `XDG_RUNTIME_DIR=/tmp/xdg-<user>`, `ulimit -c 0`), default
  `~/.config/hypr/hyprland.conf` on first start (key list in the script
  header).  Root hands over to the desktop user.
- `desktop/install.sh` (run in the guest by the prepare step): user
  `desk` (`useradd -G operator`: /dev/drm0 and /dev/input/event* are
  root:operator 660; operator is gid 0 on MINIX, so `ls` shows "wheel"),
  `/etc/rc.d/hyprland` + `hyprland=NO` in `/etc/rc.conf`,
  `/etc/ifconfig.em0` (DHCP at boot; `NONET=1 ./run-hyprland.sh` boots
  without a NIC).  git and curl are in the user's PATH (`/usr/pkg/bin`).
- While Hyprland runs it owns keyboard and mouse: the VGA text console
  gets no keys.  Serial console and network logins are unaffected.
