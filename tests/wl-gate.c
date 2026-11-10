/*
 * wl-gate - Phase 4 gate: the wayland stack on MINIX.
 *
 * A forked minimal compositor (libwayland-server: wl_compositor + wl_surface
 * implemented on wayland-server-protocol.h, wl_shm via wl_display_init_shm;
 * event loop = the libc epoll emulation, with a signalfd SIGTERM source and
 * a timerfd watchdog) and a client (libwayland-client) that
 *   - binds wl_compositor/wl_shm after a registry roundtrip,
 *   - creates an ftruncate()d (sparse) shm file, passes the fd over the
 *     socket (SCM_RIGHTS) as a wl_shm_pool, paints it with pixman,
 *   - attaches + commits, and waits for the frame callback.
 * The server checks the pixels it sees through its own mapping of the
 * pool (MAP_SHARED of file holes: VM FDIO_FILL).  Plus an xkbcommon keymap
 * from the installed xkeyboard-config data ("us": keycode 38 -> 'a').
 *
 * Prints "WLGATE-OK" when everything worked.
 */

#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <wayland-client.h>
#include <wayland-server.h>
#include <wayland-server-protocol.h>
#include <pixman.h>
#include <xkbcommon/xkbcommon.h>

#define W 64
#define H 48
#define COLOR 0xff3366cc	/* ARGB */

#define FAIL(...) do { fprintf(stderr, "WLGATE-FAIL: " __VA_ARGS__); \
	fprintf(stderr, " (errno %d %s)\n", errno, strerror(errno)); \
	exit(1); } while (0)

/* ------------------------------------------------------------ server --- */

struct surface {
	struct wl_resource *res;
	struct wl_resource *pending_buffer;
	struct wl_resource *frame_cb;
};

static struct wl_display *sdisplay;
static int server_ok;

static void
surface_destroy(struct wl_client *c, struct wl_resource *r)
{
	(void)c;
	wl_resource_destroy(r);
}

static void
surface_attach(struct wl_client *c, struct wl_resource *r,
	struct wl_resource *buffer, int32_t x, int32_t y)
{
	struct surface *s = wl_resource_get_user_data(r);
	(void)c; (void)x; (void)y;
	s->pending_buffer = buffer;
}

static void
surface_damage(struct wl_client *c, struct wl_resource *r, int32_t x,
	int32_t y, int32_t w, int32_t h)
{
	(void)c; (void)r; (void)x; (void)y; (void)w; (void)h;
}

static void
surface_frame(struct wl_client *c, struct wl_resource *r, uint32_t id)
{
	struct surface *s = wl_resource_get_user_data(r);

	s->frame_cb = wl_resource_create(c, &wl_callback_interface, 1, id);
}

static void
surface_noop_region(struct wl_client *c, struct wl_resource *r,
	struct wl_resource *region)
{
	(void)c; (void)r; (void)region;
}

static void
surface_commit(struct wl_client *c, struct wl_resource *r)
{
	struct surface *s = wl_resource_get_user_data(r);
	struct wl_shm_buffer *buf;
	uint32_t *px;
	int w, h, stride, bad = 0, x, y;

	(void)c;
	if (s->pending_buffer == NULL ||
	    (buf = wl_shm_buffer_get(s->pending_buffer)) == NULL) {
		fprintf(stderr, "server: commit without shm buffer\n");
		return;
	}
	w = wl_shm_buffer_get_width(buf);
	h = wl_shm_buffer_get_height(buf);
	stride = wl_shm_buffer_get_stride(buf);
	wl_shm_buffer_begin_access(buf);
	px = wl_shm_buffer_get_data(buf);
	for (y = 0; y < h; y++)
		for (x = 0; x < w; x++)
			if (px[y * (stride / 4) + x] != COLOR)
				bad++;
	printf("server: buffer %dx%d stride %d format %u, first pixel "
	    "%08x, %d wrong pixels\n", w, h, stride,
	    wl_shm_buffer_get_format(buf), px[0], bad);
	wl_shm_buffer_end_access(buf);
	if (w == W && h == H && bad == 0)
		server_ok = 1;

	wl_buffer_send_release(s->pending_buffer);
	s->pending_buffer = NULL;
	if (s->frame_cb) {
		wl_callback_send_done(s->frame_cb, 1234);
		wl_resource_destroy(s->frame_cb);
		s->frame_cb = NULL;
	}
}

