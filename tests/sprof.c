/*
 * sprof.so - LD_PRELOAD sampling profiler for MINIX (no perf, no gprof
 * runtime for ports).  ITIMER_PROF (process CPU time; the timerfd shim uses
 * ITIMER_REAL) delivers SIGPROF at the clock rate; the handler takes the
 * interrupted PC from the sigcontext (MINIX passes it as the third handler
 * argument) and counts it in a lock-free table.  At exit (or SIGUSR2) it
 * writes /tmp/sprof.<pid>: "SPROF obj <base> <path>" lines for every
 * loaded object, then "SPROF pc <addr> <count>" lines.
 * tests/sprof-report.py resolves them with addr2line on the unstripped
 * ports tree.  Build with -static-libgcc (no RPATH: see PLAN.md).
 * SPROF_HZ (default 100) asks for that rate; MINIX delivers at most the
 * clock rate.
 */
#include <sys/time.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <link.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SLOTS	65536			/* power of two */

static volatile uintptr_t pcs[SLOTS];
static volatile unsigned int counts[SLOTS];
static volatile unsigned int total, lost;
static int out_fd = -1;

static void
on_prof(int sig, int code, struct sigcontext *scp)
{
	uintptr_t pc;
	unsigned int h, i;

	(void)sig; (void)code;
	if (scp == NULL)
		return;
	pc = (uintptr_t)scp->sc_eip;
	h = (unsigned int)(pc * 2654435761u) & (SLOTS - 1);
	for (i = 0; i < 64; i++, h = (h + 1) & (SLOTS - 1)) {
		if (pcs[h] == pc) {
			counts[h]++;
			total++;
			return;
		}
		if (pcs[h] == 0) {
			pcs[h] = pc;
			counts[h] = 1;
			total++;
			return;
		}
	}
	lost++;
}

static int
dump_obj(struct dl_phdr_info *info, size_t size, void *data)
{
	char buf[320];
	int n;

	(void)size; (void)data;
	n = snprintf(buf, sizeof(buf), "SPROF obj %#lx %s\n",
	    (unsigned long)info->dlpi_addr,
	    info->dlpi_name && info->dlpi_name[0] ? info->dlpi_name : "(main)");
	if (n > 0)
		write(out_fd, buf, (size_t)n);
	return 0;
}

static void
dump(void)
{
	struct itimerval off;
	char path[64], buf[96];
	unsigned int i;
	int n;

	memset(&off, 0, sizeof(off));
	setitimer(ITIMER_PROF, &off, NULL);
	snprintf(path, sizeof(path), "/tmp/sprof.%d", (int)getpid());
	if ((out_fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644)) < 0)
		return;
	n = snprintf(buf, sizeof(buf), "SPROF total %u lost %u\n", total, lost);
	write(out_fd, buf, (size_t)n);
	n = snprintf(buf, sizeof(buf), "SPROF main %s\n", getprogname());
	write(out_fd, buf, (size_t)n);
	dl_iterate_phdr(dump_obj, NULL);
	for (i = 0; i < SLOTS; i++) {
		if (pcs[i] == 0)
			continue;
		n = snprintf(buf, sizeof(buf), "SPROF pc %#lx %u\n",
		    (unsigned long)pcs[i], counts[i]);
		write(out_fd, buf, (size_t)n);
	}
	close(out_fd);
}

static void
on_usr2(int sig)
{
	(void)sig;
	dump();
}

__attribute__((constructor)) static void
sprof_init(void)
{
	struct sigaction sa;
	struct itimerval it;
	const char *hz = getenv("SPROF_HZ");
	long us = 1000000 / (hz != NULL && atoi(hz) > 0 ? atoi(hz) : 100);

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = (void (*)(int))on_prof;
	sa.sa_flags = SA_RESTART;
	sigaction(SIGPROF, &sa, NULL);
	signal(SIGUSR2, on_usr2);
	memset(&it, 0, sizeof(it));
	it.it_interval.tv_usec = us;
	it.it_value.tv_usec = us;
	setitimer(ITIMER_PROF, &it, NULL);
	atexit(dump);
}
