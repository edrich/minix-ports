# vim: the editor (Phase 10).  Terminal build: no GUI, no X, no scripting
# language interfaces, no NLS (no gettext in base).  Terminal library: the
# base system's libterminfo (NetBSD terminfo database; foot runs with
# TERM=xterm-256color).  vim's configure runs test programs: when cross
# compiling their answers are given as vim_cv_* cache variables (values as
# for NetBSD).  --disable-xattr: <sys/xattr.h> is there (NetBSD headers) but
# MINIX has no extended attribute calls.  It only builds in-tree: the source is copied to
# build/vim/obj.
VERSION=9.1.2148
URL=https://github.com/vim/vim/archive/refs/tags/v$VERSION.tar.gz
TARBALL=vim-$VERSION.tar.gz

port_configure() {
	if [ ! -f "$BUILD/obj/src/auto/config.mk.done" ]; then
		mkdir -p "$BUILD/obj"
		cp -a "$SRC/." "$BUILD/obj/"
		(cd "$BUILD/obj" && \
		vim_cv_toupper_broken=no vim_cv_terminfo=yes \
		vim_cv_tgetent=zero vim_cv_getcwd_broken=no \
		vim_cv_stat_ignores_slash=no vim_cv_memmove_handles_overlap=yes \
		vim_cv_bcopy_handles_overlap=yes vim_cv_memcpy_handles_overlap=no \
		vim_cv_tty_group=world vim_cv_tty_mode=0620 \
		vim_cv_timer_create=no vim_cv_timer_create_with_lrt=no \
		vim_cv_uname_output=Minix \
		ac_cv_small_wchar_t=no ac_cv_sizeof_int=4 \
		./configure --host=i586-elf32-minix --build="$(cc -dumpmachine)" \
			--prefix="$PREFIX" \
			CC="i586-elf32-minix-gcc --sysroot=$SYSROOT" \
			CPPFLAGS="-I$SYSROOT$PREFIX/include" \
			LDFLAGS="-L$SYSROOT$PREFIX/lib -Wl,-rpath,$PREFIX/lib -Wl,-z,noexecstack" \
			STRIP=i586-elf32-minix-strip \
			--with-features=huge --with-tlib=terminfo \
			--enable-gui=no --without-x --disable-nls \
			--disable-gpm --disable-sysmouse --disable-selinux --disable-xattr \
			--disable-canberra --disable-libsodium --disable-netbeans \
			--disable-channel --disable-terminal \
			--disable-luainterp --disable-perlinterp \
			--disable-pythoninterp --disable-python3interp \
			--disable-rubyinterp --disable-tclinterp \
			--with-compiledby=minix-ports) &&
		touch "$BUILD/obj/src/auto/config.mk.done"
	fi
}
port_build() { make -C "$BUILD/obj" -j"$(nproc)"; }
port_install() { make -C "$BUILD/obj" install DESTDIR="$DESTDIR" STRIP=true; }
