/*
 * drm-demo - Phase 3 gate: drive the MINIX DRM-lite device purely through
 * the libdrm API, the way a KMS compositor does (legacy, non-atomic path):
 * resources -> connector/encoder/CRTC -> primary plane via universal planes
 * -> two dumb buffers + ADDFB2 -> SETCRTC -> page flips paced by flip
 * events (drmHandleEvent) -> test card left on screen for a screendump.
 * The buffers go through PRIME like wlroots' GBM allocator path: created on
 * a second "allocator" open, exported as dma-buf fds, drawn through the
 * dma-buf mapping, and imported into the modesetting fd for ADDFB2.
 *
 *   drm-demo [hold-seconds]
 *
 * Prints "DRMDEMO-OK ..." on success.
 */

#include <sys/mman.h>
#include <sys/select.h>
#include <sys/time.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <xf86drm.h>
#include <xf86drmMode.h>
#include <drm_fourcc.h>

#define FAIL(...) do { printf("DRMDEMO-FAIL: " __VA_ARGS__); \
	printf(" (errno %d %s)\n", errno, strerror(errno)); exit(1); } while (0)

#define W 800
#define H 600
#define FRAMES 30

struct buf {
	uint32_t handle, pitch, fb;
	int dmabuf;
	uint64_t size;
	uint32_t *px;
};

static int flips_done;
static unsigned int last_crtc;

static void
flip_handler(int fd, unsigned int seq, unsigned int sec, unsigned int usec,
	unsigned int crtc_id, void *data)
{
	(void)fd; (void)seq; (void)sec; (void)usec; (void)data;
	last_crtc = crtc_id;
	flips_done++;
}

/* Allocate on afd, share with fd through a dma-buf fd. */
static void
make_buf(int fd, int afd, struct buf *b)
{
	uint32_t ahandle, h2;
	uint64_t dsize;

	if (drmModeCreateDumbBuffer(afd, W, H, 32, 0, &ahandle, &b->pitch,
	    &b->size) != 0)
		FAIL("create dumb");
	if (drmPrimeHandleToFD(afd, ahandle, DRM_CLOEXEC | DRM_RDWR,
	    &b->dmabuf) != 0)
		FAIL("prime export");
	if (drmMinixDmabufSize(b->dmabuf, &dsize) != 0 || dsize != b->size)
		FAIL("dma-buf size");
	if (drmPrimeFDToHandle(fd, b->dmabuf, &b->handle) != 0)
		FAIL("prime import");
	if (drmPrimeFDToHandle(fd, b->dmabuf, &h2) != 0 || h2 != b->handle)
		FAIL("prime re-import gave another handle");
	/* The allocator's handle can go: the dma-buf and import keep it. */
	if (drmCloseBufferHandle(afd, ahandle) != 0)
		FAIL("close allocator handle");
	uint32_t handles[4] = { b->handle }, pitches[4] = { b->pitch };
	uint32_t offsets[4] = { 0 };
	if (drmModeAddFB2(fd, W, H, DRM_FORMAT_XRGB8888, handles, pitches,
	    offsets, &b->fb, 0) != 0)
		FAIL("addfb2");
	/* Like wlroots: the framebuffer keeps the buffer, the handle can go. */
	if (drmCloseBufferHandle(fd, b->handle) != 0)
		FAIL("close imported handle");
	b->handle = 0;
	b->px = mmap(NULL, b->size, PROT_READ | PROT_WRITE, MAP_SHARED,
	    b->dmabuf, 0);
	if (b->px == MAP_FAILED)
		FAIL("mmap dma-buf");
}

static void
draw(struct buf *b, int frame, int card)
{
	for (int y = 0; y < H; y++)
		for (int x = 0; x < W; x++) {
			uint32_t c;
			if (card)
				c = y < H / 2 ? (x < W / 2 ? 0xff0000 : 0x00ff00)
				    : (x < W / 2 ? 0x0000ff : 0xffffff);
			else	/* moving bar */
				c = ((x + frame * 8) % 200) < 100 ? 0x404040 :
				    0x202020;
			b->px[y * (b->pitch / 4) + x] = c;
		}
}

