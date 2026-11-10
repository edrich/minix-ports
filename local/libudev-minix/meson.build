# libudev-minix: the libudev API over a static view of MINIX devices.
# The version number is the libudev API level it stands in for.
project('libudev-minix', 'c',
	version : '251',
	default_options : ['c_std=gnu99', 'warning_level=2'])

lib = library('udev', 'libudev.c',
	c_args : ['-fvisibility=hidden', '-Wno-unused-parameter'],
	version : '1.7.5',
	soversion : '1',
	install : true)

install_headers('libudev.h')

pkg = import('pkgconfig')
pkg.generate(lib,
	name : 'libudev',
	description : 'Library to access udev device information (MINIX)',
	version : meson.project_version())
