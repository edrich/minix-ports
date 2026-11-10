/*
 * polllog.so - LD_PRELOAD debugging aid: log epoll_ctl() registrations
 * (with the kind of file each fd is) and epoll_wait()/poll() calls and
 * results to stderr, to see what an event loop waits for.  Build with
 * -static-libgcc (no RPATH: the base libgcc_s stub would be found).
 */
#include <sys/epoll.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void
out(const char *buf, int n)
{
	if (n > 0)
		write(STDERR_FILENO, buf, (size_t)n);
}

static const char *
kind(int fd, char *b, size_t len)
{
	struct stat st;

	if (fstat(fd, &st) != 0)
		return "badfd";
	if (S_ISCHR(st.st_mode))
		snprintf(b, len, "chr(%d,%d)", (int)major(st.st_rdev),
		    (int)minor(st.st_rdev));
	else if (S_ISSOCK(st.st_mode))
		snprintf(b, len, "sock");
	else if (S_ISFIFO(st.st_mode))
		snprintf(b, len, "fifo(ino %lu)", (unsigned long)st.st_ino);
	else
		snprintf(b, len, "mode %o", (unsigned)st.st_mode);
	return b;
}

int
epoll_ctl(int epfd, int op, int fd, struct epoll_event *ev)
{
	static int (*real)(int, int, int, struct epoll_event *);
	char buf[200], k[40];
	int r;

	if (real == NULL)
		real = (int (*)(int, int, int, struct epoll_event *))
		    dlsym(RTLD_NEXT, "epoll_ctl");
	r = real(epfd, op, fd, ev);
	out(buf, snprintf(buf, sizeof(buf),
	    "POLLLOG epoll_ctl ep %d op %d fd %d %s ev %#x -> %d\n", epfd, op,
	    fd, kind(fd, k, sizeof(k)), ev ? ev->events : 0, r));
	return r;
}

int
epoll_wait(int epfd, struct epoll_event *evs, int max, int timeout)
{
	static int (*real)(int, struct epoll_event *, int, int);
	static int n;
	char buf[200];
	int r, i;

	if (real == NULL)
		real = (int (*)(int, struct epoll_event *, int, int))
		    dlsym(RTLD_NEXT, "epoll_wait");
	if (n < 400)
		out(buf, snprintf(buf, sizeof(buf),
		    "POLLLOG epoll_wait ep %d timeout %d ...\n", epfd, timeout));
	r = real(epfd, evs, max, timeout);
	if (n++ < 400) {
		out(buf, snprintf(buf, sizeof(buf),
		    "POLLLOG epoll_wait ep %d -> %d\n", epfd, r));
		for (i = 0; i < r; i++)
			out(buf, snprintf(buf, sizeof(buf),
			    "POLLLOG   ev %#x data %#llx\n", evs[i].events,
			    (unsigned long long)evs[i].data.u64));
	}
	return r;
}

int
poll(struct pollfd *fds, nfds_t nfds, int timeout)
{
	static int (*real)(struct pollfd *, nfds_t, int);
	static int n;
	char buf[200], k[40];
	nfds_t i;
	int r;

	if (real == NULL)
		real = (int (*)(struct pollfd *, nfds_t, int))
		    dlsym(RTLD_NEXT, "poll");
	r = real(fds, nfds, timeout);
	if (n++ < 200) {
		out(buf, snprintf(buf, sizeof(buf),
		    "POLLLOG poll n %u timeout %d -> %d\n", (unsigned)nfds,
		    timeout, r));
		for (i = 0; i < nfds; i++)
			out(buf, snprintf(buf, sizeof(buf),
			    "POLLLOG   fd %d %s ev %#x rev %#x\n", fds[i].fd,
			    kind(fds[i].fd, k, sizeof(k)), fds[i].events,
			    fds[i].revents));
	}
	return r;
}
