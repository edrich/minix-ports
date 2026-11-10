# DejaVu fonts (TrueType): the default sans and monospace faces for
# fontconfig/cairo (weston-terminal uses "monospace").  Only the regular and
# bold Sans/Sans Mono faces, to keep the guest payload small.
VERSION=2.37
URL=https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-$VERSION.tar.bz2
SRCNAME=dejavu-fonts-ttf-$VERSION

port_configure() { :; }
port_build() { :; }
port_install() {
	_d="$DESTDIR$PREFIX/share/fonts/dejavu"
	mkdir -p "$_d"
	for _f in DejaVuSans DejaVuSans-Bold DejaVuSansMono DejaVuSansMono-Bold; do
		cp "$SRC/ttf/$_f.ttf" "$_d/"
	done
	cp "$SRC/LICENSE" "$_d/LICENSE"
}
