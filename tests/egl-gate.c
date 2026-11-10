/*
 * egl-gate - Phase 7 gate: Mesa OpenGL ES 2 (softpipe) through EGL.
 *
 *   egl-gate surfaceless
 *	EGL_PLATFORM_SURFACELESS_MESA (swrast), a pbuffer, a GLSL program;
 *	draws a red triangle on blue and checks the pixels with glReadPixels.
 *   egl-gate gbm [hold-seconds]
 *	GBM on /dev/drm0 (Mesa's DRI backend -> kms_swrast, i.e. softpipe
 *	rendering into DRM-lite dumb buffers), EGL_PLATFORM_GBM_KHR window
 *	surface, FRAMES animated frames scanned out with libdrm (SETCRTC,
 *	then event-paced page flips); the last frame (triangle upright) stays
 *	on screen for hold-seconds so the harness can take a screendump.
 *   egl-gate dmabuf
 *	wlroots' GLES2 renderer path: GBM device + EGL_PLATFORM_GBM_KHR,
 *	configless surfaceless context, a GBM buffer exported as a dma-buf
 *	fd (PRIME), imported with EGL_EXT_image_dma_buf_import and rendered
 *	to as a renderbuffer (glEGLImageTargetRenderbufferStorageOES); the
 *	pixels are checked through the dma-buf mapping and in another DRM
 *	client that imports the same buffer.
 *
 * Prints EGL-SURFACELESS-OK / EGL-GBM-OK / EGL-DMABUF-OK, or EGL-FAIL: ...
 * and exits 1.
 */
#include <sys/select.h>
#include <sys/time.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <sys/mman.h>
#include <drm_fourcc.h>
#include <gbm.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#define FAIL(...) do { printf("EGL-FAIL: " __VA_ARGS__); \
	printf(" (egl 0x%x, gl 0x%x, errno %d)\n", eglGetError(), \
	    glGetError(), errno); exit(1); } while (0)

#define FRAMES 30

static const char *vs_src =
	"attribute vec2 pos;\n"
	"uniform float angle;\n"
	"void main() {\n"
	"	float c = cos(angle), s = sin(angle);\n"
	"	gl_Position = vec4(c * pos.x - s * pos.y,\n"
	"	    s * pos.x + c * pos.y, 0.0, 1.0);\n"
	"}\n";
static const char *fs_src =
	"precision mediump float;\n"
	"uniform vec4 color;\n"
	"void main() {\n"
	"	gl_FragColor = color;\n"
	"}\n";

static GLuint prog;
static GLint u_angle, u_color;

static GLuint
shader(GLenum type, const char *src)
{
	GLuint s = glCreateShader(type);
	GLint ok;
	char log[512];

	glShaderSource(s, 1, &src, NULL);
	glCompileShader(s);
	glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
	if (!ok) {
		glGetShaderInfoLog(s, sizeof(log), NULL, log);
		FAIL("shader compile: %s", log);
	}
	return s;
}

static void
gl_setup(void)
{
	static const GLfloat tri[] = { -0.5f, -0.5f, 0.5f, -0.5f, 0.0f, 0.6f };
	GLint ok;

	printf("GL_VENDOR %s\nGL_RENDERER %s\nGL_VERSION %s\nGLSL %s\n",
	    glGetString(GL_VENDOR), glGetString(GL_RENDERER),
	    glGetString(GL_VERSION),
	    glGetString(GL_SHADING_LANGUAGE_VERSION));
	prog = glCreateProgram();
	glAttachShader(prog, shader(GL_VERTEX_SHADER, vs_src));
	glAttachShader(prog, shader(GL_FRAGMENT_SHADER, fs_src));
	glBindAttribLocation(prog, 0, "pos");
	glLinkProgram(prog);
	glGetProgramiv(prog, GL_LINK_STATUS, &ok);
	if (!ok)
		FAIL("program link");
	glUseProgram(prog);
	u_angle = glGetUniformLocation(prog, "angle");
	u_color = glGetUniformLocation(prog, "color");
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, tri);
	glEnableVertexAttribArray(0);
}