int
main(int argc, char **argv)
{
	int hold = argc > 1 ? atoi(argv[1]) : 0;
	int fd = open("/dev/drm0", O_RDWR | O_CLOEXEC);
	if (fd < 0)
		FAIL("open /dev/drm0");

	drmVersionPtr v = drmGetVersion(fd);
	if (v == NULL)
		FAIL("drmGetVersion");
	char *node = drmGetDeviceNameFromFd2(fd);
	uint64_t cap = 0;
	if (drmGetCap(fd, DRM_CAP_DUMB_BUFFER, &cap) != 0 || cap != 1)
		FAIL("dumb buffer cap");
	if (!drmIsMaster(fd))
		FAIL("not master");
	if (drmSetClientCap(fd, DRM_CLIENT_CAP_ATOMIC, 1) == 0)
		FAIL("atomic unexpectedly accepted");
	if (drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) != 0)
		FAIL("universal planes");
	printf("driver %s %d.%d (%s), node %s\n", v->name, v->version_major,
	    v->version_minor, v->desc, node ? node : "?");
	if (node == NULL || strcmp(node, "/dev/drm0") != 0)
		FAIL("device name");
	drmFreeVersion(v);
	free(node);

	drmModeRes *res = drmModeGetResources(fd);
	if (res == NULL || res->count_connectors < 1 || res->count_crtcs < 1)
		FAIL("resources");
	drmModeConnector *conn = drmModeGetConnector(fd, res->connectors[0]);
	if (conn == NULL || conn->connection != DRM_MODE_CONNECTED ||
	    conn->count_modes < 1)
		FAIL("connector");

	/* What wlroots' DRM backend and allocator need besides KMS. */
	uint32_t dpms_prop = 0;
	drmModeObjectProperties *cp = drmModeObjectGetProperties(fd,
	    conn->connector_id, DRM_MODE_OBJECT_CONNECTOR);
	for (uint32_t i = 0; cp != NULL && i < cp->count_props; i++) {
		drmModePropertyRes *pr = drmModeGetProperty(fd, cp->props[i]);
		if (pr != NULL && strcmp(pr->name, "DPMS") == 0 &&
		    (pr->flags & DRM_MODE_PROP_ENUM) && pr->count_enums == 4)
			dpms_prop = pr->prop_id;
		drmModeFreeProperty(pr);
	}
	drmModeFreeObjectProperties(cp);
	if (dpms_prop == 0)
		FAIL("connector DPMS property");
	if (drmModeConnectorSetProperty(fd, conn->connector_id, dpms_prop,
	    DRM_MODE_DPMS_ON) != 0)
		FAIL("set DPMS");
	uint32_t lessee;
	int lr = drmModeCreateLease(fd, NULL, 0, O_CLOEXEC, &lessee);
	if (lr != -EINVAL && lr != -EOPNOTSUPP)
		FAIL("drmModeCreateLease returned %d", lr);
	if (drmGetNodeTypeFromFd(fd) != DRM_NODE_PRIMARY)
		FAIL("node type");
	int rfd = open("/dev/drm0", O_RDWR | O_CLOEXEC);
	drm_magic_t magic;
	if (rfd < 0 || drmGetMagic(rfd, &magic) != 0 || magic == 0 ||
	    drmAuthMagic(fd, magic) != 0)
		FAIL("magic authentication");
	close(rfd);
	uint64_t vbl_cap;
	if (drmGetCap(fd, DRM_CAP_CRTC_IN_VBLANK_EVENT, &vbl_cap) != 0 ||
	    vbl_cap != 1)
		FAIL("CRTC_IN_VBLANK_EVENT");
	if (drmModeSetCursor(fd, res->crtcs[0], 0, 0, 0) != 0)
		FAIL("hiding the (absent) cursor");
	printf("wlroots DRM prerequisites ok\n");
	drmModeModeInfo *mode = NULL, *pref = NULL;
	for (int i = 0; i < conn->count_modes; i++) {
		if (conn->modes[i].hdisplay == W && conn->modes[i].vdisplay == H)
			mode = &conn->modes[i];
		if (conn->modes[i].type & DRM_MODE_TYPE_PREFERRED)
			pref = &conn->modes[i];
	}
	if (mode == NULL || pref == NULL)
		FAIL("modes");
	printf("connector %u type %u: %d modes, preferred %s @%u Hz, %ux%u mm\n",
	    conn->connector_id, conn->connector_type, conn->count_modes,
	    pref->name, pref->vrefresh, conn->mmWidth, conn->mmHeight);
	drmModeEncoder *enc = drmModeGetEncoder(fd, conn->encoders[0]);
	if (enc == NULL || !(enc->possible_crtcs & 1))
		FAIL("encoder");
	uint32_t crtc_id = res->crtcs[0];

	/* Primary plane, identified through its "type" property. */
	drmModePlaneRes *pres = drmModeGetPlaneResources(fd);
	if (pres == NULL || pres->count_planes != 1)
		FAIL("plane resources");
	drmModeObjectProperties *props = drmModeObjectGetProperties(fd,
	    pres->planes[0], DRM_MODE_OBJECT_PLANE);
	if (props == NULL || props->count_props != 1)
		FAIL("plane props");
	drmModePropertyRes *p = drmModeGetProperty(fd, props->props[0]);
	if (p == NULL || strcmp(p->name, "type") != 0 ||
	    props->prop_values[0] != DRM_PLANE_TYPE_PRIMARY ||
	    p->count_enums != 3 || strcmp(p->enums[1].name, "Primary") != 0)
		FAIL("plane type property");
	drmModePlane *plane = drmModeGetPlane(fd, pres->planes[0]);
	if (plane == NULL || plane->count_formats < 1 ||
	    plane->formats[0] != DRM_FORMAT_XRGB8888)
		FAIL("plane");

	if (drmGetCap(fd, DRM_CAP_PRIME, &cap) != 0 ||
	    cap != (DRM_PRIME_CAP_IMPORT | DRM_PRIME_CAP_EXPORT))
		FAIL("PRIME cap");
	int afd = open("/dev/drm0", O_RDWR | O_CLOEXEC);
	if (afd < 0)
		FAIL("open allocator fd");
	struct buf b[2];
	make_buf(fd, afd, &b[0]);
	make_buf(fd, afd, &b[1]);
	close(afd);
	printf("PRIME: buffers shared via dma-buf fds %d %d\n", b[0].dmabuf,
	    b[1].dmabuf);
	draw(&b[0], 0, 0);
	if (drmModeSetCrtc(fd, crtc_id, b[0].fb, 0, 0, &conn->connector_id, 1,
	    mode) != 0)
		FAIL("setcrtc");
	drmModeCrtc *crtc = drmModeGetCrtc(fd, crtc_id);
	if (crtc == NULL || crtc->buffer_id != b[0].fb || !crtc->mode_valid ||
	    crtc->mode.hdisplay != W)
		FAIL("getcrtc");

	drmEventContext ev = { .version = 3,
	    .page_flip_handler2 = flip_handler };
	struct timeval t0, t1;
	gettimeofday(&t0, NULL);
	int cur = 0;
	for (int f = 1; f <= FRAMES; f++) {
		cur ^= 1;
		draw(&b[cur], f, f == FRAMES);
		if (drmModePageFlip(fd, crtc_id, b[cur].fb,
		    DRM_MODE_PAGE_FLIP_EVENT, NULL) != 0)
			FAIL("page flip %d", f);
		while (flips_done < f) {
			fd_set rfds;
			struct timeval tv = { 1, 0 };
			FD_ZERO(&rfds);
			FD_SET(fd, &rfds);
			int r = select(fd + 1, &rfds, NULL, NULL, &tv);
			if (r <= 0)
				FAIL("no flip event (frame %d)", f);
			drmHandleEvent(fd, &ev);
		}
	}
	gettimeofday(&t1, NULL);
	double secs = (t1.tv_sec - t0.tv_sec) + (t1.tv_usec - t0.tv_usec) / 1e6;
	double fps = FRAMES / secs;
	if (last_crtc != crtc_id)
		FAIL("event crtc %u != %u", last_crtc, crtc_id);
	if (fps < 30 || fps > 75)
		FAIL("flip rate %.1f fps", fps);

	printf("DRMDEMO-OK frames=%d fps=%.1f\n", FRAMES, fps);
	fflush(stdout);
	if (hold > 0)
		sleep(hold);

	if (drmModeRmFB(fd, b[cur].fb) != 0)	/* turns the CRTC off */
		FAIL("rmfb");
	crtc = drmModeGetCrtc(fd, crtc_id);
	if (crtc == NULL || crtc->mode_valid)
		FAIL("crtc still on after rmfb");
	close(fd);
	return 0;
}
