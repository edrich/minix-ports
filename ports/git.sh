# git: version control (Phase 10).  https transport through the curl port
# (static libcurl) and the openssl port; no ssh in the MINIX base system, so
# ssh:// remotes need an OpenSSH port first.
# Built with git's own Makefile (it only builds in-tree: the source is
# copied to build/git/obj).  uname_S is a name config.mak.uname does not
# know - its "Minix" section describes MINIX 3.1 (no curl, no expat, ...).
#   NO_PTHREADS  libmthread is cooperative: threaded pack/grep/index gain
#                nothing and a blocked worker would stall everything
#   NO_MMAP      pread-based emulation; MINIX file mmap has no MAP_SHARED
#                writeback and git needs none of it
#   NO_ICONV     multibyte locales/iconv modules are not reliable in base
#   NO_PERL/NO_PYTHON/NO_TCLTK/NO_GETTEXT  not in the base system: no
#                add -p helpers in perl (builtin now), git-svn, gitk, i18n
#   INSTALL_SYMLINKS  the ~150 git-<builtin> names as symlinks (the payload
#                copy into the guest would turn hard links into copies)
VERSION=2.52.0
URL=https://www.kernel.org/pub/software/scm/git/git-$VERSION.tar.xz

git_make() {
	make -C "$BUILD/obj" -j"$(nproc)" \
		uname_S=MinixPorts uname_O= uname_M=i386 uname_R=3.4.0 \
		prefix="$PREFIX" sysconfdir="$PREFIX/etc" \
		CC="i586-elf32-minix-gcc --sysroot=$SYSROOT" \
		AR=i586-elf32-minix-ar STRIP=i586-elf32-minix-strip \
		CFLAGS="-O2 -I$SYSROOT$PREFIX/include" \
		LDFLAGS="-L$SYSROOT$PREFIX/lib -Wl,-rpath,$PREFIX/lib -Wl,-z,noexecstack" \
		CURL_CONFIG=false CURL_CFLAGS= \
		CURL_LDFLAGS="-lcurl -lssl -lcrypto -lz" \
		NO_PTHREADS=YesPlease NO_MMAP=YesPlease NO_ICONV=YesPlease \
		NO_PERL=YesPlease NO_PYTHON=YesPlease NO_TCLTK=YesPlease \
		NO_GETTEXT=YesPlease NO_INSTALL_HARDLINKS=YesPlease \
		INSTALL_SYMLINKS=YesPlease NO_REGEX= NO_NSEC=YesPlease \
		HAVE_PATHS_H=YesPlease HAVE_DEV_TTY=YesPlease \
		HAVE_STRINGS_H=YesPlease HAVE_GETDELIM=YesPlease \
		CSPRNG_METHOD=arc4random DEFAULT_PAGER=less DEFAULT_EDITOR=vi \
		SHELL_PATH=/bin/sh NO_RUST=YesPlease \
		"$@"
}
port_configure() {
	if [ ! -f "$BUILD/obj/Makefile" ]; then
		mkdir -p "$BUILD/obj"
		cp -a "$SRC/." "$BUILD/obj/"
	fi
}
port_build() { git_make all; }
port_install() { git_make install DESTDIR="$DESTDIR"; }