/* Blue background, red triangle rotated by 'angle' radians. */
static void
draw(int w, int h, float angle)
{
	glViewport(0, 0, w, h);
	glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	glUniform1f(u_angle, angle);
	glUniform4f(u_color, 1.0f, 0.0f, 0.0f, 1.0f);
	glDrawArrays(GL_TRIANGLES, 0, 3);
	if (glGetError() != GL_NO_ERROR)
		FAIL("draw");
}

static EGLDisplay
get_display(EGLenum platform, void *native)
{
	PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
	    (PFNEGLGETPLATFORMDISPLAYEXTPROC)
	    eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay dpy;
	EGLint major, minor;

	printf("client extensions: %s\n",
	    eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS));
	if (get_platform_display == NULL)
		FAIL("no eglGetPlatformDisplayEXT");
	dpy = get_platform_display(platform, native, NULL);
	if (dpy == EGL_NO_DISPLAY)
		FAIL("eglGetPlatformDisplayEXT");
	if (!eglInitialize(dpy, &major, &minor))
		FAIL("eglInitialize");
	printf("EGL %d.%d %s (%s)\n", major, minor,
	    eglQueryString(dpy, EGL_VENDOR), eglQueryString(dpy, EGL_VERSION));
	if (!eglBindAPI(EGL_OPENGL_ES_API))
		FAIL("eglBindAPI");
	return dpy;
}

static EGLContext
make_context(EGLDisplay dpy, EGLConfig cfg)
{
	static const EGLint ctx_attr[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE
	};
	EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);

	if (ctx == EGL_NO_CONTEXT)
		FAIL("eglCreateContext");
	return ctx;
}

static int
surfaceless(void)
{
	static const EGLint cfg_attr[] = {
		EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE
	};
	static const EGLint pb_attr[] = { EGL_WIDTH, 64, EGL_HEIGHT, 64,
		EGL_NONE };
	EGLDisplay dpy = get_display(EGL_PLATFORM_SURFACELESS_MESA,
	    EGL_DEFAULT_DISPLAY);
	EGLConfig cfg;
	EGLint n;
	EGLSurface surf;
	uint8_t px[64 * 64 * 4];

	if (!eglChooseConfig(dpy, cfg_attr, &cfg, 1, &n) || n < 1)
		FAIL("eglChooseConfig");
	surf = eglCreatePbufferSurface(dpy, cfg, pb_attr);
	if (surf == EGL_NO_SURFACE)
		FAIL("eglCreatePbufferSurface");
	if (!eglMakeCurrent(dpy, surf, surf, make_context(dpy, cfg)))
		FAIL("eglMakeCurrent");
	gl_setup();
	draw(64, 64, 0.0f);
	glFinish();
	glReadPixels(0, 0, 64, 64, GL_RGBA, GL_UNSIGNED_BYTE, px);
	/* Center (inside the triangle) red, corner blue. */
	uint8_t *c = &px[(32 * 64 + 32) * 4], *k = &px[(2 * 64 + 2) * 4];
	printf("center %u,%u,%u corner %u,%u,%u\n", c[0], c[1], c[2], k[0],
	    k[1], k[2]);
	if (c[0] < 250 || c[1] > 5 || c[2] > 5)
		FAIL("center pixel not red");
	if (k[0] > 5 || k[1] > 5 || k[2] < 250)
		FAIL("corner pixel not blue");
	eglTerminate(dpy);
	printf("EGL-SURFACELESS-OK\n");
	return 0;
}

/* ------------------------------------------------------------------ gbm */

static int flip_pending;

static void
flip_handler(int fd, unsigned int seq, unsigned int sec, unsigned int usec,
	void *data)
{
	(void)fd; (void)seq; (void)sec; (void)usec; (void)data;
	flip_pending = 0;
}

static void
destroy_fb(struct gbm_bo *bo, void *data)
{
	int fd = gbm_device_get_fd(gbm_bo_get_device(bo));
	uint32_t fb = (uint32_t)(uintptr_t)data;

	drmModeRmFB(fd, fb);
}