static void
surface_set_transform(struct wl_client *c, struct wl_resource *r, int32_t t)
{
	(void)c; (void)r; (void)t;
}

static void
surface_set_scale(struct wl_client *c, struct wl_resource *r, int32_t s)
{
	(void)c; (void)r; (void)s;
}

static void
surface_damage_buffer(struct wl_client *c, struct wl_resource *r, int32_t x,
	int32_t y, int32_t w, int32_t h)
{
	(void)c; (void)r; (void)x; (void)y; (void)w; (void)h;
}

static void
surface_offset(struct wl_client *c, struct wl_resource *r, int32_t x,
	int32_t y)
{
	(void)c; (void)r; (void)x; (void)y;
}

static const struct wl_surface_interface surface_impl = {
	.destroy = surface_destroy,
	.attach = surface_attach,
	.damage = surface_damage,
	.frame = surface_frame,
	.set_opaque_region = surface_noop_region,
	.set_input_region = surface_noop_region,
	.commit = surface_commit,
	.set_buffer_transform = surface_set_transform,
	.set_buffer_scale = surface_set_scale,
	.damage_buffer = surface_damage_buffer,
	.offset = surface_offset,
};

static void
surface_free(struct wl_resource *r)
{
	free(wl_resource_get_user_data(r));
}

static void
compositor_create_surface(struct wl_client *c, struct wl_resource *r,
	uint32_t id)
{
	struct surface *s = calloc(1, sizeof(*s));

	s->res = wl_resource_create(c, &wl_surface_interface,
	    wl_resource_get_version(r), id);
	wl_resource_set_implementation(s->res, &surface_impl, s, surface_free);
}

static void
compositor_create_region(struct wl_client *c, struct wl_resource *r,
	uint32_t id)
{
	(void)c; (void)r; (void)id;
	wl_resource_post_error(r, 0, "regions not supported");
}

static const struct wl_compositor_interface compositor_impl = {
	.create_surface = compositor_create_surface,
	.create_region = compositor_create_region,
};

static void
bind_compositor(struct wl_client *c, void *data, uint32_t version,
	uint32_t id)
{
	struct wl_resource *r;

	(void)data;
	r = wl_resource_create(c, &wl_compositor_interface, version, id);
	wl_resource_set_implementation(r, &compositor_impl, NULL, NULL);
}

static int
on_sigterm(int sig, void *data)
{
	(void)sig; (void)data;
	printf("server: SIGTERM via signalfd source\n");
	wl_display_terminate(sdisplay);
	return 0;
}

static int
on_watchdog(void *data)
{
	(void)data;
	fprintf(stderr, "server: watchdog expired\n");
	wl_display_terminate(sdisplay);
	return 0;
}

static int
run_server(const char *sock, int ready_fd)
{
	struct wl_event_loop *loop;
	struct wl_event_source *sig, *timer;

	if ((sdisplay = wl_display_create()) == NULL)
		FAIL("wl_display_create");
	if (wl_display_add_socket(sdisplay, sock) != 0)
		FAIL("wl_display_add_socket");
	if (wl_display_init_shm(sdisplay) != 0)
		FAIL("wl_display_init_shm");
	if (wl_global_create(sdisplay, &wl_compositor_interface, 4, NULL,
	    bind_compositor) == NULL)
		FAIL("wl_global_create");
	loop = wl_display_get_event_loop(sdisplay);
	sig = wl_event_loop_add_signal(loop, SIGTERM, on_sigterm, NULL);
	timer = wl_event_loop_add_timer(loop, on_watchdog, NULL);
	if (sig == NULL || timer == NULL)
		FAIL("event sources");
	wl_event_source_timer_update(timer, 30000);

	(void)write(ready_fd, "R", 1);
	close(ready_fd);
	wl_display_run(sdisplay);

	wl_event_source_remove(sig);
	wl_event_source_remove(timer);
	wl_display_destroy(sdisplay);
	printf("server: %s\n", server_ok ? "pixels OK" : "pixels WRONG");
	return server_ok ? 0 : 1;
}

