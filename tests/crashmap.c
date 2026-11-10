/*
 * crashmap.so - LD_PRELOAD debugging aid for MINIX: on SIGSEGV/SIGBUS/
 * SIGILL/SIGFPE/SIGABRT, print the load address of every loaded object
 * (dl_iterate_phdr), then die with the original signal.  MINIX has no ASLR,
 * so with the kernel's stack trace of addresses, addr2line on the ports
 * tree resolves the frames:  offset = address - base.  Also prints the
 * faulting eip/esp/ebp and the top of the stack (MINIX passes the
 * sigcontext as the handler's third argument).
 */
#include <dlfcn.h>
#include <link.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int
print_obj(struct dl_phdr_info *info, size_t size, void *data)
{
	char buf[256];
	int n;

	(void)size; (void)data;
	n = snprintf(buf, sizeof(buf), "CRASHMAP %#lx %s\n",
	    (unsigned long)info->dlpi_addr,
	    info->dlpi_name && info->dlpi_name[0] ? info->dlpi_name : "(main)");
	if (n > 0)
		write(STDERR_FILENO, buf, (size_t)n < sizeof(buf) ? n : sizeof(buf));
	return 0;
}

static void
handler(int sig, int code, struct sigcontext *scp)
{
	char buf[160];
	int n = snprintf(buf, sizeof(buf), "CRASHMAP signal %d pid %d\n", sig,
	    (int)getpid());
	write(STDERR_FILENO, buf, n);
	(void)code;
	if (scp != NULL) {
		/* Faulting context and the top of its stack: the return
		 * addresses there locate the caller even when the PC is
		 * in unmapped memory (frame-pointer walks can skip it). */
		const unsigned long *sp = (const unsigned long *)scp->sc_esp;
		int i;

		n = snprintf(buf, sizeof(buf),
		    "CRASHMAP eip %#lx esp %#lx ebp %#lx\n",
		    (unsigned long)scp->sc_eip, (unsigned long)scp->sc_esp,
		    (unsigned long)scp->sc_ebp);
		write(STDERR_FILENO, buf, n);
		for (i = 0; i < 24; i += 4) {
			n = snprintf(buf, sizeof(buf),
			    "CRASHMAP stack+%02x %#lx %#lx %#lx %#lx\n", i * 4,
			    sp[i], sp[i + 1], sp[i + 2], sp[i + 3]);
			write(STDERR_FILENO, buf, n);
		}
	}
	dl_iterate_phdr(print_obj, NULL);
	signal(sig, SIG_DFL);
	raise(sig);
}

__attribute__((constructor)) static void
crashmap_init(void)
{
	static const int sigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT };
	unsigned i;

	for (i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++)
		signal(sigs[i], (void (*)(int))handler);
}