static uint32_t
bo_fb(int fd, struct gbm_bo *bo)
{
	uint32_t fb = (uint32_t)(uintptr_t)gbm_bo_get_user_data(bo);

	if (fb != 0)
		return fb;
	if (drmModeAddFB(fd, gbm_bo_get_width(bo), gbm_bo_get_height(bo), 24,
	    32, gbm_bo_get_stride(bo), gbm_bo_get_handle(bo).u32, &fb) != 0)
		FAIL("drmModeAddFB");
	gbm_bo_set_user_data(bo, (void *)(uintptr_t)fb, destroy_fb);
	return fb;
}

static double
now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int
gbm(int hold)
{
	static const EGLint cfg_attr[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 0,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE
	};
	drmEventContext ev = { .version = 2,
		.page_flip_handler = flip_handler };
	EGLConfig cfgs[64], cfg = NULL;
	EGLint n, id;
	int fd, i, w, h;
	double t0;

	if ((fd = open("/dev/drm0", O_RDWR | O_CLOEXEC)) < 0)
		FAIL("open /dev/drm0");
	drmModeRes *res = drmModeGetResources(fd);
	if (res == NULL || res->count_connectors < 1 || res->count_crtcs < 1)
		FAIL("drm resources");
	drmModeConnector *conn = drmModeGetConnector(fd, res->connectors[0]);
	if (conn == NULL || conn->count_modes < 1)
		FAIL("connector");
	drmModeModeInfo *mode = &conn->modes[0];
	for (i = 0; i < conn->count_modes; i++)
		if (conn->modes[i].type & DRM_MODE_TYPE_PREFERRED)
			mode = &conn->modes[i];
	w = mode->hdisplay;
	h = mode->vdisplay;
	uint32_t crtc = res->crtcs[0], conn_id = conn->connector_id;
	printf("mode %s (%dx%d)\n", mode->name, w, h);

	struct gbm_device *dev = gbm_create_device(fd);
	if (dev == NULL)
		FAIL("gbm_create_device");
	printf("gbm backend %s\n", gbm_device_get_backend_name(dev));
	struct gbm_surface *gs = gbm_surface_create(dev, w, h,
	    GBM_FORMAT_XRGB8888, GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING);
	if (gs == NULL)
		FAIL("gbm_surface_create");

	EGLDisplay dpy = get_display(EGL_PLATFORM_GBM_KHR, dev);
	if (!eglChooseConfig(dpy, cfg_attr, cfgs, 64, &n) || n < 1)
		FAIL("eglChooseConfig");
	for (i = 0; i < n; i++)
		if (eglGetConfigAttrib(dpy, cfgs[i], EGL_NATIVE_VISUAL_ID,
		    &id) && (uint32_t)id == GBM_FORMAT_XRGB8888) {
			cfg = cfgs[i];
			break;
		}
	if (cfg == NULL)
		FAIL("no XRGB8888 config");
	EGLSurface es = eglCreateWindowSurface(dpy, cfg,
	    (EGLNativeWindowType)gs, NULL);
	if (es == EGL_NO_SURFACE)
		FAIL("eglCreateWindowSurface");
	if (!eglMakeCurrent(dpy, es, es, make_context(dpy, cfg)))
		FAIL("eglMakeCurrent");
	gl_setup();

	struct gbm_bo *prev = NULL;
	t0 = now();
	for (i = 0; i < FRAMES; i++) {
		/* One turn over the run; the last frame is upright. */
		draw(w, h, 2.0f * (float)M_PI * (FRAMES - 1 - i) / FRAMES);
		if (!eglSwapBuffers(dpy, es))
			FAIL("eglSwapBuffers");
		struct gbm_bo *bo = gbm_surface_lock_front_buffer(gs);
		if (bo == NULL)
			FAIL("gbm_surface_lock_front_buffer");
		uint32_t fb = bo_fb(fd, bo);
		if (i == 0) {
			if (drmModeSetCrtc(fd, crtc, fb, 0, 0, &conn_id, 1,
			    mode) != 0)
				FAIL("drmModeSetCrtc");
		} else {
			flip_pending = 1;
			if (drmModePageFlip(fd, crtc, fb,
			    DRM_MODE_PAGE_FLIP_EVENT, NULL) != 0)
				FAIL("drmModePageFlip");
			while (flip_pending) {
				fd_set fds;
				FD_ZERO(&fds);
				FD_SET(fd, &fds);
				if (select(fd + 1, &fds, NULL, NULL, NULL) < 0)
					FAIL("select");
				drmHandleEvent(fd, &ev);
			}
		}
		if (prev != NULL)
			gbm_surface_release_buffer(gs, prev);
		prev = bo;
	}
	printf("EGL-GBM-OK %d frames %dx%d in %.1f s\n", FRAMES, w, h,
	    now() - t0);
	fflush(stdout);
	if (hold > 0)
		sleep(hold);
	return 0;
}

