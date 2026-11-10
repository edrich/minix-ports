/*
 * glbench - softpipe cost of the pieces of a GLES2 compositor frame, at a
 * given size (default 1024x768), on an EGL surfaceless pbuffer:
 *   clear    glClear of the whole target
 *   upload   glTexSubImage2D of a full-size BGRA client buffer (wl_shm)
 *   quad     a full-screen textured quad (compositing a window)
 *   tri      a full-screen interpolated-colour triangle pair (a GL client)
 * Each is run N times (default 20) followed by glFinish; prints
 * "GLBENCH <what> <ms per op>" and "GLBENCH-OK".
 *
 *   glbench [width height [n]]
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#define FAIL(...) do { printf("GLBENCH-FAIL: " __VA_ARGS__); \
	printf(" (egl 0x%x gl 0x%x)\n", eglGetError(), glGetError()); \
	exit(1); } while (0)

static double
now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static GLuint
program(const char *vs, const char *fs)
{
	const char *src[2] = { vs, fs };
	GLenum type[2] = { GL_VERTEX_SHADER, GL_FRAGMENT_SHADER };
	GLuint p = glCreateProgram();
	char log[512];
	GLint ok;

	for (int i = 0; i < 2; i++) {
		GLuint s = glCreateShader(type[i]);
		glShaderSource(s, 1, &src[i], NULL);
		glCompileShader(s);
		glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
		if (!ok) {
			glGetShaderInfoLog(s, sizeof(log), NULL, log);
			FAIL("shader: %s", log);
		}
		glAttachShader(p, s);
	}
	glBindAttribLocation(p, 0, "pos");
	glLinkProgram(p);
	glGetProgramiv(p, GL_LINK_STATUS, &ok);
	if (!ok)
		FAIL("link");
	return p;
}

int
main(int argc, char **argv)
{
	int w = argc > 2 ? atoi(argv[1]) : 1024;
	int h = argc > 2 ? atoi(argv[2]) : 768;
	int n = argc > 3 ? atoi(argv[3]) : 20;
	PFNEGLGETPLATFORMDISPLAYEXTPROC gpd = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
	    eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay dpy;
	EGLConfig cfg;
	EGLint cnt;
	static const EGLint cfg_attr[] = {
		EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RED_SIZE, 8,
		EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE
	};
	static const EGLint ctx_attr[] = { EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE };
	EGLint pb_attr[] = { EGL_WIDTH, w, EGL_HEIGHT, h, EGL_NONE };

	setvbuf(stdout, NULL, _IOLBF, 0);
	if (gpd == NULL)
		FAIL("no eglGetPlatformDisplayEXT");
	dpy = gpd(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
	if (dpy == EGL_NO_DISPLAY || !eglInitialize(dpy, NULL, NULL))
		FAIL("display");
	eglBindAPI(EGL_OPENGL_ES_API);
	if (!eglChooseConfig(dpy, cfg_attr, &cfg, 1, &cnt) || cnt < 1)
		FAIL("config");
	EGLSurface surf = eglCreatePbufferSurface(dpy, cfg, pb_attr);
	EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attr);
	if (surf == EGL_NO_SURFACE || ctx == EGL_NO_CONTEXT ||
	    !eglMakeCurrent(dpy, surf, surf, ctx))
		FAIL("context");
	printf("GLBENCH %dx%d n=%d renderer %s\n", w, h, n,
	    (const char *)glGetString(GL_RENDERER));
	glViewport(0, 0, w, h);

	GLuint tex_prog = program(
	    "attribute vec2 pos;\nvarying vec2 uv;\n"
	    "void main() { uv = pos * 0.5 + 0.5;\n"
	    "  gl_Position = vec4(pos, 0.0, 1.0); }\n",
	    "precision mediump float;\nvarying vec2 uv;\n"
	    "uniform sampler2D tex;\nuniform float alpha;\n"
	    "void main() { gl_FragColor = texture2D(tex, uv) * alpha; }\n");
	GLuint col_prog = program(
	    "attribute vec2 pos;\nvarying vec3 c;\n"
	    "void main() { c = vec3(pos.x * 0.5 + 0.5, pos.y * 0.5 + 0.5, 0.5);\n"
	    "  gl_Position = vec4(pos, 0.0, 1.0); }\n",
	    "precision mediump float;\nvarying vec3 c;\n"
	    "void main() { gl_FragColor = vec4(c, 1.0); }\n");
	static const GLfloat quad[] = { -1, -1, 1, -1, -1, 1, 1, 1 };
	glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
	glEnableVertexAttribArray(0);

	uint32_t *pix = malloc((size_t)w * h * 4);
	for (int i = 0; i < w * h; i++)
		pix[i] = 0xff000000u | (uint32_t)(i * 2654435761u >> 8);
	GLuint tex;
	glGenTextures(1, &tex);
	glBindTexture(GL_TEXTURE_2D, tex);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_BGRA_EXT, w, h, 0, GL_BGRA_EXT,
	    GL_UNSIGNED_BYTE, pix);
	glFinish();

	double t;
	/* clear */
	t = now_ms();
	for (int i = 0; i < n; i++) {
		glClearColor(0.1f * (i & 1), 0.2f, 0.3f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		glFinish();
	}
	printf("GLBENCH clear %.2f ms\n", (now_ms() - t) / n);
	/* upload */
	t = now_ms();
	for (int i = 0; i < n; i++) {
		pix[i] ^= 0xffffff;
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h, GL_BGRA_EXT,
		    GL_UNSIGNED_BYTE, pix);
		glFinish();
	}
	printf("GLBENCH upload %.2f ms\n", (now_ms() - t) / n);
	/* textured quad */
	glUseProgram(tex_prog);
	glUniform1i(glGetUniformLocation(tex_prog, "tex"), 0);
	glUniform1f(glGetUniformLocation(tex_prog, "alpha"), 1.0f);
	t = now_ms();
	for (int i = 0; i < n; i++) {
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glFinish();
	}
	printf("GLBENCH quad %.2f ms\n", (now_ms() - t) / n);
	/* the same with GL_NEAREST (identical result when drawn 1:1) */
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	t = now_ms();
	for (int i = 0; i < n; i++) {
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glFinish();
	}
	printf("GLBENCH quad-nearest %.2f ms\n", (now_ms() - t) / n);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	/* a power-of-two texture (softpipe has POT fast paths) */
	{
		int pw = 1, ph = 1;
		while (pw < w) pw <<= 1;
		while (ph < h) ph <<= 1;
		GLuint t2;
		uint32_t *p2 = calloc((size_t)pw * ph, 4);
		glGenTextures(1, &t2);
		glBindTexture(GL_TEXTURE_2D, t2);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_BGRA_EXT, pw, ph, 0,
		    GL_BGRA_EXT, GL_UNSIGNED_BYTE, p2);
		for (int f = 0; f < 2; f++) {
			GLint flt = f ? GL_NEAREST : GL_LINEAR;
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, flt);
			glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, flt);
			t = now_ms();
			for (int i = 0; i < n; i++) {
				glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				glFinish();
			}
			printf("GLBENCH quad-pot-%s %.2f ms\n",
			    f ? "nearest" : "linear", (now_ms() - t) / n);
		}
		glDeleteTextures(1, &t2);
		free(p2);
		glBindTexture(GL_TEXTURE_2D, tex);
	}
	/* blended textured quad (alpha-premultiplied window composition) */
	glEnable(GL_BLEND);
	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
	glUniform1f(glGetUniformLocation(tex_prog, "alpha"), 0.9f);
	t = now_ms();
	for (int i = 0; i < n; i++) {
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glFinish();
	}
	printf("GLBENCH quad-blend %.2f ms\n", (now_ms() - t) / n);
	glDisable(GL_BLEND);
	/* interpolated colour */
	glUseProgram(col_prog);
	t = now_ms();
	for (int i = 0; i < n; i++) {
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glFinish();
	}
	printf("GLBENCH tri %.2f ms\n", (now_ms() - t) / n);
	if (glGetError() != GL_NO_ERROR)
		FAIL("gl error");
	eglTerminate(dpy);
	printf("GLBENCH-OK\n");
	return 0;
}
