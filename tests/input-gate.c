/*
 * input-gate.c - Phase 5 gate: compositor-style input on MINIX.
 *
 * libseat (noop backend) opens the seat, libinput's udev backend finds the
 * input server's evdev devices through libudev-minix and opens them via
 * libseat, and xkbcommon turns key codes into text - the same path Weston
 * and wlroots take.  Real input is injected by the QEMU harness
 * (x86_qemu.py --input) when this prints HARNESS:INPUT:<name> lines:
 *
 *   keys:  sendkey a; sendkey shift-b        -> text "aB"
 *   mouse: mouse_move 20 10; mouse_button 1; mouse_button 0
 *          -> motion right/down, BTN_LEFT pressed and released
 *
 * Prints INPUTGATE-OK on success.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <libinput.h>
#include <libseat.h>
#include <libudev.h>
#include <xkbcommon/xkbcommon.h>

#define BTN_LEFT	0x110

#define FAIL(...) do { printf("INPUTGATE-FAIL: " __VA_ARGS__); \
	printf("\n"); exit(1); } while (0)

static struct libseat *seat;
static int seat_active;

static void
seat_enable(struct libseat *s, void *data)
{

	(void)s; (void)data;
	seat_active = 1;
}

static void
seat_disable(struct libseat *s, void *data)
{

	(void)data;
	seat_active = 0;
	libseat_disable_seat(s);
}

static struct libseat_seat_listener seat_listener = {
	.enable_seat = seat_enable,
	.disable_seat = seat_disable,
};

/* libinput opens devices through the seat, like a compositor does. */
struct dev_map { int fd, id; } devs[16];

static int
open_restricted(const char *path, int flags, void *data)
{
	int fd, id, i;

	(void)flags; (void)data;
	if ((id = libseat_open_device(seat, path, &fd)) < 0)
		return -errno;
	for (i = 0; i < 16; i++) {
		if (devs[i].fd == 0) {
			devs[i].fd = fd;
			devs[i].id = id;
			break;
		}
	}
	printf("opened %s (fd %d)\n", path, fd);
	return fd;
}

static void
close_restricted(int fd, void *data)
{
	int i;

	(void)data;
	for (i = 0; i < 16; i++) {
		if (devs[i].fd == fd) {
			libseat_close_device(seat, devs[i].id);
			devs[i].fd = 0;
		}
	}
	close(fd);
}

static const struct libinput_interface iface = {
	.open_restricted = open_restricted,
	.close_restricted = close_restricted,
};

static void
log_handler(struct libinput *li, enum libinput_log_priority prio,
	const char *fmt, va_list args)
{

	(void)li;
	printf("libinput[%d]: ", prio);
	vprintf(fmt, args);
}

static struct libinput *li;
static struct xkb_state *xkb;
static char text[64];
static int keyboards, pointers;
static double dx_sum, dy_sum;
static int btn_down, btn_up;

static void
handle(struct libinput_event *ev)
{
	struct libinput_device *dev = libinput_event_get_device(ev);
	struct libinput_event_keyboard *k;
	struct libinput_event_pointer *p;
	uint32_t key;
	char buf[16];

	switch (libinput_event_get_type(ev)) {
	case LIBINPUT_EVENT_DEVICE_ADDED:
		printf("device added: %s (%s)%s%s\n",
		    libinput_device_get_name(dev),
		    libinput_device_get_sysname(dev),
		    libinput_device_has_capability(dev,
		    LIBINPUT_DEVICE_CAP_KEYBOARD) ? " keyboard" : "",
		    libinput_device_has_capability(dev,
		    LIBINPUT_DEVICE_CAP_POINTER) ? " pointer" : "");
		if (libinput_device_has_capability(dev,
		    LIBINPUT_DEVICE_CAP_KEYBOARD))
			keyboards++;
		if (libinput_device_has_capability(dev,
		    LIBINPUT_DEVICE_CAP_POINTER))
			pointers++;
		break;
	case LIBINPUT_EVENT_KEYBOARD_KEY:
		k = libinput_event_get_keyboard_event(ev);
		key = libinput_event_keyboard_get_key(k);
		if (libinput_event_keyboard_get_key_state(k) ==
		    LIBINPUT_KEY_STATE_PRESSED) {
			xkb_state_key_get_utf8(xkb, key + 8, buf, sizeof(buf));
			if (buf[0] >= ' ' &&
			    strlen(text) + strlen(buf) < sizeof(text))
				strcat(text, buf);
			xkb_state_update_key(xkb, key + 8, XKB_KEY_DOWN);
		} else {
			xkb_state_update_key(xkb, key + 8, XKB_KEY_UP);
		}
		printf("key %u %s (time %u ms)\n", key,
		    libinput_event_keyboard_get_key_state(k) ==
		    LIBINPUT_KEY_STATE_PRESSED ? "down" : "up",
		    libinput_event_keyboard_get_time(k));
		break;
	case LIBINPUT_EVENT_POINTER_MOTION:
		p = libinput_event_get_pointer_event(ev);
		dx_sum += libinput_event_pointer_get_dx_unaccelerated(p);
		dy_sum += libinput_event_pointer_get_dy_unaccelerated(p);
		break;
	case LIBINPUT_EVENT_POINTER_BUTTON:
		p = libinput_event_get_pointer_event(ev);
		if (libinput_event_pointer_get_button(p) == BTN_LEFT) {
			if (libinput_event_pointer_get_button_state(p) ==
			    LIBINPUT_BUTTON_STATE_PRESSED)
				btn_down++;
			else
				btn_up++;
		}
		printf("button %u %s\n", libinput_event_pointer_get_button(p),
		    libinput_event_pointer_get_button_state(p) ==
		    LIBINPUT_BUTTON_STATE_PRESSED ? "down" : "up");
		break;
	default:
		break;
	}
}

