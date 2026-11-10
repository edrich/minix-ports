/*
 * vrambench - CPU bandwidth of a /dev/drm0 dumb buffer mapping (bochs VRAM,
 * what softpipe renders into when wlroots scans out its GBM buffers)
 * against ordinary memory: memset writes, 32-bit reads, read-modify-write.
 * Prints "VRAMBENCH <mem> <op> <MB/s>" and "VRAMBENCH-OK".
 *
 *   vrambench [seconds-per-test]
 */
#include <sys/mman.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#define W 1024
#define H 768

static double
now(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static volatile uint32_t sink;

static void
bench(const char *mem, uint32_t *p, size_t size, double secs)
{
	static const char *ops[] = { "write", "read", "rmw" };
	size_t n = size / 4;

	for (int op = 0; op < 3; op++) {
		double t0 = now(), t;
		long iters = 0;
		do {
			if (op == 0)
				memset(p, iters & 0xff, size);
			else if (op == 1) {
				uint32_t s = 0;
				for (size_t i = 0; i < n; i++)
					s += p[i];
				sink = s;
			} else {
				for (size_t i = 0; i < n; i++)
					p[i] += 0x01010101;
			}
			iters++;
		} while ((t = now() - t0) < secs);
		printf("VRAMBENCH %s %s %.0f MB/s (%.2f ms per %zu KB)\n", mem,
		    ops[op], iters * (size / 1048576.0) / t, 1000 * t / iters,
		    size / 1024);
	}
}

int
main(int argc, char **argv)
{
	double secs = argc > 1 ? atof(argv[1]) : 2;
	uint32_t handle, pitch;
	uint64_t size, off;

	int fd = open("/dev/drm0", O_RDWR | O_CLOEXEC);
	if (fd < 0) { perror("/dev/drm0"); return 1; }
	if (drmModeCreateDumbBuffer(fd, W, H, 32, 0, &handle, &pitch, &size)) {
		perror("create dumb"); return 1;
	}
	if (drmModeMapDumbBuffer(fd, handle, &off)) {
		perror("map dumb"); return 1;
	}
	uint32_t *vram = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED,
	    fd, off);
	if (vram == MAP_FAILED) { perror("mmap"); return 1; }
	uint32_t *ram = malloc(size);
	if (!ram) return 1;
	memset(ram, 0, size);

	bench("ram", ram, size, secs);
	bench("vram", vram, size, secs);
	printf("VRAMBENCH-OK\n");
	return 0;
}