static int
has_ext(const char *list, const char *ext)
{
	size_t n = strlen(ext);
	const char *p = list;

	while (p != NULL && (p = strstr(p, ext)) != NULL) {
		if ((p == list || p[-1] == ' ') && (p[n] == ' ' || p[n] == 0))
			return 1;
		p += n;
	}
	return 0;
}

static int
dmabuf(void)
{
	const int w = 64, h = 48;
	int fd = open("/dev/drm0", O_RDWR | O_CLOEXEC);
	if (fd < 0)
		FAIL("open /dev/drm0");
	struct gbm_device *dev = gbm_create_device(fd);
	if (dev == NULL)
		FAIL("gbm_create_device");
	EGLDisplay dpy = get_display(EGL_PLATFORM_GBM_KHR, dev);
	const char *ext = eglQueryString(dpy, EGL_EXTENSIONS);
	printf("display extensions: %s\n", ext);
	static const char *const need_egl[] = {
		"EGL_EXT_image_dma_buf_import", "EGL_KHR_surfaceless_context",
		"EGL_KHR_image_base",
	};
	for (unsigned i = 0; i < sizeof(need_egl) / sizeof(need_egl[0]); i++)
		if (!has_ext(ext, need_egl[i]))
			FAIL("missing %s", need_egl[i]);
	if (!has_ext(ext, "EGL_KHR_no_config_context") &&
	    !has_ext(ext, "EGL_MESA_configless_context"))
		FAIL("no configless contexts");

	static const EGLint ctx_attr[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE
	};
	EGLContext ctx = eglCreateContext(dpy, EGL_NO_CONFIG_KHR,
	    EGL_NO_CONTEXT, ctx_attr);
	if (ctx == EGL_NO_CONTEXT)
		FAIL("configless eglCreateContext");
	if (!eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx))
		FAIL("surfaceless eglMakeCurrent");
	const char *glext = (const char *)glGetString(GL_EXTENSIONS);
	static const char *const need_gl[] = {
		"GL_OES_EGL_image", "GL_EXT_texture_format_BGRA8888",
		"GL_EXT_unpack_subimage",
	};
	for (unsigned i = 0; i < sizeof(need_gl) / sizeof(need_gl[0]); i++)
		if (!has_ext(glext, need_gl[i]))
			FAIL("missing %s", need_gl[i]);

	struct gbm_bo *bo = gbm_bo_create(dev, w, h, GBM_FORMAT_XRGB8888,
	    GBM_BO_USE_RENDERING | GBM_BO_USE_SCANOUT | GBM_BO_USE_LINEAR);
	if (bo == NULL)
		FAIL("gbm_bo_create");
	int dfd = gbm_bo_get_fd(bo);
	uint32_t stride = gbm_bo_get_stride(bo);
	if (dfd < 0 || stride < (uint32_t)w * 4)
		FAIL("gbm_bo_get_fd/stride (%d, %u)", dfd, stride);
	printf("gbm bo %dx%d stride %u exported as dma-buf fd %d\n", w, h,
	    stride, dfd);

	PFNEGLCREATEIMAGEKHRPROC create_image = (PFNEGLCREATEIMAGEKHRPROC)
	    eglGetProcAddress("eglCreateImageKHR");
	PFNEGLDESTROYIMAGEKHRPROC destroy_image = (PFNEGLDESTROYIMAGEKHRPROC)
	    eglGetProcAddress("eglDestroyImageKHR");
	PFNGLEGLIMAGETARGETRENDERBUFFERSTORAGEOESPROC image_rb =
	    (PFNGLEGLIMAGETARGETRENDERBUFFERSTORAGEOESPROC)
	    eglGetProcAddress("glEGLImageTargetRenderbufferStorageOES");
	if (create_image == NULL || destroy_image == NULL || image_rb == NULL)
		FAIL("EGLImage entry points");
	EGLint attr[] = {
		EGL_WIDTH, w, EGL_HEIGHT, h,
		EGL_LINUX_DRM_FOURCC_EXT, DRM_FORMAT_XRGB8888,
		EGL_DMA_BUF_PLANE0_FD_EXT, dfd,
		EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0,
		EGL_DMA_BUF_PLANE0_PITCH_EXT, (EGLint)stride,
		EGL_NONE
	};
	EGLImageKHR img = create_image(dpy, EGL_NO_CONTEXT,
	    EGL_LINUX_DMA_BUF_EXT, NULL, attr);
	if (img == EGL_NO_IMAGE_KHR)
		FAIL("eglCreateImageKHR(dma-buf) 0x%x", eglGetError());

	GLuint rb, fbo;
	glGenRenderbuffers(1, &rb);
	glBindRenderbuffer(GL_RENDERBUFFER, rb);
	image_rb(GL_RENDERBUFFER, img);
	glGenFramebuffers(1, &fbo);
	glBindFramebuffer(GL_FRAMEBUFFER, fbo);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
	    GL_RENDERBUFFER, rb);
	if (glCheckFramebufferStatus(GL_FRAMEBUFFER) !=
	    GL_FRAMEBUFFER_COMPLETE)
		FAIL("dma-buf framebuffer incomplete");
	glViewport(0, 0, w, h);
	glClearColor(0.0f, 1.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	glFinish();
	if (glGetError() != GL_NO_ERROR)
		FAIL("render into dma-buf");

	/* The pixels are in the shared buffer: via the dma-buf mapping ... */
	uint32_t *px = mmap(NULL, stride * h, PROT_READ, MAP_SHARED, dfd, 0);
	if (px == MAP_FAILED)
		FAIL("mmap dma-buf");
	if ((px[0] & 0xffffff) != 0x00ff00 ||
	    (px[(h - 1) * (stride / 4) + w - 1] & 0xffffff) != 0x00ff00)
		FAIL("dma-buf pixels %#x %#x", px[0],
		    px[(h - 1) * (stride / 4) + w - 1]);
	/* ... and in another client that imports it (the DRM backend). */
	int fd2 = open("/dev/drm0", O_RDWR | O_CLOEXEC);
	uint32_t h2;
	uint64_t off;
	if (fd2 < 0 || drmPrimeFDToHandle(fd2, dfd, &h2) != 0)
		FAIL("import into second client");
	if (drmModeMapDumbBuffer(fd2, h2, &off) != 0)
		FAIL("map imported buffer");
	uint32_t *px2 = mmap(NULL, stride * h, PROT_READ, MAP_SHARED, fd2,
	    off);
	if (px2 == MAP_FAILED || (px2[w / 2] & 0xffffff) != 0x00ff00)
		FAIL("pixels in importing client");

	destroy_image(dpy, img);
	glDeleteFramebuffers(1, &fbo);
	glDeleteRenderbuffers(1, &rb);
	gbm_bo_destroy(bo);
	close(dfd);
	close(fd2);
	eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	eglDestroyContext(dpy, ctx);
	eglTerminate(dpy);
	gbm_device_destroy(dev);
	close(fd);
	printf("EGL-DMABUF-OK %dx%d\n", w, h);
	return 0;
}

int
main(int argc, char **argv)
{

	setvbuf(stdout, NULL, _IOLBF, 0);
	if (argc > 1 && strcmp(argv[1], "surfaceless") == 0)
		return surfaceless();
	if (argc > 1 && strcmp(argv[1], "gbm") == 0)
		return gbm(argc > 2 ? atoi(argv[2]) : 0);
	if (argc > 1 && strcmp(argv[1], "dmabuf") == 0)
		return dmabuf();
	fprintf(stderr, "usage: egl-gate surfaceless | gbm [hold] | dmabuf\n");
	return 2;
}