/* ------------------------------------------------------------ client --- */

static struct wl_compositor *compositor;
static struct wl_shm *shm;
static int have_argb, frame_done, released;

static void
shm_format(void *data, struct wl_shm *s, uint32_t format)
{
	(void)data; (void)s;
	if (format == WL_SHM_FORMAT_ARGB8888)
		have_argb = 1;
}

static const struct wl_shm_listener shm_listener = { .format = shm_format };

static void
registry_global(void *data, struct wl_registry *reg, uint32_t name,
	const char *iface, uint32_t version)
{
	(void)data;
	if (strcmp(iface, wl_compositor_interface.name) == 0)
		compositor = wl_registry_bind(reg, name,
		    &wl_compositor_interface, version < 4 ? version : 4);
	else if (strcmp(iface, wl_shm_interface.name) == 0) {
		shm = wl_registry_bind(reg, name, &wl_shm_interface, 1);
		wl_shm_add_listener(shm, &shm_listener, NULL);
	}
}

static void
registry_remove(void *data, struct wl_registry *reg, uint32_t name)
{
	(void)data; (void)reg; (void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = registry_global,
	.global_remove = registry_remove,
};

static void
frame_cb(void *data, struct wl_callback *cb, uint32_t time)
{
	(void)data;
	if (time == 1234)
		frame_done = 1;
	wl_callback_destroy(cb);
}

static const struct wl_callback_listener frame_listener = { .done = frame_cb };

static void
buffer_release(void *data, struct wl_buffer *b)
{
	(void)data; (void)b;
	released = 1;
}

static const struct wl_buffer_listener buffer_listener = {
	.release = buffer_release,
};

static int
run_client(const char *sock)
{
	struct wl_display *d;
	struct wl_registry *reg;
	struct wl_shm_pool *pool;
	struct wl_buffer *buffer;
	struct wl_surface *surf;
	struct wl_callback *cb;
	pixman_image_t *img;
	pixman_color_t color = { 0x3333, 0x6666, 0xcccc, 0xffff };
	pixman_rectangle16_t rect = { 0, 0, W, H };
	char path[256];
	uint32_t *px;
	int fd, i, size = W * H * 4;

	if ((d = wl_display_connect(sock)) == NULL)
		FAIL("wl_display_connect");
	reg = wl_display_get_registry(d);
	wl_registry_add_listener(reg, &registry_listener, NULL);
	wl_display_roundtrip(d);	/* globals */
	wl_display_roundtrip(d);	/* shm formats */
	if (compositor == NULL || shm == NULL || !have_argb)
		FAIL("globals (compositor %p shm %p argb %d)",
		    (void *)compositor, (void *)shm, have_argb);
	printf("client: bound wl_compositor + wl_shm (ARGB8888)\n");

	/* The usual wl_shm pattern: an unlinked, ftruncate()d file. */
	snprintf(path, sizeof(path), "%s/wl-gate-XXXXXX",
	    getenv("XDG_RUNTIME_DIR"));
	if ((fd = mkstemp(path)) < 0)
		FAIL("mkstemp");
	unlink(path);
	if (ftruncate(fd, size) != 0)
		FAIL("ftruncate");
	px = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (px == MAP_FAILED)
		FAIL("mmap");

	/* Paint with pixman. */
	img = pixman_image_create_bits(PIXMAN_a8r8g8b8, W, H, px, W * 4);
	if (img == NULL)
		FAIL("pixman_image_create_bits");
	pixman_image_fill_rectangles(PIXMAN_OP_SRC, img, &color, 1, &rect);
	pixman_image_unref(img);
	if (px[0] != COLOR || px[W * H - 1] != COLOR)
		FAIL("pixman fill gave %08x", px[0]);
	printf("client: pixman filled %dx%d with %08x\n", W, H, px[0]);

	pool = wl_shm_create_pool(shm, fd, size);
	buffer = wl_shm_pool_create_buffer(pool, 0, W, H, W * 4,
	    WL_SHM_FORMAT_ARGB8888);
	wl_buffer_add_listener(buffer, &buffer_listener, NULL);
	wl_shm_pool_destroy(pool);
	close(fd);

	surf = wl_compositor_create_surface(compositor);
	cb = wl_surface_frame(surf);
	wl_callback_add_listener(cb, &frame_listener, NULL);
	wl_surface_attach(surf, buffer, 0, 0);
	wl_surface_damage(surf, 0, 0, W, H);
	wl_surface_commit(surf);

	for (i = 0; i < 100 && !(frame_done && released); i++)
		if (wl_display_dispatch(d) < 0)
			FAIL("dispatch");
	if (!frame_done || !released)
		FAIL("no frame callback/release");
	printf("client: frame callback + buffer release received\n");

	wl_buffer_destroy(buffer);
	wl_surface_destroy(surf);
	wl_display_disconnect(d);
	munmap(px, size);
	return 0;
}

/* ------------------------------------------------------------ xkb ------ */

static int
run_xkb(void)
{
	struct xkb_context *ctx;
	struct xkb_keymap *km;
	struct xkb_state *st;
	struct xkb_rule_names names = { "evdev", "pc105", "us", "", "" };
	xkb_keysym_t sym;
	char name[64];

	if ((ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS)) == NULL)
		FAIL("xkb_context_new");
	if ((km = xkb_keymap_new_from_names(ctx, &names,
	    XKB_KEYMAP_COMPILE_NO_FLAGS)) == NULL)
		FAIL("xkb keymap (us)");
	st = xkb_state_new(km);
	sym = xkb_state_key_get_one_sym(st, 38);	/* KEY_A + 8 */
	xkb_keysym_get_name(sym, name, sizeof(name));
	printf("xkb: keycode 38 -> %s\n", name);
	if (sym != XKB_KEY_a)
		FAIL("xkb keysym");
	xkb_state_update_key(st, 50, XKB_KEY_DOWN);	/* Shift_L */
	sym = xkb_state_key_get_one_sym(st, 38);
	if (sym != XKB_KEY_A)
		FAIL("xkb shifted keysym");
	xkb_state_unref(st);
	xkb_keymap_unref(km);
	xkb_context_unref(ctx);
	return 0;
}

int
main(void)
{
	const char *sock = "wl-gate-0";
	int pfd[2], status, rc;
	char c;
	pid_t pid;

	if (getenv("XDG_RUNTIME_DIR") == NULL)
		FAIL("XDG_RUNTIME_DIR not set");
	run_xkb();

	if (pipe(pfd) != 0)
		FAIL("pipe");
	if ((pid = fork()) == 0) {
		close(pfd[0]);
		_exit(run_server(sock, pfd[1]));
	}
	close(pfd[1]);
	if (read(pfd[0], &c, 1) != 1)
		FAIL("server did not start");

	rc = run_client(sock);

	kill(pid, SIGTERM);
	if (waitpid(pid, &status, 0) != pid)
		FAIL("waitpid");
	if (rc == 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0) {
		printf("WLGATE-OK\n");
		return 0;
	}
	fprintf(stderr, "WLGATE-FAIL: client %d server status %x\n", rc,
	    status);
	return 1;
}
