/*
 * shm-pattern - static wl_shm test window (xdg-shell) for compositor
 * correctness checks: a pattern that shows flips, offsets and stale pixels.
 *
 *   red   = 255 * x / (w - 1)          (rises left -> right)
 *   green = 255 * y / (h - 1)          (rises top -> bottom)
 *   blue  = 0xff on a 32x32 checker whose (0,0) square is blue
 *
 * The buffer always has the size the compositor configured (tiled windows)
 * or 400x300.  Modes (argv[1]):
 *   xrgb         WL_SHM_FORMAT_XRGB8888, alpha byte 0x00 (must be ignored)
 *   argb-opaque  ARGB8888, alpha 0xff, opaque region = whole surface
 *   argb         ARGB8888, alpha 0xff, no opaque region (blended)
 * Runs until SIGINT/SIGTERM; prints "SHMPATTERN <w>x<h>" per buffer.
 */
#include <sys/mman.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <wayland-client.h>
#include "xdg-shell-client-protocol.h"

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm_base;
static int cfg_w, cfg_h, configured, running = 1;
static enum { XRGB, ARGB_OPAQUE, ARGB } mode;

static void
on_signal(int sig)
{
	(void)sig;
	running = 0;
}

static void
wm_ping(void *data, struct xdg_wm_base *b, uint32_t serial)
{
	(void)data;
	xdg_wm_base_pong(b, serial);
}
static const struct xdg_wm_base_listener wm_listener = { wm_ping };

static void
reg_global(void *data, struct wl_registry *r, uint32_t name,
    const char *iface, uint32_t version)
{
	(void)data; (void)version;
	if (!strcmp(iface, wl_compositor_interface.name))
		compositor = wl_registry_bind(r, name, &wl_compositor_interface, 4);
	else if (!strcmp(iface, wl_shm_interface.name))
		shm = wl_registry_bind(r, name, &wl_shm_interface, 1);
	else if (!strcmp(iface, xdg_wm_base_interface.name)) {
		wm_base = wl_registry_bind(r, name, &xdg_wm_base_interface, 1);
		xdg_wm_base_add_listener(wm_base, &wm_listener, NULL);
	}
}
static void
reg_remove(void *data, struct wl_registry *r, uint32_t name)
{
	(void)data; (void)r; (void)name;
}
static const struct wl_registry_listener reg_listener = { reg_global, reg_remove };

static void
surf_configure(void *data, struct xdg_surface *s, uint32_t serial)
{
	(void)data;
	xdg_surface_ack_configure(s, serial);
	configured = 1;
}
static const struct xdg_surface_listener surf_listener = { surf_configure };

static void
top_configure(void *data, struct xdg_toplevel *t, int32_t w, int32_t h,
    struct wl_array *states)
{
	(void)data; (void)t; (void)states;
	cfg_w = w;
	cfg_h = h;
}
static void
top_close(void *data, struct xdg_toplevel *t)
{
	(void)data; (void)t;
	running = 0;
}
static const struct xdg_toplevel_listener top_listener = {
	top_configure, top_close
};

static struct wl_buffer *
make_buffer(int w, int h)
{
	int stride = w * 4, size = stride * h;
	char name[] = "/tmp/shm-pattern-XXXXXX";
	int fd = mkstemp(name);
	if (fd < 0) { perror("mkstemp"); exit(1); }
	unlink(name);
	if (ftruncate(fd, size) < 0) { perror("ftruncate"); exit(1); }
	uint32_t *px = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (px == MAP_FAILED) { perror("mmap"); exit(1); }
	uint32_t a = mode == XRGB ? 0x00000000u : 0xff000000u;
	for (int y = 0; y < h; y++)
		for (int x = 0; x < w; x++) {
			uint32_t r = 255u * x / (w > 1 ? w - 1 : 1);
			uint32_t g = 255u * y / (h > 1 ? h - 1 : 1);
			uint32_t b = ((x / 32 + y / 32) & 1) ? 0 : 0xff;
			px[y * w + x] = a | r << 16 | g << 8 | b;
		}
	munmap(px, size);
	struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, size);
	struct wl_buffer *buf = wl_shm_pool_create_buffer(pool, 0, w, h, stride,
	    mode == XRGB ? WL_SHM_FORMAT_XRGB8888 : WL_SHM_FORMAT_ARGB8888);
	wl_shm_pool_destroy(pool);
	close(fd);
	return buf;
}

int
main(int argc, char **argv)
{
	const char *m = argc > 1 ? argv[1] : "xrgb";
	if (!strcmp(m, "xrgb")) mode = XRGB;
	else if (!strcmp(m, "argb-opaque")) mode = ARGB_OPAQUE;
	else if (!strcmp(m, "argb")) mode = ARGB;
	else { fprintf(stderr, "usage: shm-pattern [xrgb|argb-opaque|argb]\n"); return 2; }

	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	struct wl_display *dpy = wl_display_connect(NULL);
	if (!dpy) { fprintf(stderr, "shm-pattern: no display\n"); return 1; }
	struct wl_registry *reg = wl_display_get_registry(dpy);
	wl_registry_add_listener(reg, &reg_listener, NULL);
	wl_display_roundtrip(dpy);
	if (!compositor || !shm || !wm_base) {
		fprintf(stderr, "shm-pattern: missing globals\n");
		return 1;
	}

	struct wl_surface *surf = wl_compositor_create_surface(compositor);
	struct xdg_surface *xs = xdg_wm_base_get_xdg_surface(wm_base, surf);
	xdg_surface_add_listener(xs, &surf_listener, NULL);
	struct xdg_toplevel *top = xdg_surface_get_toplevel(xs);
	xdg_toplevel_add_listener(top, &top_listener, NULL);
	xdg_toplevel_set_title(top, "shm-pattern");
	xdg_toplevel_set_app_id(top, "shm-pattern");
	wl_surface_commit(surf);

	int cur_w = 0, cur_h = 0;
	struct wl_buffer *buf = NULL;
	while (running) {
		if (configured) {
			configured = 0;
			int w = cfg_w > 0 ? cfg_w : 400, h = cfg_h > 0 ? cfg_h : 300;
			if (w != cur_w || h != cur_h || !buf) {
				if (buf)
					wl_buffer_destroy(buf);
				buf = make_buffer(w, h);
				cur_w = w; cur_h = h;
				printf("SHMPATTERN %dx%d %s\n", w, h, m);
				fflush(stdout);
			}
			struct wl_region *rg = NULL;
			if (mode != ARGB) {
				rg = wl_compositor_create_region(compositor);
				wl_region_add(rg, 0, 0, w, h);
			}
			wl_surface_set_opaque_region(surf, rg);
			if (rg)
				wl_region_destroy(rg);
			wl_surface_attach(surf, buf, 0, 0);
			wl_surface_damage(surf, 0, 0, w, h);
			wl_surface_commit(surf);
		}
		wl_display_flush(dpy);
		struct pollfd p = { wl_display_get_fd(dpy), POLLIN, 0 };
		if (poll(&p, 1, 500) < 0 && errno != EINTR)
			break;
		if (p.revents & POLLIN) {
			if (wl_display_dispatch(dpy) < 0)
				break;
		} else
			wl_display_dispatch_pending(dpy);
	}
	wl_display_disconnect(dpy);
	return 0;
}