/* Dispatch libinput (and the seat) until 'done' returns true or timeout. */
static int
run(int secs, int (*done)(void))
{
	struct pollfd pfd[2];
	struct libinput_event *ev;
	time_t end = time(NULL) + secs;

	while (!done()) {
		if (time(NULL) >= end)
			return 0;
		pfd[0].fd = libinput_get_fd(li);
		pfd[0].events = POLLIN;
		pfd[1].fd = libseat_get_fd(seat);
		pfd[1].events = POLLIN;
		if (poll(pfd, 2, 200) < 0 && errno != EINTR)
			FAIL("poll: %s", strerror(errno));
		if (pfd[1].revents & POLLIN)
			libseat_dispatch(seat, 0);
		if (libinput_dispatch(li) != 0)
			FAIL("libinput_dispatch");
		while ((ev = libinput_get_event(li)) != NULL) {
			handle(ev);
			libinput_event_destroy(ev);
		}
	}
	return 1;
}

static int devices_done(void) { return keyboards >= 1 && pointers >= 1; }
static int keys_done(void) { return strcmp(text, "aB") == 0; }
static int mouse_done(void) { return btn_up >= 1 && dx_sum > 0 && dy_sum > 0; }

int
main(void)
{
	struct xkb_rule_names names = { "evdev", "pc105", "us", "", "" };
	struct xkb_context *ctx;
	struct xkb_keymap *km;
	struct udev *udev;

	setvbuf(stdout, NULL, _IONBF, 0);

	/* Seat: the noop backend is enabled at the first dispatch. */
	if ((seat = libseat_open_seat(&seat_listener, NULL)) == NULL)
		FAIL("libseat_open_seat: %s", strerror(errno));
	while (!seat_active)
		if (libseat_dispatch(seat, 1000) < 0)
			FAIL("libseat_dispatch");
	printf("seat %s active\n", libseat_seat_name(seat));

	if ((ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS)) == NULL ||
	    (km = xkb_keymap_new_from_names(ctx, &names,
	    XKB_KEYMAP_COMPILE_NO_FLAGS)) == NULL ||
	    (xkb = xkb_state_new(km)) == NULL)
		FAIL("xkbcommon keymap");

	if ((udev = udev_new()) == NULL)
		FAIL("udev_new");
	if ((li = libinput_udev_create_context(&iface, NULL, udev)) == NULL)
		FAIL("libinput_udev_create_context");
	libinput_log_set_handler(li, log_handler);
	libinput_log_set_priority(li, LIBINPUT_LOG_PRIORITY_INFO);
	if (libinput_udev_assign_seat(li, libseat_seat_name(seat)) != 0)
		FAIL("libinput_udev_assign_seat");

	if (!run(10, devices_done))
		FAIL("devices: %d keyboard(s), %d pointer(s)", keyboards,
		    pointers);

	printf("\nHARNESS:INPUT:keys\n");
	if (!run(20, keys_done))
		FAIL("typed text \"%s\", expected \"aB\"", text);
	printf("typed \"%s\"\n", text);

	printf("\nHARNESS:INPUT:mouse\n");
	if (!run(20, mouse_done))
		FAIL("mouse: dx %.1f dy %.1f, left button down %d up %d",
		    dx_sum, dy_sum, btn_down, btn_up);
	printf("pointer moved by (%.1f, %.1f), left click\n", dx_sum, dy_sum);
	if (btn_down != 1)
		FAIL("left button pressed %d times", btn_down);

	libinput_unref(li);
	udev_unref(udev);
	libseat_close_seat(seat);
	xkb_state_unref(xkb);
	xkb_keymap_unref(km);
	xkb_context_unref(ctx);

	printf("INPUTGATE-OK\n");
	return 0;
}
